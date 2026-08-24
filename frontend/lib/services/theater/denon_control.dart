/// Denon AVR control over its telnet protocol (TCP 23, ASCII commands
/// terminated with CR). Used by the renderer client to switch the receiver to
/// its own input (and power it on) when playback starts — the "press Play and
/// the theater assembles itself" piece.
///
/// Protocol facts proven live on the X3700H (2026-08-23 session): `ZMON`
/// powers the main zone, `SI<name>` selects an input by its SOURCE name
/// (e.g. `SI8K`), `SSFUN<input> <label>` renames. The receiver answers every
/// command with event lines; we read briefly and move on — this is
/// fire-and-forget convenience, never something playback waits on.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DenonControl {
  DenonControl(this.host, {this.port = 23});

  final String host;
  final int port;

  /// Send [commands] in order over one connection. Returns the response lines
  /// seen (for diagnostics); errors are reported, not thrown — the AVR being
  /// off the network must never break playback.
  Future<List<String>> send(List<String> commands,
      {void Function(String line)? onDiag}) async {
    Socket? sock;
    final seen = <String>[];
    try {
      sock = await Socket.connect(host, port,
          timeout: const Duration(seconds: 3));
      final lines = utf8.decoder
          .bind(sock)
          .transform(const LineSplitter())
          .listen((l) => seen.add(l.trim()));
      for (final cmd in commands) {
        sock.add(ascii.encode('$cmd\r'));
        await sock.flush();
        // The Denon needs a beat between commands (its own docs say 200ms+);
        // power-on especially, before it will take an input switch.
        await Future.delayed(const Duration(milliseconds: 300));
      }
      // Brief grace for trailing event lines, then hang up.
      await Future.delayed(const Duration(milliseconds: 300));
      await lines.cancel();
      onDiag?.call('denon: sent ${commands.join(",")} → [${seen.join(" | ")}]');
    } catch (e) {
      onDiag?.call('denon: $host unreachable ($e)');
    } finally {
      sock?.destroy();
    }
    return seen;
  }

  /// Power the main zone and select [input] (a SOURCE name like `8K`).
  Future<void> powerAndSelect(String input,
          {bool power = true, void Function(String line)? onDiag}) =>
      send([if (power) 'ZMON', 'SI${input.toUpperCase()}'], onDiag: onDiag);
}
