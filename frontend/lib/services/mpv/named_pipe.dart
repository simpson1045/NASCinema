/// Windows named-pipe client for mpv's JSON IPC (`--input-ipc-server`).
///
/// Hand-rolled kernel32 FFI — no `win32` package. The design encodes the
/// hard-won lessons from the ELKO embed harness (see memory
/// `mpv-wid-embed-ipc-architecture`), where each of these was a live failure:
///
///  * The pipe handle MUST be opened overlapped (FILE_FLAG_OVERLAPPED). A
///    synchronous handle serializes reads against writes at the OS level, so
///    the bridge goes mute after ~1 command while a blocking read is pending.
///  * mpv replies to EVERY command; if nobody drains those replies both pipe
///    buffers fill and the whole IPC channel deadlocks. A dedicated reader
///    isolate drains continuously.
///  * Writes go through a writer isolate (its port is the queue), so the UI
///    isolate can never block on the pipe, no matter what mpv is doing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// --- kernel32 bindings (resolved per-isolate; top-level finals) -------------

final DynamicLibrary _k32 = DynamicLibrary.open('kernel32.dll');

final class _Overlapped extends Struct {
  @IntPtr()
  external int internal;
  @IntPtr()
  external int internalHigh;
  @Uint32()
  external int offset;
  @Uint32()
  external int offsetHigh;
  @IntPtr()
  external int hEvent;
}

final _createFileW = _k32.lookupFunction<
    IntPtr Function(
        Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr),
    int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int,
        int)>('CreateFileW');

// isLeaf on the quick calls so only pure Dart runs between an I/O call and
// the GetLastError that must immediately follow it (Dart runtime syscalls
// would clobber the thread's last-error).
final _readFile = _k32.lookupFunction<
    Int32 Function(
        IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<_Overlapped>),
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<_Overlapped>)>('ReadFile', isLeaf: true);

final _writeFile = _k32.lookupFunction<
    Int32 Function(
        IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<_Overlapped>),
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<_Overlapped>)>('WriteFile', isLeaf: true);

final _getLastError = _k32.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
    isLeaf: true);

final _createEventW = _k32.lookupFunction<
    IntPtr Function(Pointer<Void>, Int32, Int32, Pointer<Void>),
    int Function(Pointer<Void>, int, int, Pointer<Void>)>('CreateEventW');

final _resetEvent = _k32.lookupFunction<Int32 Function(IntPtr),
    int Function(int)>('ResetEvent', isLeaf: true);

// Blocking — deliberately NOT leaf; only ever called inside a worker isolate.
final _getOverlappedResult = _k32.lookupFunction<
    Int32 Function(IntPtr, Pointer<_Overlapped>, Pointer<Uint32>, Int32),
    int Function(
        int, Pointer<_Overlapped>, Pointer<Uint32>, int)>('GetOverlappedResult');

final _cancelIoEx = _k32.lookupFunction<
    Int32 Function(IntPtr, Pointer<_Overlapped>),
    int Function(int, Pointer<_Overlapped>)>('CancelIoEx');

final _closeHandle = _k32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

const _genericRead = 0x80000000;
const _genericWrite = 0x40000000;
const _openExisting = 3;
const _fileFlagOverlapped = 0x40000000;
const _invalidHandle = -1;
const _errorIoPending = 997;

// --- worker isolates ---------------------------------------------------------

/// Reader: blocking overlapped-read loop; ships raw chunks to the main
/// isolate (line assembly happens there). Sends `null` once on EOF/error.
void _readLoop(List<Object> init) {
  final send = init[0] as SendPort;
  final handle = init[1] as int;
  final buf = calloc<Uint8>(65536);
  final got = calloc<Uint32>();
  final ov = calloc<_Overlapped>();
  final ev = _createEventW(nullptr, 1, 0, nullptr);
  try {
    while (true) {
      _resetEvent(ev);
      ov.ref.internal = 0;
      ov.ref.internalHigh = 0;
      ov.ref.offset = 0;
      ov.ref.offsetHigh = 0;
      ov.ref.hEvent = ev;
      final ok = _readFile(handle, buf, 65536, got, ov);
      if (ok == 0) {
        if (_getLastError() != _errorIoPending) break;
        if (_getOverlappedResult(handle, ov, got, 1) == 0) break;
      }
      final n = got.value;
      if (n == 0) break;
      send.send(Uint8List.fromList(buf.asTypedList(n)));
    }
  } finally {
    send.send(null);
    calloc.free(buf);
    calloc.free(got);
    calloc.free(ov);
    _closeHandle(ev);
  }
}

