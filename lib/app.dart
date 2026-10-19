import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'state/lentera_controller.dart';
import 'ui/home_screen.dart';
import 'ui/splash_screen.dart';

class LenteraApp extends StatefulWidget {
  const LenteraApp({super.key, required this.controller});
  final LenteraController controller;

  @override
  State<LenteraApp> createState() => _LenteraAppState();
}

class _LenteraAppState extends State<LenteraApp> with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 'inactive' sengaja diabaikan: dialog izin sistem juga memicunya.
    if (state == AppLifecycleState.paused) {
      widget.controller.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      widget.controller.onResume();
    }
  }

  void _openHome() {
    if (_navigated) return; // splash tidak boleh menumpuk
    _navigated = true;
    _navKey.currentState?.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LENTERA',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: SplashScreen(onFinished: _openHome),
    );
  }
}
