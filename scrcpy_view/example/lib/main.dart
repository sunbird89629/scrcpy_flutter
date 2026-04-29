import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:scrcpy_view_example/webview_screen.dart';

void main() {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScrcpyView Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const WebViewScreen(),
    );
  }
}

// class ExamplePage extends StatefulWidget {
//   const ExamplePage({super.key});

//   @override
//   State<ExamplePage> createState() => _ExamplePageState();
// }

// class _ExamplePageState extends State<ExamplePage> {
//   final _adb = AdbClientAdapter.withPath();
//   List<String> _devices = [];
//   String? _selectedId;
//   String? _statsJson;

//   Future<void> _refreshDevices() async {
//     try {
//       final devices = await _adb.getDevices();
//       setState(() {
//         _devices = devices;
//         if (_devices.isEmpty) {
//           _selectedId = null;
//         } else if (_selectedId == null || !_devices.contains(_selectedId)) {
//           _selectedId = _devices.first;
//         }
//       });
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to get devices: $e'),
//           ),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('ScrcpyView Example'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _refreshDevices,
//           ),
//         ],
//       ),
//       body: _selectedId == null
//           ? Center(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   const Text('No device selected'),
//                   const SizedBox(height: 16),
//                   FilledButton(
//                     onPressed: _refreshDevices,
//                     child: const Text('Scan for devices'),
//                   ),
//                 ],
//               ),
//             )
//           : Column(
//               children: [
//                 Padding(
//                   padding: const EdgeInsets.all(8),
//                   child: Row(
//                     children: [
//                       const Text('Device: '),
//                       Expanded(
//                         child: DropdownButton<String>(
//                           value: _selectedId,
//                           isExpanded: true,
//                           items: _devices
//                               .map((d) => DropdownMenuItem(
//                                     value: d,
//                                     child: Text(d),
//                                   ))
//                               .toList(),
//                           onChanged: (id) {
//                             if (id != null) setState(() => _selectedId = id);
//                           },
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 const Divider(height: 1),
//                 Expanded(
//                   child: Stack(
//                     children: [
//                       ScrcpyView(
//                         key: ValueKey(_selectedId),
//                         adb: _adb,
//                         deviceId: _selectedId!,
//                         videoBackend: _WebViewBackend(
//                           onStats: (stats) =>
//                               setState(() => _statsJson = stats),
//                         ),
//                         onError: (err) {
//                           ScaffoldMessenger.of(context).showSnackBar(
//                             SnackBar(content: Text('Error: $err')),
//                           );
//                         },
//                       ),
//                       if (_statsJson != null)
//                         Positioned(
//                           top: 8,
//                           right: 8,
//                           child: IgnorePointer(
//                             child: Container(
//                               padding: const EdgeInsets.all(4),
//                               decoration: BoxDecoration(
//                                 color: Colors.black54,
//                                 borderRadius: BorderRadius.circular(4),
//                               ),
//                               child: Text(
//                                 _statsJson!,
//                                 style: const TextStyle(
//                                   color: Colors.white,
//                                   fontSize: 10,
//                                   fontFamily: 'monospace',
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//     );
//   }
// }

/// An example [ScrcpyVideoBackend] that renders the stream in a WebView
/// and forwards touch events to the device via JavaScript interop.
// class _WebViewBackend implements ScrcpyVideoBackend {
//   const _WebViewBackend({this.onStats});

//   final ValueChanged<String>? onStats;

//   @override
//   Widget build({
//     required String playerUrl,
//     required ScrcpyTouchController touchController,
//     required void Function(ScrcpyControlMessage) onControlMessage,
//   }) {
//     return InAppWebView(
//       initialUrlRequest: URLRequest(url: WebUri(playerUrl)),
//       initialSettings: InAppWebViewSettings(
//         preferredContentMode: UserPreferredContentMode.DESKTOP,
//         isInspectable: true,
//       ),
//       onWebViewCreated: (controller) {
//         controller.addJavaScriptHandler(
//           handlerName: 'statsHandler',
//           callback: (args) {
//             if (args.isNotEmpty) onStats?.call(args[0] as String);
//             return null;
//           },
//         );

//         controller.addJavaScriptHandler(
//           handlerName: 'touchHandler',
//           callback: (args) {
//             final action = (args[0] as num).toInt();
//             final pointerId = (args[1] as num).toInt();
//             final cssX = (args[2] as num).toInt();
//             final cssY = (args[3] as num).toInt();
//             final cssW = (args[4] as num).toInt();
//             final cssH = (args[5] as num).toInt();
//             final internalW = (args[6] as num).toInt();
//             final internalH = (args[7] as num).toInt();
//             final pressure = (args[8] as num).toDouble();

//             if (internalW == 0 || internalH == 0) return;

//             final x = (cssX * internalW) ~/ cssW;
//             final y = (cssY * internalH) ~/ cssH;

//             onControlMessage(
//               ScrcpyInjectTouchMessage(
//                 action: _mapAction(action),
//                 pointerId: pointerId,
//                 x: x,
//                 y: y,
//                 width: internalW,
//                 height: internalH,
//                 pressure: pressure,
//                 buttons: 1,
//               ),
//             );
//           },
//         );
//       },
//     );
//   }

//   int _mapAction(int jsAction) {
//     return switch (jsAction) {
//       0 => ScrcpyAction.down,
//       1 => ScrcpyAction.up,
//       2 => ScrcpyAction.move,
//       3 => ScrcpyAction.cancel,
//       _ => ScrcpyAction.move,
//     };
//   }
// }