/// Writer: its ReceivePort *is* the send queue. Strings arrive from the main
/// isolate, get a trailing `\n`, and are written with a blocking overlapped
/// write. A `null` message ends the loop.
void _writeLoop(List<Object> init) {
  final main = init[0] as SendPort;
  final handle = init[1] as int;
  final port = ReceivePort();
  main.send(port.sendPort);
  final got = calloc<Uint32>();
  final ov = calloc<_Overlapped>();
  final ev = _createEventW(nullptr, 1, 0, nullptr);
  port.listen((msg) {
    if (msg == null) {
      calloc.free(got);
      calloc.free(ov);
      _closeHandle(ev);
      port.close();
      return;
    }
    final bytes = utf8.encode('${msg as String}\n');
    final p = calloc<Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    _resetEvent(ev);
    ov.ref.internal = 0;
    ov.ref.internalHigh = 0;
    ov.ref.offset = 0;
    ov.ref.offsetHigh = 0;
    ov.ref.hEvent = ev;
    final ok = _writeFile(handle, p, bytes.length, got, ov);
    if (ok == 0 && _getLastError() == _errorIoPending) {
      _getOverlappedResult(handle, ov, got, 1);
    }
    calloc.free(p);
  });
}

// --- public client -----------------------------------------------------------

/// Duplex line-oriented client for `\\.\pipe\<name>`.
class NamedPipeClient {
  NamedPipeClient._(this._handle);

  final int _handle;
  Isolate? _reader;
  Isolate? _writer;
  SendPort? _writePort;
  final _lines = StreamController<String>.broadcast();
  final _closed = Completer<void>();
  String _pending = '';

  /// One JSON line per event, as mpv writes them.
  Stream<String> get lines => _lines.stream;

  /// Completes when the pipe drops (mpv quit) or [close] is called.
  Future<void> get done => _closed.future;

  /// Polls until mpv has created the pipe (it appears shortly after launch),
  /// then spins up the reader/writer isolates. Returns null on timeout.
  static Future<NamedPipeClient?> connect(
    String name, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final path = '\\\\.\\pipe\\$name'.toNativeUtf16();
    final deadline = DateTime.now().add(timeout);
    try {
      while (true) {
        final h = _createFileW(path, _genericRead | _genericWrite, 0, nullptr,
            _openExisting, _fileFlagOverlapped, 0);
        if (h != _invalidHandle) {
          final client = NamedPipeClient._(h);
          await client._start();
          return client;
        }
        if (DateTime.now().isAfter(deadline)) return null;
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      calloc.free(path);
    }
  }

  Future<void> _start() async {
    final fromRead = ReceivePort();
    fromRead.listen((msg) {
      if (msg == null) {
        fromRead.close();
        _shutdown();
        return;
      }
      // Assemble complete lines; a chunk can hold several or a partial one.
      _pending += utf8.decode(msg as Uint8List, allowMalformed: true);
      int i;
      while ((i = _pending.indexOf('\n')) >= 0) {
        final line = _pending.substring(0, i).trim();
        _pending = _pending.substring(i + 1);
        if (line.isNotEmpty && !_lines.isClosed) _lines.add(line);
      }
    });
    _reader = await Isolate.spawn(_readLoop, [fromRead.sendPort, _handle]);

    final fromWrite = ReceivePort();
    _writer = await Isolate.spawn(_writeLoop, [fromWrite.sendPort, _handle]);
    _writePort = await fromWrite.first as SendPort;
    fromWrite.close();
  }

  /// Queue one JSON line for mpv. Never blocks the caller.
  void send(String jsonLine) => _writePort?.send(jsonLine);

  void _shutdown() {
    if (_closed.isCompleted) return;
    _closed.complete();
    _writePort?.send(null);
    _reader?.kill(priority: Isolate.immediate);
    _writer?.kill(priority: Isolate.beforeNextEvent);
    _lines.close();
    _cancelIoEx(_handle, nullptr);
    _closeHandle(_handle);
  }

  Future<void> close() async => _shutdown();
}
