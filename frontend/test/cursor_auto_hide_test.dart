import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nascinema/widgets/cursor_auto_hide.dart';

void main() {
  testWidgets('keyboard hides the cursor even over a button; mouse brings it back',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => CursorAutoHide(child: child!),
      // A child that asks for its own cursor, like every button does.
      home: const Center(
        child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('Play')),
      ),
    ));
    MouseCursor cursor() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Play')));
    await tester.pump();
    expect(cursor(), SystemMouseCursors.click);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(cursor(), SystemMouseCursors.none);

    await mouse.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(cursor(), SystemMouseCursors.click);
  });
}
