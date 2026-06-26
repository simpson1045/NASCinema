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
/// Receiver, LOADs a video URL, and exposes transport/volume/subtitle controls
/// for the remote — all over a raw TLS socket, so it works on a plain-HTTP LAN
/// (no browser, no HTTPS). Lives app-level so the session survives navigation.
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

  int? _castingFileId;
  String _castingTitle = '';
  int? get castingFileId => _castingFileId;
  String get castingTitle => _castingTitle;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;

  // Receiver volume, kept in sync with RECEIVER_STATUS. controlType 'fixed'
  // (typical for a TV → eARC → AVR chain, where the AVR owns volume) means
  // SET_VOLUME is silently ignored — so the remote hides the volume keys.
  double _volume = 1.0;
  bool _muted = false;
  String? _volumeControlType;
  double get volume => _volume;
  bool get muted => _muted;
  bool get volumeControllable =>
      _volumeControlType != null && _volumeControlType != 'fixed';

  // Whether the cast media carries a subtitle track, and whether it's showing.
  bool _hasSubtitles = false;
  bool _subtitlesOn = false;
  bool get hasSubtitles => _hasSubtitles;
  bool get subtitlesOn => _subtitlesOn;

  /// Casting is available on this platform (native socket stack present).
  bool get supported => true;

  StreamSubscription? _msgSub;
  StreamSubscription? _stateSub;
  Timer? _poll;

  Future<void> discover(
      {Duration timeout = const Duration(seconds: 8)}) async {
    if (_discovering) return;
    _discovering = true;
    _devices.clear();
    notifyListeners();
    try {
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

  Future<bool> connect(CastDevice device) async {
    if (isConnected && _connected?.serviceName == device.serviceName) {
      return true;
    }
    await _cleanup();
    try {
      final session = await CastSessionManager().startSession(device);
      _session = session;
      final connected = Completer<bool>();
      _stateSub = session.stateStream.listen((state) {
        if (state == CastSessionState.connected) {
          _connected = device;
          _startPolling();
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

  Future<void> castVideo({
    required int fileId,
    required String url,
    required String contentType,
    required String title,
    String? subUrl,
  }) async {
    final s = _session;
    if (s == null || !isConnected) return;
    _castingFileId = fileId;
    _castingTitle = title;
    _position = Duration.zero;
    _duration = Duration.zero;
    _hasSubtitles = subUrl != null && subUrl.isNotEmpty;
    _subtitlesOn = _hasSubtitles;
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
    if (_hasSubtitles) {
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
    notifyListeners();
  }

  void play() => _media({'type': 'PLAY'});
  void pause() => _media({'type': 'PAUSE'});
  void stop() => _media({'type': 'STOP'});
  void seekTo(double seconds) {
    _position = Duration(milliseconds: (seconds * 1000).round());
    notifyListeners();
    _media({'type': 'SEEK', 'currentTime': seconds});
  }

  /// Show/hide the subtitle track on the receiver (EDIT_TRACKS_INFO).
  void toggleSubtitles() {
    final s = _session;
    if (s == null || _mediaSessionId == null || !_hasSubtitles) return;
    _subtitlesOn = !_subtitlesOn;
    s.sendMessage(CastSession.kNamespaceMedia, {
      'type': 'EDIT_TRACKS_INFO',
      'mediaSessionId': _mediaSessionId,
      'activeTrackIds': _subtitlesOn ? [1] : <int>[],
    });
    notifyListeners();
  }

  /// Set receiver volume (0..1). No-op when the chain reports it 'fixed'.
  void setVolume(double v) {
    final s = _session;
    if (s == null || !volumeControllable) return;
    final clamped = v.clamp(0.0, 1.0);
    s.sendMessage(CastSession.kNamespaceReceiver, {
      'type': 'SET_VOLUME',
      'volume': {'level': clamped},
    });
    _volume = clamped;
    notifyListeners();
  }

  void adjustVolume(double delta) => setVolume((_volume + delta).clamp(0.0, 1.0));

  void _media(Map<String, dynamic> msg) {
    final s = _session;
    if (s == null || _mediaSessionId == null) return;
    s.sendMessage(
        CastSession.kNamespaceMedia, {...msg, 'mediaSessionId': _mediaSessionId});
  }

  void _onMessage(Map<String, dynamic> m) {
    final type = m['type'];
    if (type == 'MEDIA_STATUS') {
      final list = m['status'] as List?;
      if (list == null || list.isEmpty) return;
      final st = list.first as Map<String, dynamic>;
      _mediaSessionId = st['mediaSessionId'] as int? ?? _mediaSessionId;
      _playerState = st['playerState'] as String? ?? _playerState;
      _isPlaying = _playerState == 'PLAYING';
      final ct = st['currentTime'];
      if (ct is num) _position = Duration(milliseconds: (ct * 1000).round());
      final media = st['media'];
      if (media is Map && media['duration'] is num) {
        _duration =
            Duration(milliseconds: ((media['duration'] as num) * 1000).round());
      }
      notifyListeners();
    } else if (type == 'RECEIVER_STATUS') {
      final status = m['status'] as Map<String, dynamic>?;
      final vol = status?['volume'] as Map<String, dynamic>?;
      if (vol != null) {
        final level = vol['level'];
        if (level is num) _volume = level.toDouble().clamp(0.0, 1.0);
        final mut = vol['muted'];
        if (mut is bool) _muted = mut;
        final ct = vol['controlType'];
        if (ct is String) _volumeControlType = ct;
        notifyListeners();
      }
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isConnected) return;
      if (_isPlaying && _duration > Duration.zero) {
        _position += const Duration(seconds: 1);
        if (_position > _duration) _position = _duration;
        notifyListeners();
      }
      final s = _session;
      if (s != null && _mediaSessionId != null) {
        s.sendMessage(CastSession.kNamespaceMedia,
            {'type': 'GET_STATUS', 'mediaSessionId': _mediaSessionId});
      }
    });
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
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _castingFileId = null;
    _castingTitle = '';
    _hasSubtitles = false;
    _subtitlesOn = false;
    _volumeControlType = null;
    notifyListeners();
  }

  Future<void> _cleanup() async {
    _poll?.cancel();
    _poll = null;
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
