import 'dart:collection';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_app/i18n/strings.g.dart';
import 'package:autoglm_app/pages/devices_page.dart';
import 'package:autoglm_app/providers/adb_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<DeviceInfo> devices, {AdbClient? adbClient}) {
  return ProviderScope(
    overrides: [
      adbDevicesWithInfoProvider.overrideWith((_) async => devices),
      if (adbClient != null)
        adbClientProvider.overrideWith((_) async => adbClient),
    ],
    child: TranslationProvider(
      child: const MaterialApp(home: DevicesPage()),
    ),
  );
}

class _FakeAdbClient extends AdbClient {
  _FakeAdbClient({
    List<Object>? connectResponses,
    List<Object>? pairResponses,
  })  : _connectQ = Queue.of(connectResponses ?? []),
        _pairQ = Queue.of(pairResponses ?? []);

  final Queue<Object> _connectQ;
  final Queue<Object> _pairQ;

  @override
  Future<String> connect(String ip, int port) async {
    final r = _connectQ.isNotEmpty ? _connectQ.removeFirst() : 'connected to $ip:$port';
    if (r is AdbException) throw r;
    return r as String;
  }

  @override
  Future<String> pair(String ip, int port, String code) async {
    final r = _pairQ.isNotEmpty ? _pairQ.removeFirst() : 'Successfully paired to $ip:$port';
    if (r is AdbException) throw r;
    return r as String;
  }

  @override
  Future<List<DeviceInfo>> getDevicesWithInfo() async => [];
}

void main() {
  setUpAll(LocaleSettings.useDeviceLocale);

  testWidgets('shows model name and online badge for online device',
      (tester) async {
    await tester.pumpWidget(
      _wrap([
        const DeviceInfo(
          serial: 'R3CN12345',
          status: DeviceStatus.online,
          model: 'Pixel 8 Pro',
          manufacturer: 'Google',
          androidVersion: '14',
          sdkVersion: 34,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pixel 8 Pro'), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
    expect(find.text('offline'), findsNothing);
  });

  testWidgets('shows serial as title when model is null (offline device)',
      (tester) async {
    await tester.pumpWidget(
      _wrap([
        const DeviceInfo(
          serial: 'emulator-5554',
          status: DeviceStatus.offline,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('emulator-5554'), findsWidgets); // title + serial row
    expect(find.text('offline'), findsOneWidget);
  });

  testWidgets('shows unauthorized badge for unauthorized device',
      (tester) async {
    await tester.pumpWidget(
      _wrap([
        const DeviceInfo(
          serial: '192.168.1.8:5555',
          status: DeviceStatus.unauthorized,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('unauthorized'), findsOneWidget);
  });

  testWidgets('shows no-device message when list is empty', (tester) async {
    await tester.pumpWidget(_wrap([]));
    await tester.pumpAndSettle();

    expect(find.text(t.devices_page.no_devices), findsOneWidget);
  });

  testWidgets('shows Wi-Fi icon for wireless serial', (tester) async {
    await tester.pumpWidget(
      _wrap([
        const DeviceInfo(
          serial: '192.168.1.5:5555',
          status: DeviceStatus.online,
          model: 'Xiaomi 14',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.wifi), findsOneWidget);
    expect(find.byIcon(Icons.usb), findsNothing);
  });

  testWidgets('shows USB icon for wired serial', (tester) async {
    await tester.pumpWidget(
      _wrap([
        const DeviceInfo(
          serial: 'R3CN12345',
          status: DeviceStatus.online,
          model: 'Pixel 8',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.usb), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsNothing);
  });

  group('_ConnectPairDialog', () {
    Future<void> openDialog(WidgetTester tester, {AdbClient? adbClient}) async {
      await tester.pumpWidget(_wrap([], adbClient: adbClient));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_link));
      await tester.pumpAndSettle();
    }

    testWidgets('shows IP and port fields but no code field initially',
        (tester) async {
      await openDialog(tester);
      expect(find.byKey(const Key('code_field')), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('connect success closes dialog and shows Snackbar',
        (tester) async {
      final client = _FakeAdbClient(
        connectResponses: ['connected to 192.168.1.1:5555'],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('192.168.1.1:5555'), findsOneWidget);
    });

    testWidgets('connect failure reveals code field', (tester) async {
      final client = _FakeAdbClient(
        connectResponses: [
          const AdbException('Connect failed: not paired'),
        ],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('code_field')), findsOneWidget);
    });

    testWidgets('empty IP shows invalid_ip Snackbar', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      expect(find.text(t.devices_page.invalid_ip), findsOneWidget);
    });

    testWidgets('port 0 shows invalid_port Snackbar', (tester) async {
      await openDialog(tester);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '0');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      expect(find.text(t.devices_page.invalid_port), findsOneWidget);
    });

    testWidgets('5-digit code shows invalid_code Snackbar', (tester) async {
      final client = _FakeAdbClient(
        connectResponses: [
          const AdbException('Connect failed: not paired'),
        ],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      // Now in Step 2 — enter 5-digit code
      await tester.enterText(find.byKey(const Key('code_field')), '12345');
      await tester.tap(find.text(t.devices_page.pair));
      await tester.pumpAndSettle();
      expect(find.text(t.devices_page.invalid_code), findsOneWidget);
    });

    testWidgets('pair success closes dialog and shows paired_and_connected',
        (tester) async {
      final client = _FakeAdbClient(
        connectResponses: [
          const AdbException('Connect failed: not paired'), // Step 1 fails
          'connected to 192.168.1.1:5555', // auto-connect after pair
        ],
        pairResponses: ['Successfully paired to 192.168.1.1:5555'],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('code_field')), '123456');
      await tester.tap(find.text(t.devices_page.pair));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('192.168.1.1:5555'), findsOneWidget);
    });

    testWidgets('pair failure keeps dialog open and shows error Snackbar',
        (tester) async {
      final client = _FakeAdbClient(
        connectResponses: [
          const AdbException('Connect failed: not paired'),
        ],
        pairResponses: [
          const AdbException('Invalid pairing code'),
        ],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('code_field')), '123456');
      await tester.tap(find.text(t.devices_page.pair));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(t.devices_page.invalid_pairing_code), findsOneWidget);
    });
  });
}
