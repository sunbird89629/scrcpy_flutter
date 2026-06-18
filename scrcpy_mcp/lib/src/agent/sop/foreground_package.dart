import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

final _log = Logger('scrcpy.mcp.sop.foreground');

/// Extracts the foreground app package from `dumpsys activity activities`
/// output by matching a `ResumedActivity: ActivityRecord{... u0 <pkg>/<act>}`
/// line. Returns null when no resumed activity is found.
String? parseForegroundPackage(String dumpsysOutput) {
  final re = RegExp(r'ResumedActivity.*?\bu\d+\s+([\w.]+)/');
  final m = re.firstMatch(dumpsysOutput);
  return m?.group(1);
}

/// Best-effort foreground package via adb. Returns null on any failure.
Future<String?> foregroundPackage(ScrcpyAdb adb, String deviceId) async {
  try {
    final r = await adb.shell(
      ['dumpsys', 'activity', 'activities'],
      deviceId: deviceId,
    );
    return parseForegroundPackage(r.stdout as String);
  } catch (e) {
    _log.warning('foreground package lookup failed: $e');
    return null;
  }
}
