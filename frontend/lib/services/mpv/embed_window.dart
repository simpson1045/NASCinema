/// Native child window inside the Flutter root window — the surface mpv
/// renders into (`--wid`). mpv keeps its own d3d11/gpu-next pipeline (full
/// 4K HDR Dolby Vision + exclusive audio), it just paints inside our window:
/// the single-window UX with none of the ANGLE-texture limitations.
///
/// The child uses the stock `STATIC` window class (SS_BLACKRECT) so nothing
/// has to be registered from Dart. It sits above the FLUTTERVIEW sibling in
/// z-order, covering exactly the video rect the player layout reports —
/// Flutter widgets around that rect (top bar, control bar) stay live.
library;

import 'dart:ffi';
import 'dart:ui' show Rect;

import 'package:ffi/ffi.dart';

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

final _findWindowW = _user32.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
    int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');

final _createWindowExW = _user32.lookupFunction<
    IntPtr Function(Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32, Int32,
        Int32, Int32, Int32, IntPtr, IntPtr, IntPtr, Pointer<Void>),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int,
        int, int, int, Pointer<Void>)>('CreateWindowExW');

final _setWindowPos = _user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int)>('SetWindowPos');

final _destroyWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow');

final _showWindow = _user32.lookupFunction<Int32 Function(IntPtr, Int32),
    int Function(int, int)>('ShowWindow');

final _findWindowExW = _user32.lookupFunction<
    IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
    int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final _getWindowRect = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<_Rect>),
    int Function(int, Pointer<_Rect>)>('GetWindowRect');

final _setForegroundWindow = _user32.lookupFunction<Int32 Function(IntPtr),
    int Function(int)>('SetForegroundWindow');

const _wsChild = 0x40000000;
const _wsVisible = 0x10000000;
const _wsClipSiblings = 0x04000000;
const _ssBlackRect = 0x00000004;
const _hwndTop = 0;
const _swpNoActivate = 0x0010;
const _swpShowWindow = 0x0040;

/// The video-hosting child window. Coordinates are PHYSICAL pixels relative
/// to the root window's client area — which is exactly Flutter's logical
/// coordinate space multiplied by the devicePixelRatio, since the Flutter
/// view fills the client area.
class EmbedWindow {
  EmbedWindow._(this.hwnd, this._root);

  final int hwnd;
  final int _root;
  Rect _bounds = Rect.zero;

  /// Find the app's root window and create the child over [physicalBounds].
  /// Returns null if the root can't be found (never expected in practice).
  static EmbedWindow? create(Rect physicalBounds) {
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final root = _findWindowW(cls, nullptr);
    calloc.free(cls);
    if (root == 0) return null;

    final staticCls = 'STATIC'.toNativeUtf16();
    final none = ''.toNativeUtf16();
    final h = _createWindowExW(
      0,
      staticCls,
      none,
      _wsChild | _wsVisible | _wsClipSiblings | _ssBlackRect,
      physicalBounds.left.round(),
      physicalBounds.top.round(),
      physicalBounds.width.round(),
      physicalBounds.height.round(),
      root,
      0,
      0,
      nullptr,
    );
    calloc.free(staticCls);
    calloc.free(none);
    if (h == 0) return null;

    final w = EmbedWindow._(h, root);
    w._bounds = physicalBounds;
    // Above the FLUTTERVIEW sibling so the video is actually visible.
    _setWindowPos(h, _hwndTop, physicalBounds.left.round(),
        physicalBounds.top.round(), physicalBounds.width.round(),
        physicalBounds.height.round(), _swpNoActivate | _swpShowWindow);
    return w;
  }

  /// Track the Flutter video area (layout/resize). No-op when unchanged, so
  /// callers can invoke this freely from frame callbacks.
  void setBounds(Rect physicalBounds) {
    if (physicalBounds == _bounds) return;
    _bounds = physicalBounds;
    _setWindowPos(hwnd, _hwndTop, physicalBounds.left.round(),
        physicalBounds.top.round(), physicalBounds.width.round(),
        physicalBounds.height.round(), _swpNoActivate);
    fitInner();
  }

  /// mpv creates its own window INSIDE ours, sized once at attach — it does
  /// not follow parent resizes (video stayed launch-sized inside a maximized
  /// window, boxed in black — happened live). Keep it stretched to our
  /// client area. Cheap; safe to call from the periodic tracker.
  void fitInner() {
    final inner = _findWindowExW(hwnd, 0, nullptr, nullptr);
    if (inner == 0) return;
    final w = _bounds.width.round();
    final h = _bounds.height.round();
    final rc = calloc<_Rect>();
    try {
      if (_getWindowRect(inner, rc) != 0 &&
          (rc.ref.right - rc.ref.left != w ||
              rc.ref.bottom - rc.ref.top != h)) {
        _setWindowPos(inner, 0, 0, 0, w, h, _swpNoActivate);
      }
    } finally {
      calloc.free(rc);
    }
  }

  /// mpv's window grabs focus when it spawns; hand keyboard control back to
  /// the app (the F11/space/arrow handlers live in Flutter).
  void focusApp() => _setForegroundWindow(_root);

  /// One-line geometry snapshot (host + mpv inner window, screen coords) for
  /// the diag log — remote sessions can't enumerate our windows, so the app
  /// reports its own.
  String debugGeometry() {
    final rc = calloc<_Rect>();
    try {
      String rect(int h) {
        if (h == 0 || _getWindowRect(h, rc) == 0) return '?';
        return '${rc.ref.left},${rc.ref.top} ${rc.ref.right - rc.ref.left}x${rc.ref.bottom - rc.ref.top}';
      }

      final host = rect(hwnd);
      final inner = rect(_findWindowExW(hwnd, 0, nullptr, nullptr));
      return 'host[$host] inner[$inner] wanted[${_bounds.width.round()}x${_bounds.height.round()}]';
    } finally {
      calloc.free(rc);
    }
  }

  /// Hide/show the video surface. Native airspace sits above every Flutter
  /// widget, so modal sheets/dialogs would open BEHIND the movie — the player
  /// hides the video while an overlay is up (audio keeps playing) and brings
  /// it back on dismiss. SW_HIDE=0 / SW_SHOWNA=8 (show without stealing focus).
  void setVisible(bool visible) => _showWindow(hwnd, visible ? 8 : 0);

  void destroy() => _destroyWindow(hwnd);
}
