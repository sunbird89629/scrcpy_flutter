import 'dart:io';
import 'package:flutter/material.dart';
import 'package:scrcpy_adapters/scrcpy_adapters.dart';

class SafeAdbClient extends AdbClientAdapter {
  SafeAdbClient() : super.withPath();

  @override
  Future<ProcessResult> shell(
    List<String> args, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await super.shell(args, deviceId: deviceId, timeout: timeout);
    } catch (e) {
      final cmd = args.join(' ');
      if (cmd.contains('pkill')) {
        debugPrint('SafeAdbClient: Ignoring pkill failure: $e');
        return ProcessResult(0, 0, '', '');
      }
      rethrow;
    }
  }
}
