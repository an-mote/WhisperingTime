import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispering_time/design/app_theme.dart';
import 'package:whispering_time/welcome.dart';

/// Render the production Welcome widget and exercise only invalid submissions.
/// Authentication and visitor registration are deliberately never sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final captureKey = GlobalKey();
  final output = Directory('../../TMP/UI重设计/2026-10-14/欢迎页截图');

  setUpAll(() async {
    await output.create(recursive: true);
    // macOS installations may keep PingFang in protected assets. If unavailable,
    // use the installed Chinese font so screenshots remain readable. Loading
    // under the normal families retains the production ThemeData and sizes.
    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    final chineseFont = pingFang.existsSync()
        ? pingFang
        : File('/System/Library/Fonts/STHeiti Medium.ttc');
    final unicodeFont = File(
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    );
    final latinFont = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    for (final entry in <String, File>{
      'UIQA Chinese': chineseFont,
      'PingFang SC': chineseFont,
      'Roboto': latinFont,
      // The test runner substitutes Ahem when a TextStyle has no family. Supply
      // a real Unicode font for that family instead of exporting square glyphs.
      'Ahem': unicodeFont,
    }.entries) {
      if (!entry.value.existsSync()) {
        throw StateError('Missing screenshot font: ${entry.value.path}');
      }
      final bytes = await entry.value.readAsBytes();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await materialIcons.load();
    await File('${output.path}/字体说明.txt').writeAsString(
      '生产 Welcome widget、AppTheme.light/dark 实际 Flutter 渲染。\n'
      '中文字体：${chineseFont.path}\n'
      '拉丁字体：${latinFont.path}\n'
      '测试默认字体替代：${unicodeFont.path}\n'
      '生产 AppTheme 保留全部样式；截图仅加载已安装字体供其回退。\n'
      '字体文件用于可读截图；macOS 系统最终字体回退仍需运行应用核验。\n',
    );
  });

  final cases = <({String name, Size size, bool dark, double scale})>[
    (name: '手机浅色', size: const Size(375, 812), dark: false, scale: 1),
    (name: '宽窗口浅色', size: const Size(1000, 760), dark: false, scale: 1),
    (name: '窄窗口浅色', size: const Size(360, 600), dark: false, scale: 1),
    (name: '横屏浅色', size: const Size(812, 375), dark: false, scale: 1),
    (name: '宽窗口深色', size: const Size(1000, 760), dark: true, scale: 1),
    (name: '手机深色', size: const Size(375, 812), dark: true, scale: 1),
    (name: '手机大字', size: const Size(375, 812), dark: false, scale: 2),
    (name: '宽窗口深色大字', size: const Size(1000, 760), dark: true, scale: 2),
  ];

  for (final scenario in cases) {
    testWidgets('${scenario.name}：欢迎、登录、注册和返回', (tester) async {
      await tester.binding.setSurfaceSize(scenario.size);
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: scenario.dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scenario.scale),
                platformBrightness: scenario.dark
                    ? Brightness.dark
                    : Brightness.light,
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const Welcome(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/icon.png'),
          tester.element(find.byType(Welcome)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('枫迹'), findsOneWidget);
      expect(find.text('留住今天的印迹'), findsOneWidget);
      await _capture(tester, captureKey, output, '${scenario.name}-欢迎');

      await _tapVisible(tester, find.text('账号登陆'));
      expect(find.text('欢迎回来'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      await _capture(tester, captureKey, output, '${scenario.name}-登录');

      await _tapVisible(tester, find.byTooltip('显示密码'));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isFalse,
      );
      await _tapVisible(tester, find.byTooltip('隐藏密码'));
      await _tapVisible(tester, find.text('登录'));
      expect(find.text('用户名不能为空'), findsOneWidget);
      expect(find.text('密码不能为空'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);

      await _tapVisible(tester, find.text('注册账号'));
      expect(find.text('创建账号'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(4));
      await _capture(tester, captureKey, output, '${scenario.name}-注册输入');
      await tester.ensureVisible(find.text('注册'));
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, output, '${scenario.name}-注册提交');
      await _tapVisible(tester, find.text('注册'));
      expect(find.text('用户名不能为空'), findsOneWidget);
      expect(find.text('邮箱不能为空'), findsOneWidget);
      expect(find.text('密码不能为空'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextFormField).first, 'maple_journey');
      await _tapVisible(tester, find.text('已有账号，登录'));
      expect(find.text('欢迎回来'), findsOneWidget);
      await _tapVisible(tester, find.text('注册账号'));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'maple_journey',
      );
      await _tapVisible(tester, find.text('返回'));
      expect(find.text('欢迎回来'), findsOneWidget);
      await _tapVisible(tester, find.text('返回'));
      expect(find.text('留住今天的印迹'), findsOneWidget);
      await _tapVisible(tester, find.text('了解更多'));
      expect(find.text('游客模式说明'), findsOneWidget);
      await _tapVisible(tester, find.text('知道了'));
      expect(find.text('游客模式说明'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  // 输入聚焦会在下一帧滚动到文本框，待该滚动完成后再定位操作按钮。
  for (var attempt = 0; attempt < 3; attempt++) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    if (finder.hitTestable().evaluate().isNotEmpty) break;
  }
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  Directory output,
  String name,
) async {
  await tester.pump();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final rendered = await boundary.toImage(pixelRatio: 1);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    rendered.dispose();
  });
}
