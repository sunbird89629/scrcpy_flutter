import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_plus/device/pairing_service.dart';

void main() {
  group('PairingService', () {
    test('validateAddress accepts valid IP:port', () {
      expect(PairingService.validateAddress('192.168.1.100:5555'), isNull);
    });

    test('validateAddress rejects missing port', () {
      expect(PairingService.validateAddress('192.168.1.100'), isNotNull);
    });

    test('validateAddress rejects empty string', () {
      expect(PairingService.validateAddress(''), isNotNull);
    });

    test('validatePairingCode accepts 6-digit code', () {
      expect(PairingService.validatePairingCode('123456'), isNull);
    });

    test('validatePairingCode rejects short code', () {
      expect(PairingService.validatePairingCode('12345'), isNotNull);
    });

    test('validatePairingCode rejects non-numeric', () {
      expect(PairingService.validatePairingCode('abcdef'), isNotNull);
    });
  });
}
