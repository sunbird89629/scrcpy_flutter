import 'package:adb_tools/adb_tools.dart';

/// Handles device pairing via IP+code and direct ADB connect.
class PairingService {
  PairingService({required this.adb});

  final AdbClient adb;

  /// Validate an IP:port address string. Returns null if valid, error message otherwise.
  static String? validateAddress(String address) {
    if (address.isEmpty) return 'Address cannot be empty';
    final parts = address.split(':');
    if (parts.length != 2) return 'Format must be IP:port';
    final port = int.tryParse(parts[1]);
    if (port == null || port <= 0 || port > 65535) return 'Invalid port number';
    return null;
  }

  /// Validate a 6-digit pairing code. Returns null if valid, error message otherwise.
  static String? validatePairingCode(String code) {
    if (code.length != 6) return 'Code must be 6 digits';
    if (int.tryParse(code) == null) return 'Code must be numeric';
    return null;
  }

  /// Pair with a device using IP, port, and pairing code.
  Future<String> pair(String ip, int port, String code) async {
    return adb.pair(ip, port, code);
  }

  /// Connect to a previously paired device.
  Future<String> connect(String ip, int port) async {
    return adb.connect(ip, port);
  }

  /// Disconnect a device.
  Future<void> disconnect(String serial) async {
    await adb.runner.run(adb.adbPath, ['disconnect', serial]);
  }
}
