import 'package:flutter/material.dart';
import 'package:scrcpy_app/home_page.dart';
import 'package:scrcpy_app/theme/app_theme.dart';

class ScrcpyApp extends StatelessWidget {
  const ScrcpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScrcpyApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      home: const HomePage(),
    );
  }
}
