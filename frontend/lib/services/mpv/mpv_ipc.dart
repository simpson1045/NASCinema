/// mpv JSON IPC protocol on top of [NamedPipeClient]: fire-and-forget or
/// awaited commands (request_id correlation) and property observation.
///
/// The controller keeps a local cache of observed properties, because the
/// player seam's accessors (`playerCurrentTime()` etc.) are synchronous polls
/// — mpv pushes changes here, the seam reads the cache.
library;

import 'dart:async';
import 'dart:convert';

import 'named_pipe.dart';

class MpvIpc {
  MpvIpc._(this._pipe) {
    _sub = _pipe.lines.listen(_onLine);
  }

  final NamedPipeClient _pipe;
  StreamSubscription<String>? _sub;
  int _nextRequestId = 1;
  int _nextObserveId = 1;
  final _pending = <int, Completer<dynamic>>{};
  final _observers = <int, void Function(dynamic value)>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// Raw mpv events (start-file, end-file, ...) for anyone who cares.
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Completes when mpv goes away (process quit / pipe dropped).
  Future<void> get done => _pipe.done;

  /// Connect to `\\.\pipe\<pipeName>` (retries until mpv creates it).
  static Future<MpvIpc?> connect(
    String pipeName, {
    Duration timeout = const Duration(seconds: 10),
    void Function(String line)? onDiag,
  }) async {
    final pipe = await NamedPipeClient.connect(pipeName,
        timeout: timeout, onDiag: onDiag);
    return pipe == null ? null : MpvIpc._(pipe);
  }

  void _onLine(String line) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return; // not JSON — ignore
    }
    final reqId = msg['request_id'];
    if (reqId is int && _pending.containsKey(reqId)) {
      final c = _pending.remove(reqId)!;
      if (msg['error'] == 'success') {
        c.complete(msg['data']);
      } else {
        c.complete(null); // soft-fail; callers treat null as "unavailable"
      }
      return;
    }
    if (msg['event'] == 'property-change') {
      final cb = _observers[msg['id']];
      if (cb != null) cb(msg['data']);
      return;
    }
    if (msg['event'] != null && !_events.isClosed) _events.add(msg);
  }

  /// Fire-and-forget command, e.g. `command(['seek', 30, 'relative'])`.
  void command(List<Object?> args) =>
      _pipe.send(jsonEncode({'command': args}));

  /// Command whose reply we want, e.g. `await get('time-pos')`.
  Future<dynamic> request(List<Object?> args) {
    final id = _nextRequestId++;
    final c = Completer<dynamic>();
    _pending[id] = c;
    _pipe.send(jsonEncode({'command': args, 'request_id': id, 'async': true}));
    // Don't leak completers if mpv dies mid-request.
    return c.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _pending.remove(id);
      return null;
    });
  }

  Future<dynamic> get(String property) =>
      request(['get_property', property]);

  void set(String property, Object? value) =>
      command(['set_property', property, value]);

  /// Push-updates for [property] via [onChange] (fires once immediately with
  /// the current value, then on every change — mpv's observe semantics).
  void observe(String property, void Function(dynamic value) onChange) {
    final id = _nextObserveId++;
    _observers[id] = onChange;
    command(['observe_property', id, property]);
  }

  /// Ask mpv to exit, then release the pipe.
  Future<void> quit() async {
    command(['quit']);
    await close();
  }

  Future<void> close() async {
    await _sub?.cancel();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    _observers.clear();
    await _events.close();
    await _pipe.close();
  }
}
