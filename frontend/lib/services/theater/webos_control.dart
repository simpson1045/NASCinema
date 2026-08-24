/// LG webOS TV control over the SSAP websocket (the same channel aiowebostv
/// uses — proven against the C2 on 2026-08-23).
///
/// Why the client needs this at all: after a source reboot the C2 reads the
/// GPU's HDMI SPD infoframe and silently relabels the input as **PC**, and
/// LG's PC input mode grays out TruMotion/Real Cinema/film processing —
/// harsh 24p, no "butter". The fix that works (instant, options un-gray) is
/// `com.webos.service.eim/setDeviceInfo {id, label, icon}`; webOS 23 has no
/// UI for it. The guard below re-applies it whenever it flips back.
///
/// Connection notes: newer webOS firmware wants TLS on **3001** with a
/// self-signed cert (accept it); older accepts plain ws on 3000 — we try
/// both. First-time pairing pops an accept dialog on the TV and hands back a
/// client-key we persist; every later connect with that key is silent.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The standard SSAP permission manifest (same scope aiowebostv registers
/// with). Asking for the full set once beats re-pairing when a feature grows.
const _manifest = {
  'manifestVersion': 1,
  'permissions': [
    'LAUNCH', 'LAUNCH_WEBAPP', 'APP_TO_APP', 'CONTROL_AUDIO',
    'CONTROL_DISPLAY', 'CONTROL_INPUT_JOYSTICK', 'CONTROL_INPUT_MEDIA_RECORDING',
    'CONTROL_INPUT_MEDIA_PLAYBACK', 'CONTROL_INPUT_TV', 'CONTROL_POWER',
    'CONTROL_TV_SCREEN', 'READ_APP_STATUS', 'READ_CURRENT_CHANNEL',
    'READ_INPUT_DEVICE_LIST', 'READ_NETWORK_STATE', 'READ_RUNNING_APPS',
    'READ_TV_CHANNEL_LIST', 'WRITE_NOTIFICATION_TOAST', 'READ_POWER_STATE',
    'READ_COUNTRY_INFO', 'READ_SETTINGS', 'CONTROL_TV_STANBY',
    'CONTROL_FAVORITE_GROUP', 'CONTROL_USER_DEFINED', 'UPDATE_FROM_REMOTE_APP',
    'READ_LGE_TV_INPUT_EVENTS', 'READ_TV_CURRENT_TIME',
  ],
};

class WebOsControl {
  WebOsControl._(this._ws);

  final WebSocket _ws;
  final _replies = <String, Completer<Map<String, dynamic>>>{};
  int _nextId = 0;
  String? clientKey;

  /// Connect and register. [clientKey] null → first-time pairing: the TV
  /// shows an accept dialog and [pairingTimeout] applies; the granted key is
  /// in [WebOsControl.clientKey] afterwards — persist it.
  static Future<WebOsControl?> connect(
    String host, {
    String? clientKey,
    Duration pairingTimeout = const Duration(seconds: 60),
    void Function(String line)? onDiag,
  }) async {
    WebSocket? ws;
    // TLS first (current firmware), plain as fallback (older firmware).
    for (final url in ['wss://$host:3001', 'ws://$host:3000']) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4)
          ..badCertificateCallback = ((_, _, _) => true); // LG self-signed
        ws = await WebSocket.connect(url, customClient: client);
        onDiag?.call('webos: connected $url');
        break;
      } catch (e) {
        onDiag?.call('webos: $url failed ($e)');
      }
    }
    if (ws == null) return null;

    final c = WebOsControl._(ws);
    c.clientKey = clientKey;
    final registered = Completer<bool>();
    ws.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final type = msg['type'];
      if (type == 'registered') {
        c.clientKey =
            (msg['payload'] as Map?)?['client-key']?.toString() ?? c.clientKey;
        if (!registered.isCompleted) registered.complete(true);
        return;
      }
      if (type == 'error' && !registered.isCompleted) {
        onDiag?.call('webos: register error ${msg['error']}');
        registered.complete(false);
        return;
      }
      final id = msg['id']?.toString();
      // The pairing PROMPT arrives as a plain response to the register id —
      // not a reply to any request() caller. Only route real request ids.
      final waiter = id == null ? null : c._replies.remove(id);
      waiter?.complete((msg['payload'] as Map?)?.cast<String, dynamic>() ?? {});
    }, onDone: () {
      for (final w in c._replies.values) {
        if (!w.isCompleted) w.complete({});
      }
      c._replies.clear();
    }, onError: (_) {});

    ws.add(jsonEncode({
      'type': 'register',
      'id': 'register_0',
      'payload': {
        ..._manifest,
        'client-key': ?clientKey,
      },
    }));

    final ok = await registered.future
        .timeout(clientKey == null ? pairingTimeout : const Duration(seconds: 8),
            onTimeout: () => false);
    if (!ok) {
      onDiag?.call('webos: registration failed/timed out');
      ws.close();
      return null;
    }
    onDiag?.call('webos: registered (key ${c.clientKey == null ? "NONE" : "held"})');
    return c;
  }

  Future<Map<String, dynamic>> request(String uri,
      [Map<String, dynamic>? payload]) {
    final id = 'req_${_nextId++}';
    final waiter = Completer<Map<String, dynamic>>();
    _replies[id] = waiter;
    _ws.add(jsonEncode({
      'type': 'request',
      'id': id,
      'uri': uri.startsWith('ssap://') ? uri : 'ssap://$uri',
      'payload': ?payload,
    }));
    return waiter.future
        .timeout(const Duration(seconds: 6), onTimeout: () => {});
  }

  /// The PC-label guard. Reads the input list; if [inputId]'s label is "PC"
  /// (the SPD-infoframe auto-relabel), rewrites it to [label] so LG's PC mode
  /// stops gutting the film-processing options. Returns what it did.
  Future<String> ensureInputLabel(String inputId, String label) async {
    final list = await request('tv/getExternalInputList');
    final devices = (list['devices'] as List?) ?? const [];
    final input = devices.cast<Map?>().firstWhere(
        (d) => d?['id'] == inputId || d?['appId']?.toString().endsWith(inputId) == true,
        orElse: () => null);
    if (input == null) return 'input $inputId not found';
    final current = input['label']?.toString() ?? '';
    if (current != 'PC') return 'label ok ("$current")';
    await request('com.webos.service.eim/setDeviceInfo',
        {'id': inputId, 'label': label, 'icon': 'bluray.png'});
    return 'label was PC → set to "$label"';
  }

  /// Switch the TV to [inputId] (e.g. HDMI_2 = the Denon's output).
  Future<void> switchInput(String inputId) =>
      request('tv/switchInput', {'inputId': inputId});

  void close() {
    _ws.close();
  }
}
