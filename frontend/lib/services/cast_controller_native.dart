import 'dart:async';
import 'dart:io' show Platform;

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'cast/cast_device.dart';
import 'cast/cast_session.dart';
import 'cast/cast_session_manager.dart';

/// Native Chromecast sender (Android / desktop) over the pure-Dart CASTV2 stack
/// ported from NASRadio. Discovers via mDNS, connects to the Default Media
/// Receiver, and LOADs a video URL — all over a raw TLS socket, so it works on
/// a plain-HTTP LAN (no browser, no HTTPS requirement). This is the "phone as
/// remote" path; the web CAF sender was a dead end (Chrome needs HTTPS to cast).
class CastController extends ChangeNotifier {
  /// Default Media Receiver — plays HLS + a sidecar WebVTT track, and (unlike a
  /// custom HTTPS receiver) is allowed to load plain-HTTP LAN media.
  static const _defaultReceiver = 'CC1AD845';

  final List<CastDevice> _devices = [];
  List<CastDevice> get devices => List.unmodifiable(_devices);

  bool _discovering = false;
  bool get isDiscovering => _discovering;

  CastSession? _session;
  CastDevice? _connected;
  CastDevice? get connectedDevice => _connected;
  bool get isConnected => _connected != null;

  int? _mediaSessionId;
  String _playerState = 'IDLE';
  String get playerState => _playerState;

  /// Casting is available on this platform (native socket stack present).
  bool get supported => true;

  StreamSubscription? _msgSub;
  StreamSubscription? _stateSub;

  /// mDNS-discover `_googlecast._tcp` devices, pushing each into [devices] as it
  /// resolves so the picker populates live.
  Future<void> discover(
      {Duration timeout = const Duration(seconds: 8)}) async {
    if (_discovering) return;
    _discovering = true;
    _devices.clear();
    notifyListeners();
    try {
      // Android 13+ gates mDNS behind NEARBY_WIFI_DEVICES.
      if (Platform.isAndroid) {
        final st = await Permission.nearbyWifiDevices.request();
        if (!st.isGranted) {
          _discovering = false;
          notifyListeners();
          return;
        }
      }
      final discovery = BonsoirDiscovery(type: '_googlecast._tcp');
      await discovery.initialize();
      final done = Completer<void>();
      Timer(timeout, () {
        if (!done.isCompleted) done.complete();
      });
      final sub = discovery.eventStream?.listen((event) {
        if (event is BonsoirDiscoveryServiceResolvedEvent) {
          final s = event.service;
          final host = s.host ?? '';
          if (host.isEmpty) return;
          if (_devices.any((d) => d.serviceName == s.name)) return;
          _devices.add(CastDevice(
            serviceName: s.name,
            name: s.attributes['fn'] ?? s.name,
            host: host,
            port: s.port,
            extras: Map<String, String>.from(s.attributes),
          ));
          notifyListeners();
        } else if (event is BonsoirDiscoveryServiceFoundEvent) {
          // Must explicitly resolve to get host/port.
          try {
            discovery.serviceResolver.resolveService(event.service);
          } catch (_) {}
        }
      });
      await discovery.start();
      await done.future;
      await sub?.cancel();
      await discovery.stop();
    } catch (e) {
      debugPrint('[Cast] discovery failed: $e');
    }
    _discovering = false;
    notifyListeners();
  }

  /// Open a session and launch the Default Media Receiver. Returns true once the
  /// session reaches connected state.
  Future<bool> connect(CastDevice device) async {
    await _cleanup();
    try {
      final session = await CastSessionManager().startSession(device);
      _session = session;
      final connected = Completer<bool>();
      _stateSub = session.stateStream.listen((state) {
        if (state == CastSessionState.connected) {
          _connected = device;
          notifyListeners();
          if (!connected.isCompleted) connected.complete(true);
        } else if (state == CastSessionState.closed) {
          if (!connected.isCompleted) connected.complete(false);
          _onClosed();
        }
      });
      _msgSub = session.messageStream.listen(_onMessage);
      session.sendMessage(CastSession.kNamespaceReceiver,
          {'type': 'LAUNCH', 'appId': _defaultReceiver});
      final ok = await connected.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (!ok) await _cleanup();
      return ok;
    } catch (e) {
      debugPrint('[Cast] connect failed: $e');
      await _cleanup();
      return false;
    }
  }

  /// LOAD a video on the receiver. [subUrl] '' / null = no subtitle track.
  Future<void> castVideo({
    required String url,
    required String contentType,
    required String title,
    String? subUrl,
  }) async {
    final s = _session;
    if (s == null || !isConnected) return;
    final media = <String, dynamic>{
      'contentId': url,
      'contentType': contentType,
      'streamType': 'BUFFERED',
      'metadata': {'type': 0, 'metadataType': 0, 'title': title},
    };
    final load = <String, dynamic>{
      'type': 'LOAD',
      'autoPlay': true,
      'currentTime': 0,
      'media': media,
    };
    if (subUrl != null && subUrl.isNotEmpty) {
      media['tracks'] = [
        {
          'trackId': 1,
          'type': 'TEXT',
          'trackContentId': subUrl,
          'trackContentType': 'text/vtt',
          'subtype': 'SUBTITLES',
          'name': 'Subtitles',
          'language': 'en',
        }
      ];
      load['activeTrackIds'] = [1];
    }
    s.sendMessage(CastSession.kNamespaceMedia, load);
  }

  void play() => _media({'type': 'PLAY'});
  void pause() => _media({'type': 'PAUSE'});
  void stop() => _media({'type': 'STOP'});
  void seekTo(double seconds) =>
      _media({'type': 'SEEK', 'currentTime': seconds});

  void _media(Map<String, dynamic> msg) {
    final s = _session;
    if (s == null || _mediaSessionId == null) return;
    s.sendMessage(
        CastSession.kNamespaceMedia, {...msg, 'mediaSessionId': _mediaSessionId});
  }

  void _onMessage(Map<String, dynamic> m) {
    if (m['type'] != 'MEDIA_STATUS') return;
    final list = m['status'] as List?;
    if (list == null || list.isEmpty) return;
    final st = list.first as Map<String, dynamic>;
    _mediaSessionId = st['mediaSessionId'] as int? ?? _mediaSessionId;
    _playerState = st['playerState'] as String? ?? _playerState;
    notifyListeners();
  }

  Future<void> disconnect() async {
    final s = _session;
    if (s != null && _mediaSessionId != null) {
      s.sendMessage(CastSession.kNamespaceMedia,
          {'type': 'STOP', 'mediaSessionId': _mediaSessionId});
    }
    await _cleanup();
    _onClosed();
  }

  void _onClosed() {
    _connected = null;
    _mediaSessionId = null;
    _playerState = 'IDLE';
    notifyListeners();
  }

  Future<void> _cleanup() async {
    await _msgSub?.cancel();
    await _stateSub?.cancel();
    _msgSub = null;
    _stateSub = null;
    try {
      await _session?.close();
    } catch (_) {}
    _session = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
