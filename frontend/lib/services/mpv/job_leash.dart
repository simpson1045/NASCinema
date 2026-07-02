/// Kernel-level leash for spawned mpv processes: a Windows Job Object with
/// KILL_ON_CLOSE. Every mpv we launch gets assigned to the job; when THIS
/// process exits — clean close, crash, Task Manager, anything — Windows
/// itself terminates every process in the job instantly.
///
/// Exists because orphaned mpvs kept playing (audio and all) after the app
/// closed during the multi-instance incident. Dart-side cleanup can always be
/// skipped by a hard kill; the kernel cannot.
library;

import 'dart:ffi';

final DynamicLibrary _k32j = DynamicLibrary.open('kernel32.dll');

final _createJobObjectW = _k32j.lookupFunction<
    IntPtr Function(Pointer<Void>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Void>)>('CreateJobObjectW');

final _setInformationJobObject = _k32j.lookupFunction<
    Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
    int Function(int, int, Pointer<Void>, int)>('SetInformationJobObject');

final _assignProcessToJobObject = _k32j.lookupFunction<
    Int32 Function(IntPtr, IntPtr),
    int Function(int, int)>('AssignProcessToJobObject');

final _openProcess = _k32j.lookupFunction<
    IntPtr Function(Uint32, Int32, Uint32),
    int Function(int, int, int)>('OpenProcess');

final _closeHandleJ = _k32j
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

/// JOBOBJECT_EXTENDED_LIMIT_INFORMATION (x64 layout, 144 bytes).
final class _JobExtLimits extends Struct {
  @Int64()
  external int perProcessUserTimeLimit;
  @Int64()
  external int perJobUserTimeLimit;
  @Uint32()
  external int limitFlags;
  @Uint64()
  external int minWorkingSet;
  @Uint64()
  external int maxWorkingSet;
  @Uint32()
  external int activeProcessLimit;
  @Uint64()
  external int affinity;
  @Uint32()
  external int priorityClass;
  @Uint32()
  external int schedulingClass;
  @Uint64()
  external int ioReadOps;
  @Uint64()
  external int ioWriteOps;
  @Uint64()
  external int ioOtherOps;
  @Uint64()
  external int ioReadBytes;
  @Uint64()
  external int ioWriteBytes;
  @Uint64()
  external int ioOtherBytes;
  @IntPtr()
  external int processMemoryLimit;
  @IntPtr()
  external int jobMemoryLimit;
  @IntPtr()
  external int peakProcessMemory;
  @IntPtr()
  external int peakJobMemory;
}

const _jobObjectExtendedLimitInformation = 9;
const _jobObjectLimitKillOnClose = 0x2000;
const _processSetQuota = 0x0100;
const _processTerminate = 0x0001;

int? _job;

int _ensureJob() {
  if (_job != null) return _job!;
  final job = _createJobObjectW(nullptr, nullptr);
  if (job != 0) {
    // calloc-free zeroing via Dart: allocate + zero manually with a Pointer.
    final info = _alloc();
    info.ref.limitFlags = _jobObjectLimitKillOnClose;
    _setInformationJobObject(job, _jobObjectExtendedLimitInformation,
        info.cast(), sizeOf<_JobExtLimits>());
    _free(info);
  }
  _job = job;
  return job;
}

Pointer<_JobExtLimits> _alloc() {
  final p = _k32Alloc(sizeOf<_JobExtLimits>());
  return p.cast();
}

// Minimal zeroing allocator (GlobalAlloc GPTR = fixed + zeroed) so this file
// doesn't need package:ffi's calloc.
final _globalAlloc = _k32j.lookupFunction<
    Pointer<Void> Function(Uint32, IntPtr),
    Pointer<Void> Function(int, int)>('GlobalAlloc');
final _globalFree = _k32j.lookupFunction<
    Pointer<Void> Function(Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>)>('GlobalFree');

Pointer<Void> _k32Alloc(int bytes) => _globalAlloc(0x0040, bytes); // GPTR
void _free(Pointer p) => _globalFree(p.cast());

/// Chain [pid] to the app's lifetime. Best-effort: failure just means the old
/// (leak-prone) behavior, never an error surfaced to playback.
void leashProcess(int pid) {
  try {
    final job = _ensureJob();
    if (job == 0) return;
    final h = _openProcess(_processSetQuota | _processTerminate, 0, pid);
    if (h == 0) return;
    _assignProcessToJobObject(job, h);
    _closeHandleJ(h);
  } catch (_) {}
}
