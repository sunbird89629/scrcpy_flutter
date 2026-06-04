import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_plus/mcp/mcp_server_controller.dart';

// ---------------------------------------------------------------------------
// Minimal mock session — no real scrcpy JAR or ADB required
// ---------------------------------------------------------------------------

class _MockSession implements ScrcpySession {
  @override
  bool get isConnected => false;
  @override
  int? get videoWidth => null;
  @override
  int? get videoHeight => null;
  @override
  Future<void> start(
    String deviceId, {
    dynamic options,
    dynamic logger,
    void Function()? onStarted,
    void Function()? onStopped,
    void Function(String)? onError,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  void sendControlMessage(ScrcpyControlMessage message) {}
  @override
  void injectText(String text) {}
  @override
  Stream<ScrcpyDeviceMessage> get deviceMessages =>
      const Stream<ScrcpyDeviceMessage>.empty();
  @override
  Future<String> getClipboard({
    Duration timeout = const Duration(seconds: 5),
  }) => Future.value('');
}

void main() {
  group('McpServerController', () {
    test('serverUrl is null and not running before start', () {
      final controller = McpServerController(adb: const AdbClient());
      expect(controller.isRunning, false);
      expect(controller.serverUrl, isNull);
      expect(controller.errorMessage, isNull);
    });

    test('start exposes a localhost mcp url, stop tears it down', () async {
      final controller = McpServerController(
        adb: const AdbClient(),
        session: _MockSession(),
      );
      addTearDown(controller.stop);
      await controller.start(7099);
      expect(controller.errorMessage, isNull);
      expect(controller.isRunning, true);
      expect(controller.serverUrl, 'http://localhost:7099/mcp');
      await controller.stop();
      expect(controller.isRunning, false);
      expect(controller.serverUrl, isNull);
    });

    test(
      'start on an in-use port records errorMessage without throwing',
      () async {
        final first = McpServerController(
          adb: const AdbClient(),
          session: _MockSession(),
        );
        addTearDown(first.stop);
        await first.start(7098);
        final second = McpServerController(
          adb: const AdbClient(),
          session: _MockSession(),
        );
        await second.start(7098); // same port — should fail gracefully
        expect(second.isRunning, false);
        expect(second.errorMessage, isNotNull);
      },
    );

    test(
      'start() builds a session from bundled assets (no injected session)',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final controller = McpServerController(adb: const AdbClient());
        addTearDown(controller.stop);
        await controller.start(7095);
        expect(controller.errorMessage, isNull);
        expect(controller.isRunning, true);
        expect(controller.serverUrl, 'http://localhost:7095/mcp');
      },
    );

    test('start is a no-op when already running', () async {
      final controller = McpServerController(
        adb: const AdbClient(),
        session: _MockSession(),
      );
      addTearDown(controller.stop);
      await controller.start(7097);
      expect(controller.serverUrl, 'http://localhost:7097/mcp');
      await controller.start(7096); // ignored
      expect(controller.serverUrl, 'http://localhost:7097/mcp');
      expect(controller.errorMessage, isNull);
    });
  });
}
