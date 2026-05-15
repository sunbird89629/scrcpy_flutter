import 'package:scrcpy_client/scrcpy_client.dart';

/// A hand-rolled mock of [ScrcpyDeviceProvisioner] for unit tests.
///
/// Exposes public mutable fields for call tracking and failure injection.
class MockDeviceProvisioner implements ScrcpyDeviceProvisioner {
  MockDeviceProvisioner({
    this.deviceId = 'test-device',
    this.port = 27183,
    this.options = const ScrcpyServerOptions(),
  });

  @override
  final String deviceId;

  @override
  final int port;

  @override
  final ScrcpyServerOptions options;

  @override
  int actualPort = 27183;

  bool provisionCalled = false;
  bool depovisionCalled = false;

  bool shouldProvisionFail = false;
  bool shouldDepovisionFail = false;

  @override
  Future<void> provision() async {
    provisionCalled = true;
    if (shouldProvisionFail) throw Exception('provision failed');
  }

  @override
  Future<void> depovision() async {
    depovisionCalled = true;
    if (shouldDepovisionFail) throw Exception('depovision failed');
  }
}
