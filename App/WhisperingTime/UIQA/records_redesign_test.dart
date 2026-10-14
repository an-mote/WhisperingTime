import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whispering_time/design/app_theme.dart';
import 'package:whispering_time/page/doc/browser/card_view.dart';
import 'package:whispering_time/page/doc/browser/calendar_view.dart';
import 'package:whispering_time/page/doc/browser/filter_sheet.dart';
import 'package:whispering_time/page/doc/edit_page_body.dart';
import 'package:whispering_time/page/doc/edit.dart';
import 'package:whispering_time/page/doc/setting.dart';
import 'package:whispering_time/page/doc/manager.dart';
import 'package:whispering_time/page/doc/model.dart';
import 'package:whispering_time/page/doc/zk_model.dart';
import 'package:whispering_time/page/group/model.dart';
import 'package:whispering_time/service/scale/scale_service.dart';

// Production widgets with in-memory fixtures. No network or real account data.
class _NoNetworkScaleService implements ScaleService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('This visual fixture must not request the network.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final output = Directory('../../TMP/UI重设计/2026-10-14/记录截图');
  setUpAll(() async {
    await output.create(recursive: true);
    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    final chinese = pingFang.existsSync()
        ? pingFang
        : File('/System/Library/Fonts/STHeiti Medium.ttc');
    for (final entry in <String, File>{
      'UIQA Chinese': chinese,
      'PingFang SC': chinese,
      'Roboto': File('/System/Library/Fonts/Supplemental/Arial.ttf'),
      'Ahem': File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          Future.value(ByteData.sublistView(await entry.value.readAsBytes())),
        );
      await loader.load();
    }
    final iconBytes = await File(
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await icons.load();
    await File('${output.path}/字体说明.txt').writeAsString(
      '生产 AppTheme.light/dark 与生产记录组件实际 Flutter 渲染。\n中文字体：${chinese.path}\n仅加载已安装字体与 MaterialIcons；保留生产主题所有排版、颜色与尺寸。\n',
    );
  });
  final cases = <({String name, Size size, bool dark, double scale})>[
    (name: '手机浅色', size: const Size(375, 812), dark: false, scale: 1),
    (name: '宽窗口浅色', size: const Size(1000, 760), dark: false, scale: 1),
    (name: '窄窗口深色', size: const Size(360, 600), dark: true, scale: 1),
    (name: '横屏浅色', size: const Size(812, 375), dark: false, scale: 1),
    (name: '手机大字', size: const Size(375, 812), dark: false, scale: 2),
    (name: '宽窗口深色大字', size: const Size(1000, 760), dark: true, scale: 2),
  ];
  for (final scenario in cases) {
    testWidgets('${scenario.name}：生产卡片展开、日期、编辑与设置', (tester) async {
      final key = GlobalKey();
      final manager = _fixtureManager();
      int? expanded;
      int edits = 0;
      int settings = 0;
      await _pump(
        tester,
        scenario,
        key,
        StatefulBuilder(
          builder: (context, setState) => DocCardList(
            docsManager: manager,
            expandedIndex: expanded,
            flippedStates: const {},
            onToggleExpand: (index) => setState(() => expanded = index),
            onEdit: (_, _) => edits++,
            onSetting: (_) => settings++,
            onFlip: (_, _) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('晨间步数'), findsWidgets);
      await _capture(tester, key, output, '${scenario.name}-卡片');
      await tester.ensureVisible(
        find.byTooltip('创建于 2026年10月11日 08:30，点击切换日期显示'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('创建于 2026年10月11日 08:30，点击切换日期显示'));
      await tester.pumpAndSettle();
      expect(find.text('2026年10月11日 08:30'), findsOneWidget);
      await tester.ensureVisible(find.text('展开正文').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开正文').first);
      await tester.pumpAndSettle();
      expect(expanded, 0);
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-展开');
      await tester.ensureVisible(find.text('编辑').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑').first);
      expect(edits, 1);
      await tester.ensureVisible(find.byTooltip('印迹设置').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('印迹设置').first);
      expect(settings, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      manager.dispose();
    });
    testWidgets('${scenario.name}：生产日历与定位月份', (tester) async {
      final key = GlobalKey();
      final manager = _fixtureManager();
      final monthKeys = <String, GlobalKey>{};
      final gaps = <String>{};
      DateTime picked = DateTime(2026, 10, 14);
      await _pump(
        tester,
        scenario,
        key,
        StatefulBuilder(
          builder: (context, setState) => DocCalendarView(
            docsManager: manager,
            pickedDate: picked,
            expandedRanges: gaps,
            monthKeys: monthKeys,
            onDatePicked: (date) => setState(() => picked = date),
            onGapExpanded: (id) => setState(() => gaps.add(id)),
            onEdit: (_) {},
            onSetting: (_) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('2026年 10月'), findsOneWidget);
      await _capture(tester, key, output, '${scenario.name}-日历');
      await tester.tap(find.text('定位月份'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-月份定位');
      await tester.ensureVisible(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('14'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      expect(find.text('1 篇印迹'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-当日印迹');
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      manager.dispose();
    });
    testWidgets('${scenario.name}：生产筛选保留状态与提交关闭', (tester) async {
      final key = GlobalKey();
      List<bool> changed = [];
      await _pump(
        tester,
        scenario,
        key,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => FilterBottomSheet(
                  initialViewType: 0,
                  initialSortType: 0,
                  initialLevels: const [true, false, false, true, false],
                  onChanged: (_, _, levels) => changed = List.of(levels),
                ),
              ),
              child: const Text('打开筛选'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开筛选'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-筛选');
      await tester.ensureVisible(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(changed, [true, true, true, true, true]);
      await tester.ensureVisible(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(FilterBottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('${scenario.name}：生产完整编辑器标题、元数据与文档选项', (tester) async {
      final key = GlobalKey();
      final doc = Doc(
        id: 'visual-full-editor-only',
        title: '记下日常里值得珍藏的小事',
        level: 3,
        content: jsonEncode([
          {
            'title': '晨间步数',
            'type': 'fixed',
            'interaction_mode': 'input',
            'data_type': 'number',
            'options': [],
            'has_unit': true,
            'unit': '步',
            'current_value': '6840',
          },
        ]),
        createAt: DateTime(2026, 10, 14, 8, 30),
        updateAt: DateTime(2026, 10, 14, 8, 30),
        config: DocConfig(isShowTool: true),
      );
      final group = Group(
        name: '日常手记',
        id: 'visual-group-only',
        config: GroupConfig.getDefault(),
        updateAt: DateTime.now(),
        overAt: null,
      );
      final page = EditPage(
        doc: doc,
        group: group,
        onSave: (_) => throw StateError('Visual editor must not persist data'),
        onDelete: () => throw StateError('Visual editor must not delete data'),
      );
      await _pump(tester, scenario, key, page, shell: false);
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-完整编辑器');
      await tester.tap(find.text('记下日常里值得珍藏的小事'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '较长中文标题也可以清楚地阅读和继续编辑');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-标题编辑');
      if (scenario.size.width < 600) {
        await _pump(
          tester,
          scenario,
          key,
          page,
          shell: false,
          keyboardInset: 280,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, key, output, '${scenario.name}-键盘遮挡');
        await tester.ensureVisible(find.text('2026-10-14 08:30'));
        await tester.pumpAndSettle();
        final dateBounds = tester.getRect(find.text('2026-10-14 08:30'));
        expect(dateBounds.center.dy, lessThan(scenario.size.height - 280));
        expect(tester.takeException(), isNull);
        await _capture(tester, key, output, '${scenario.name}-键盘元数据');
        await _pump(tester, scenario, key, page, shell: false);
      }
      await tester.tap(find.byTooltip('文档选项'));
      await tester.pumpAndSettle();
      expect(find.text('创建时间'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-文档选项');
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('${scenario.name}：生产刻度编辑与图文工具栏', (tester) async {
      final key = GlobalKey();
      final controller = QuillController.basic();
      final markdown = TextEditingController();
      final focus = FocusNode();
      final model = DocumentModel(
        scales: [
          ScaleInstance(
            title: '晨间步数',
            type: ScaleType.fixed,
            interactionMode: ScaleInteractionMode.input,
            dataType: ScaleDataType.number,
            options: [],
            hasUnit: true,
            unit: '步',
            currentValue: '6840',
          ),
          ScaleInstance(
            title: '今天的心情与最想记住的生活感受',
            type: ScaleType.fixed,
            interactionMode: ScaleInteractionMode.selection,
            dataType: ScaleDataType.text,
            options: ['平静', '开心'],
            hasUnit: false,
            unit: '',
            currentValue: '平静',
          ),
        ],
      );
      ImageTextLayout layout = ImageTextLayout.mixed;
      await _pump(
        tester,
        scenario,
        key,
        ChangeNotifierProvider.value(
          value: model,
          child: StatefulBuilder(
            builder: (context, setState) => EditPageBody(
              quillController: controller,
              focusNode: focus,
              showToolbar: true,
              onPaste: () {},
              embedBuilders: [],
              scaleService: _NoNetworkScaleService(),
              markdownController: markdown,
              imageTextLayout: layout,
              onImageTextLayoutChanged: (value) =>
                  setState(() => layout = value),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-编辑面板');
      await tester.ensureVisible(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('添加图文'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加图文'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('图文混排'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('图文混排'));
      controller.document.insert(0, '今天在河边散步，风里有一点秋天的味道。\n');
      await tester.pumpAndSettle();
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.byType(QuillSimpleToolbar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, key, output, '${scenario.name}-图文工具栏');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      markdown.dispose();
      focus.dispose();
      model.dispose();
    });
  }
  testWidgets('360px 两倍字号：文档显示优先确认与取消（did:null）', (tester) async {
    final scenario = (
      name: '窄窗口两倍字文档设置',
      size: const Size(360, 600),
      dark: false,
      scale: 2.0,
    );
    final key = GlobalKey();
    final initial = DocConfig(displayPriority: 0);
    Map<String, dynamic>? result;
    await _pump(
      tester,
      scenario,
      key,
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              result = null;
              result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => DocSettingsDialog(
                  gid: 'visual-settings-only',
                  did: null,
                  config: initial,
                ),
              );
            },
            child: const Text('打开文档设置'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开文档设置'));
    await tester.pumpAndSettle();
    expect(find.text('删除文档'), findsNothing);
    expect(find.text('详细显示印迹，图文混排'), findsOneWidget);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(DocSettingsDialog)))
          .scale(16),
      32,
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, key, output, '窄窗口两倍字-文档显示初始');
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await _capture(tester, key, output, '窄窗口两倍字-显示优先选项');
    await tester.ensureVisible(find.text('文字优先').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('文字优先').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .initialValue,
      1,
    );
    expect(find.text('文字为主，图片以缩略图形式'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, key, output, '窄窗口两倍字-文字优先说明');
    await tester.ensureVisible(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result?['changed'], isTrue);
    expect((result?['config'] as DocConfig).displayPriority, 1);
    expect(initial.displayPriority, 0);
    await tester.tap(find.text('打开文档设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('媒体优先').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('媒体优先').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .initialValue,
      2,
    );
    expect(find.text('媒体为主，文字最小化显示'), findsOneWidget);
    await _capture(tester, key, output, '窄窗口两倍字-媒体优先说明');
    await tester.ensureVisible(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(initial.displayPriority, 0);
    expect(find.byType(DocSettingsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

DocsManager _fixtureManager() {
  final manager = DocsManager('visual-fixture-only');
  final config = GroupConfig(
    levels: List.filled(5, true),
    viewType: 0,
    sortType: 0,
    autoFreezeDays: 30,
  );
  manager.insertDoc(
    Doc(
      id: 'fixture-scale',
      title: '把日常的小变化，写成值得珍藏的生活印迹',
      content: jsonEncode([
        {
          'title': '晨间步数',
          'current_value': '6840',
          'has_unit': true,
          'unit': '步',
        },
        {'title': '今天的心情', 'current_value': '平静', 'has_unit': false},
      ]),
      level: 3,
      createAt: DateTime(2026, 10, 11, 8, 30),
      updateAt: DateTime(2026, 10, 11, 8, 30),
      config: DocConfig(),
    ),
    config: config,
  );
  manager.insertDoc(
    Doc(
      id: 'fixture-rich',
      title: '秋日散步',
      content: jsonEncode([
        {'insert': '今天在河边散步，风里有一点秋天的味道。抬头看见树叶慢慢变黄，想把这个安静的下午记下来。\n'},
      ]),
      level: 2,
      createAt: DateTime(2026, 10, 14, 16, 20),
      updateAt: DateTime(2026, 10, 14, 16, 20),
      config: DocConfig(),
    ),
    config: config,
  );
  return manager;
}

Future<void> _pump(
  WidgetTester tester,
  ({String name, Size size, bool dark, double scale}) scenario,
  GlobalKey key,
  Widget child, {
  bool shell = true,
  double keyboardInset = 0,
}) async {
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
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: scenario.dark ? ThemeMode.dark : ThemeMode.light,
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        builder: (context, navigator) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scenario.scale),
            platformBrightness: scenario.dark
                ? Brightness.dark
                : Brightness.light,
            disableAnimations: true,
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: navigator!,
        ),
        home: shell
            ? Scaffold(
                appBar: AppBar(title: const Text('日常手记')),
                body: SafeArea(child: child),
              )
            : child,
      ),
    ),
  );
  await tester.pumpAndSettle();
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
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
