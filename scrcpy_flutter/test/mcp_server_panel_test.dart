import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_flutter/mcp_server_controller.dart';
import 'package:scrcpy_flutter/mcp_server_panel.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class _MockAdb implements ScrcpyAdb {
  @override
  Future<List<String>> getDevices() async => [];
  @override
  Future<ProcessResult> shell(List<String> a,
          {String? deviceId,
          Duration timeout = const Duration(seconds: 30)}) async =>
      ProcessResult(0, 0, '', '');
  @override
  Future<void> forward(String l, String r,
      {String? deviceId, bool noRebind = false}) async {}
  @override
  Future<void> forwardRemove(String l, {String? deviceId}) async {}
  @override
  Future<void> push(String lp, String rp, {String? deviceId}) async {}
  @override
  Future<Uint8List> takeScreenshot(String d) async => Uint8List(0);
  @override
  Future<Process> startProcess(List<String> arguments) =>
      throw UnimplementedError();
}

class _MockViewController extends ScrcpyViewController {
  _MockViewController() : super(adb: _MockAdb());
}

/// Fake controller that doesn't bind a real port, for widget-only tests.
class _FakeController extends McpServerController {
  _FakeController() : super(session: _MockViewController(), adb: _MockAdb());

  bool _fakeRunning = false;
  String? _fakeUrl;

  @override
  bool get isRunning => _fakeRunning;

  @override
  String? get serverUrl => _fakeUrl;

  void fakeStart(String url) {
    _fakeRunning = true;
    _fakeUrl = url;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _fakeRunning = false;
    _fakeUrl = null;
    notifyListeners();
  }
}

Widget _wrap(McpServerController ctrl) => MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: ctrl,
          builder: (_, __) => McpServerPanel(controller: ctrl),
        ),
      ),
    );

void main() {
  testWidgets('shows port field and Start button when not running',
      (tester) async {
    final ctrl = _FakeController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(ctrl));

    expect(find.text('MCP Server'), findsOneWidget);
    expect(find.text('7070'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
  });

  testWidgets('shows URL and Stop button when running', (tester) async {
    final ctrl = _FakeController();
    addTearDown(ctrl.dispose);

    ctrl.fakeStart('http://localhost:19820/mcp');

    await tester.pumpWidget(_wrap(ctrl));
    await tester.pump();

    expect(find.textContaining('localhost:19820'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
  });

  testWidgets('panel renders without error in idle state', (tester) async {
    final ctrl = _FakeController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(ctrl));
    expect(find.byType(McpServerPanel), findsOneWidget);
  });
}
