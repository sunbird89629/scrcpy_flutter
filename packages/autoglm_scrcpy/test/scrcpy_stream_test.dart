import 'dart:async';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Scrcpy Stream Debug Tool',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      // 0. 初始化日志系统（不传路径，仅在终端打印）
      initAppLogger();
      print('\n[INFO] Logger initialized (terminal-only mode)');

      const adbClient = AdbClient();

      // 1. 获取设备
      final deviceSerials = await adbClient.devices();
      if (deviceSerials.isEmpty) {
        print('\n[ERROR] No Android devices found via ADB!');
        return;
      }

      final deviceId = deviceSerials.first;
      print('\n[INFO] Using device: $deviceId');

      // 2. 创建并启动服务
      final server = ScrcpyServer(
        adbClient: adbClient,
        deviceId: deviceId,
      );

      print('[INFO] Starting scrcpy-server on device...');
      await server.start();

      // 3. 等待代理就绪
      print(
          '[INFO] Waiting for proxy to be ready (buffering SPS/PPS/Keyframe)...',);
      await server.proxyReady.timeout(const Duration(seconds: 15));

      final url = server.proxyUrl;
      print('\n${'=' * 60}');
      print('🚀 SCRCPY 视频流已就绪！');
      print('TCP 地址: $url');
      print('=' * 60);

      print('\n你可以打开一个新的终端运行以下命令验证画面：');
      print('ffplay -vf "setparams=colorspace=bt709" -i $url');

      // 监听元数据
      server.metadata.listen((meta) {
        print('\n[METADATA] ${meta.deviceName}: ${meta.width}x${meta.height}');
      });

      print('\n服务正在运行。按 Ctrl+C 停止测试。');

      final keepAlive = Completer<void>();
      await keepAlive.future;
    },
    timeout: const Timeout(Duration(hours: 1)),
  );
}
