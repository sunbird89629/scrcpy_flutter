import 'dart:convert';
import 'dart:io';

import 'package:logger_utils/logger_utils.dart';

import 'sop_record.dart';

final _log = Logger('scrcpy.mcp.sop.store');

/// Reads/writes SOP records as JSONL, one file per app package under
/// `<baseDir>/sop/<package>.jsonl`.
class SopStore {
  SopStore(this._baseDir);

  final String _baseDir;

  File _fileFor(String package) => File('$_baseDir/sop/$package.jsonl');

  Future<List<SopRecord>> load(String package) async {
    final f = _fileFor(package);
    if (!f.existsSync()) return const [];
    final out = <SopRecord>[];
    for (final line in await f.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(SopRecord.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (e) {
        _log.warning('skip corrupt SOP line in ${f.path}: $e');
      }
    }
    return out;
  }

  Future<void> append(SopRecord record) async {
    final f = _fileFor(record.package);
    await f.parent.create(recursive: true);
    await f.writeAsString(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
    );
  }
}
