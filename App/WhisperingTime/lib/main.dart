import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:whispering_time/design/app_theme.dart';
import 'package:whispering_time/welcome.dart';
import 'package:whispering_time/page/home/appbar.dart';
import 'package:whispering_time/service/sp/sp.dart';
import 'package:whispering_time/service/isar/config.dart';
import 'package:window_manager/window_manager.dart';
import 'package:whispering_time/util/env.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面默认使用工作区尺寸，窄窗口仍由页面自适应布局处理。
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    // 保留系统默认的窗口背景与标题栏，避免原生窗口被设为透明。
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1000, 760),
      center: true,
      skipTaskbar: false,
      minimumSize: Size(360, 600),
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await SP().init();
  final uid = SP().getUID();
  print(uid);
  await Config().init(uid);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>
    with WidgetsBindingObserver, WindowListener {
  void _resetKeyboardState() {
    // ignore: invalid_use_of_visible_for_testing_member
    HardwareKeyboard.instance.clearState();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetKeyboardState();

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Clear any stale pressed-key state when the app resumes or loses focus.
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      _resetKeyboardState();
    }
  }

  @override
  void onWindowFocus() {
    _resetKeyboardState();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: '枫迹',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        highContrastTheme: AppTheme.light(highContrast: true),
        highContrastDarkTheme: AppTheme.dark(highContrast: true),
        themeMode: ThemeMode.system,
        themeAnimationDuration:
            WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 180),
        home: enterPage(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: [
          const Locale('zh', 'CH'),
          // const Locale('en', 'US'),
        ],
        locale: Locale('zh'),
      ),
    );
  }

  Widget enterPage() {
    return SP().getIsAutoLogin() ? HomePage() : Welcome();
  }
}

class MyAppState extends ChangeNotifier {
  MyAppState();
}
