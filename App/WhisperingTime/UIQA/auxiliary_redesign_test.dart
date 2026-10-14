import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispering_time/design/app_theme.dart';
import 'package:whispering_time/page/feedback/edit.dart';
import 'package:whispering_time/util/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final output = Directory('../../TMP/UI重设计/2026-10-14/辅助页截图');
  final captureKey = GlobalKey();

  setUpAll(() async {
    await output.create(recursive: true);
    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    final chinese = pingFang.existsSync()
        ? pingFang
        : File('/System/Library/Fonts/STHeiti Medium.ttc');
    for (final entry in <String, String>{
      'PingFang SC': chinese.path,
      'Roboto': '/System/Library/Fonts/Supplemental/Arial.ttf',
    }.entries) {
      final bytes = await File(entry.value).readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  final scenarios =
      <({String name, Size size, double scale, bool dark, bool hc})>[
        (
          name: '360浅色大字',
          size: const Size(360, 600),
          scale: 2,
          dark: false,
          hc: false,
        ),
        (
          name: '360深色高对比大字',
          size: const Size(360, 600),
          scale: 2,
          dark: true,
          hc: true,
        ),
        (
          name: '375深色',
          size: const Size(375, 812),
          scale: 1,
          dark: true,
          hc: false,
        ),
        (
          name: '宽窗口浅色',
          size: const Size(1000, 760),
          scale: 1,
          dark: false,
          hc: false,
        ),
      ];

  for (final scenario in scenarios) {
    testWidgets('${scenario.name}反馈表单：无效提交、整行勾选与焦点', (tester) async {
      await _setViewport(tester, scenario.size);
      await tester.pumpWidget(
        _app(
          captureKey,
          const Edit(),
          dark: scenario.dark,
          scale: scenario.scale,
          highContrast: scenario.hc,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, captureKey, output, '${scenario.name}-反馈顶部');

      final deviceInfo = find.widgetWithText(CheckboxListTile, '上传设备信息');
      await tester.ensureVisible(deviceInfo);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(deviceInfo).value, isTrue);
      await _tap(tester, find.text('上传设备信息'));
      expect(tester.widget<CheckboxListTile>(deviceInfo).value, isFalse);
      final publicInfo = find.widgetWithText(CheckboxListTile, '公开');
      await tester.ensureVisible(publicInfo);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('公开'));
      expect(tester.widget<CheckboxListTile>(publicInfo).value, isFalse);
      await tester.ensureVisible(find.text('提交'));
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, output, '${scenario.name}-反馈提交区');

      // Every submitted form remains invalid: no HTTP request, image picker,
      // device-information writer, or persistent store is invoked by this test.
      await _tap(tester, find.text('提交'));
      expect(find.text('标题不能为空'), findsOneWidget);
      expect(find.text('请添加描述'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await _capture(tester, captureKey, output, '${scenario.name}-反馈验证');
      await tester.enterText(find.byType(TextFormField).first, '标题' * 16);
      await tester.enterText(find.byType(TextFormField).last, '说明内容');
      await _tap(tester, find.text('提交'));
      expect(find.text('标题不能超过30个字'), findsOneWidget);
      expect(find.text('正在提交…'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '界面建议');
      await tester.enterText(find.byType(TextFormField).last, '');
      await _tap(tester, find.text('提交'));
      expect(find.text('请添加描述'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('360深色大字：共享错误提示长文可以换行', (tester) async {
    await _setViewport(tester, const Size(360, 600));
    await tester.pumpWidget(
      _app(
        captureKey,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    showErrMsg(context, '反馈提交失败，请检查网络后重试。填写的标题、描述和图片附件已保留。'),
                child: const Text('显示错误提示'),
              ),
            ),
          ),
        ),
        dark: true,
        scale: 2,
        highContrast: true,
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text('显示错误提示'));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, captureKey, output, '360深色大字-共享错误提示');
  });
}

Widget _app(
  GlobalKey key,
  Widget home, {
  required bool dark,
  required double scale,
  required bool highContrast,
}) => RepaintBoundary(
  key: key,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(highContrast: highContrast),
    darkTheme: AppTheme.dark(highContrast: highContrast),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        highContrast: highContrast,
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: home,
  ),
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
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
    final picture = await boundary.toImage(pixelRatio: 1);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}
