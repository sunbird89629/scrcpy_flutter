import 'package:flutter/material.dart';
import 'package:scrcpy_flutter/home_page.dart';
import 'package:scrcpy_flutter/theme/app_theme.dart';

class ScrcpyApp extends StatelessWidget {
  const ScrcpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScrcpyApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
