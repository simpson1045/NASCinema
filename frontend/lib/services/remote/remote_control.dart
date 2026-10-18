/// Remote control: this app as a named player that the backend can drive
/// ("play Jurassic Park", "resume Whose Line", pause, seek, tracks …) — how
/// Claude runs movie night through ADMS house_cinema.
///
/// The app connects to the backend's Socket.IO server, says `player_hello`
/// with its name, and answers each `remote_command` with a result map (the
/// backend waits for it, so the caller hears "playing" or "NOT STARTED: why").
/// Status goes up every 5 s and after every command.
///
/// Two hooks do the work:
///   * [opener] — set by the Big Picture home: opens a movie/show page that
///     presses Play itself, so saved version/track picks, resume and Up Next
///     behave exactly as with the controller.
///   * [player] — set by the open player screen: pause/seek/tracks/version/…
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

typedef RemoteReply = Map<String, dynamic>;

/// What the open player screen registers while it's up.
class RemotePlayerHooks {
  RemotePlayerHooks({required this.status, required this.handle});

  final Map<String, dynamic> Function() status;
  final Future<RemoteReply> Function(String action, Map<String, dynamic> args) handle;
}

class RemoteControl {
  RemoteControl._();

  static const namePref = 'remote_player_name';

  static io.Socket? _socket;
  static Timer? _beat;
  static String _name = '';

  /// Opens a movie (`play_movie`) or episode (`play_episode`) page that plays
  /// on its own; completes when playback is under way (or failed).
  static Future<RemoteReply> Function(String action, Map<String, dynamic> args)? opener;

  /// The player screen that's up right now (null = nothing playing).
  static RemotePlayerHooks? player;

  /// Start once (Big Picture home). Native Windows only — the renderer.
  static Future<void> start(String baseUrl) async {
    if (kIsWeb || !Platform.isWindows || _socket != null) return;
    final prefs = await SharedPreferences.getInstance();
    _name = (prefs.getString(namePref) ?? '').trim();
    if (_name.isEmpty) _name = Platform.localHostname;
    String? version;
    try {
      final pkg = await PackageInfo.fromPlatform();
      version = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}

    final s = io.io(
      baseUrl,
      io.OptionBuilder()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(15000)
          .disableAutoConnect()
          .build(),
    );
    _socket = s;
    s.onConnect((_) {
      s.emitWithAck('player_hello', {'name': _name, 'version': version}, ack: (_) {
        sendStatus();
      });
    });
    s.on('remote_command', (payload) async {
      // With an ack the client hands us [data, ackFn]; without, just data.
      Map<String, dynamic> data = const {};
      Function? ack;
      if (payload is List && payload.isNotEmpty) {
        if (payload.last is Function) ack = payload.last as Function;
        if (payload.first is Map) data = Map<String, dynamic>.from(payload.first as Map);
      } else if (payload is Map) {
        data = Map<String, dynamic>.from(payload);
      }
      final reply = await _dispatch(data);
      ack?.call(reply);
      sendStatus();
    });
    s.connect();
    _beat = Timer.periodic(const Duration(seconds: 5), (_) => sendStatus());
  }

  static Future<RemoteReply> _dispatch(Map<String, dynamic> data) async {
    final action = (data['action'] ?? '').toString();
    try {
      if (action == 'play_movie' || action == 'play_episode') {
        final open = opener;
        if (open == null) {
          return {'ok': false, 'error': 'NOT STARTED: the app is not on the Big Picture home'};
        }
        return await open(action, data);
      }
      final p = player;
      if (p == null) return {'ok': false, 'error': 'nothing is playing'};
      return await p.handle(action, data);
    } catch (e) {
      return {'ok': false, 'error': '$action failed: $e'};
    }
  }

  static Map<String, dynamic> currentStatus() =>
      player?.status() ?? const {'state': 'idle'};

  static void sendStatus() {
    final s = _socket;
    if (s == null || !s.connected) return;
    try {
      s.emit('player_status', currentStatus());
    } catch (_) {}
  }

  /// Wait (up to [timeout]) until a player screen is up and mpv is running —
  /// how the opener knows "playing" is true before it answers.
  static Future<bool> waitForPlayback(bool Function() ready,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (player != null && ready()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  @visibleForTesting
  static void stop() {
    _beat?.cancel();
    _socket?.dispose();
    _socket = null;
  }
}
