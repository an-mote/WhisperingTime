import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispering_time/design/app_theme.dart';
import 'package:whispering_time/page/group/browser.dart';
import 'package:whispering_time/page/group/manager.dart';
import 'package:whispering_time/page/group/model.dart';
import 'package:whispering_time/page/group/settings.dart';
import 'package:whispering_time/page/home/drawer.dart';
import 'package:whispering_time/page/theme/browser.dart';
import 'package:whispering_time/page/theme/settings.dart';
import 'package:whispering_time/service/sp/sp.dart';
import 'package:whispering_time/util/env.dart';

/// Actual production ThemePage, GroupPage and HomeDrawer rendering.
/// The in-memory manager and account are fixtures; no backend calls are sent.
/// The Row/Scaffold host reproduces HomePage's adaptive placement, but does not
/// exercise HomePage's HTTP/gRPC startup or its create workflow end to end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final captureKey = GlobalKey();
  final output = Directory('../../TMP/UI重设计/2026-10-14/工作区截图');

  setUpAll(() async {
    // This is an explicit widget-test fixture kept in UIQA, outside test/.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'language_code': 'zh'});
    await SP().init();
    await output.create(recursive: true);
    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    final chineseFont = pingFang.existsSync()
        ? pingFang
        : File('/System/Library/Fonts/STHeiti Medium.ttc');
    final latinFont = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    final unicodeFont = File(
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    );
    for (final entry in <String, File>{
      'UIQA Chinese': chineseFont,
      'PingFang SC': chineseFont,
      'Roboto': latinFont,
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
    await File('${output.path}/验证范围与字体说明.txt').writeAsString(
      '使用生产 ThemePage、GroupPage、HomeDrawer 和 AppTheme.light/dark。\n'
      '账户、主题和分组是测试内存样本；不会写入真实账户或调用后端。\n'
      'Row/Scaffold 是与 HomePage 相同放置方式的组件测试宿主，'
      '没有验证 HomePage HTTP/gRPC 启动、新建、存储等端到端行为。\n'
      '中文字体：${chineseFont.path}\n'
      '拉丁字体：${latinFont.path}\n'
      '默认测试字体：${unicodeFont.path}\n'
      'MaterialIcons：Flutter bundle 的 MaterialIcons-Regular.otf\n'
      '生产 AppTheme 保留全部样式；截图仅加载已安装字体供其回退。\n'
      '映射真实字体以防测试默认 Ahem 方块字；系统字体回退、'
      '原生窗口与屏幕阅读器仍需运行应用核验。\n',
    );
  });

  final cases = <({String name, Size size, bool dark, double scale})>[
    (name: '窄窗口浅色', size: const Size(360, 600), dark: false, scale: 1),
    (name: '手机浅色', size: const Size(375, 812), dark: false, scale: 1),
    (name: '宽窗口浅色', size: const Size(1000, 760), dark: false, scale: 1),
    (name: '宽窗口深色', size: const Size(1000, 760), dark: true, scale: 1),
    (name: '手机深色', size: const Size(375, 812), dark: true, scale: 1),
    (name: '手机大字', size: const Size(375, 812), dark: false, scale: 2),
    (name: '宽窗口深色大字', size: const Size(1000, 760), dark: true, scale: 2),
    (name: '横屏浅色', size: const Size(812, 375), dark: false, scale: 1),
  ];
  for (final scenario in cases) {
    testWidgets('${scenario.name}：生产主题、分组、账户组件', (tester) async {
      final manager = _FixtureGroupsManager(_sampleGroups());
      final themes = [
        ThemeItem(id: 'daily', name: '日常'),
        ThemeItem(id: 'travel', name: '旅途与远方'),
      ];
      final navigatorKey = GlobalKey<NavigatorState>();
      final scaffoldKey = GlobalKey<ScaffoldState>();
      await _setSize(tester, scenario.size);
      await tester.pumpWidget(
        _host(
          captureKey: captureKey,
          size: scenario.size,
          dark: scenario.dark,
          scale: scenario.scale,
          manager: manager,
          themes: themes,
          navigatorKey: navigatorKey,
          scaffoldKey: scaffoldKey,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(manager.tid, 'daily');
      expect(find.byType(GroupPage), findsWidgets);
      expect(find.text('默认分组'), findsOneWidget);
      expect(find.byTooltip('管理当前主题'), findsOneWidget);
      expect(find.byTooltip('管理默认分组'), findsOneWidget);
      await _capture(tester, captureKey, output, '${scenario.name}-工作区');

      // A conventional button is available for both settings surfaces.
      await tester.tap(find.byTooltip('管理当前主题'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemeSettings), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(ThemeSettings)))
            .scale(16),
        closeTo(16 * scenario.scale, 0.01),
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, captureKey, output, '${scenario.name}-主题设置');
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('管理默认分组'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupSettings), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(GroupSettings)))
            .scale(16),
        closeTo(16 * scenario.scale, 0.01),
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, captureKey, output, '${scenario.name}-分组设置');
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      // Click and wheel provide alternatives to drag-only tab switching.
      await tester.tap(find.text('旅途与远方').first);
      await tester.pumpAndSettle();
      expect(manager.tid, 'travel');
      expect(find.text('山间散步'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final barCenter = tester.getCenter(find.byType(TabBar));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: barCenter,
          scrollDelta: const Offset(0, -60),
        ),
      );
      await tester.pumpAndSettle();
      expect(manager.tid, 'daily');
      expect(find.text('默认分组'), findsOneWidget);

      if (scenario.size.width < 900) {
        await tester.tap(find.byTooltip('打开账户与设置'));
        await tester.pumpAndSettle();
        expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);
        await _capture(tester, captureKey, output, '${scenario.name}-账户侧栏');
        await tester.tap(find.widgetWithText(ListTile, '我的印迹'));
        await tester.pumpAndSettle();
        expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
        expect(find.byType(ThemePage), findsOneWidget);
      } else {
        await tester.tap(find.widgetWithText(ListTile, '我的印迹'));
        await tester.pumpAndSettle();
        expect(navigatorKey.currentState!.canPop(), isFalse);
        expect(find.byType(ThemePage), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('生产空主题和分组：保留可操作新建入口', (tester) async {
    await _setSize(tester, const Size(375, 812));
    int createTheme = 0;
    int createGroup = 0;
    final manager = _FixtureGroupsManager({'empty': []});
    await tester.pumpWidget(
      _host(
        captureKey: captureKey,
        size: const Size(375, 812),
        dark: false,
        scale: 2,
        manager: manager,
        themes: [],
        onCreateTheme: () => createTheme++,
        onCreateGroup: () => createGroup++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('从一个主题开始'), findsOneWidget);
    await _capture(tester, captureKey, output, '大字-空主题');
    await tester.tap(find.text('新建主题'));
    expect(createTheme, 1);
    await tester.pumpWidget(
      _host(
        captureKey: captureKey,
        size: const Size(375, 812),
        dark: false,
        scale: 2,
        manager: manager,
        themes: [ThemeItem(id: 'empty', name: '慢慢收集生活里值得留下的瞬间')],
        onCreateTheme: () => createTheme++,
        onCreateGroup: () => createGroup++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('给这个主题添一个分组'), findsOneWidget);
    await _capture(tester, captureKey, output, '大字-长中文标题与空分组');
    await tester.tap(find.text('新建分组'));
    expect(createGroup, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('生产分组加载、错误和重试状态', (tester) async {
    await _setSize(tester, const Size(1000, 760));
    final pending = Completer<bool>();
    final manager = _FixtureGroupsManager(_sampleGroups())..pending = pending;
    await tester.pumpWidget(
      _host(
        captureKey: captureKey,
        size: const Size(1000, 760),
        dark: true,
        scale: 1,
        manager: manager,
        themes: [ThemeItem(id: 'daily', name: '日常')],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _capture(tester, captureKey, output, '深色-分组加载');
    pending.complete(false);
    manager.pending = null;
    manager.success = false;
    await tester.pumpAndSettle();
    expect(find.text('分组暂时无法加载'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    await _capture(tester, captureKey, output, '深色-分组加载失败');
    final loadsBeforeRetry = manager.loadCalls;
    manager.success = true;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(manager.loadCalls, greaterThan(loadsBeforeRetry));
    expect(find.text('默认分组'), findsOneWidget);
    expect(find.text('分组暂时无法加载'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面键盘焦点、Enter、Escape与滚轮替代入口', (tester) async {
    const viewport = Size(1000, 760);
    await _setSize(tester, viewport);
    final manager = _FixtureGroupsManager(_sampleGroups());
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(
        captureKey: captureKey,
        size: viewport,
        dark: false,
        scale: 1,
        manager: manager,
        navigatorKey: navigatorKey,
        themes: [
          ThemeItem(id: 'daily', name: '日常'),
          ThemeItem(id: 'travel', name: '旅途与远方'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final themeControl = find.byTooltip('管理当前主题');
    await _tabTo(tester, themeControl, viewport);
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    await _capture(tester, captureKey, output, '桌面键盘-主题管理焦点');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(ThemeSettings), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ThemeSettings), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);

    final groupControl = find.byTooltip('管理默认分组');
    await _tabTo(tester, groupControl, viewport);
    await _capture(tester, captureKey, output, '桌面键盘-分组管理焦点');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(GroupSettings), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GroupSettings), findsNothing);

    final navigation = find.widgetWithText(ListTile, '我的印迹');
    await _tabTo(tester, navigation, viewport);
    await _capture(tester, captureKey, output, '桌面键盘-侧栏焦点');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(find.byType(ThemePage), findsOneWidget);

    final bar = find.byType(TabBar);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(bar),
        scrollDelta: const Offset(0, 60),
      ),
    );
    await tester.pumpAndSettle();
    expect(manager.tid, 'travel');
    expect(find.text('山间散步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required GlobalKey captureKey,
  required Size size,
  required bool dark,
  required double scale,
  required _FixtureGroupsManager manager,
  required List<ThemeItem> themes,
  GlobalKey<NavigatorState>? navigatorKey,
  GlobalKey<ScaffoldState>? scaffoldKey,
  VoidCallback? onCreateTheme,
  VoidCallback? onCreateGroup,
}) {
  final account = UserBasicInfo(
    email: 'uiqa@example.invalid',
    profile: Profile(
      nickname: '记录生活的人',
      avatar: Avatar(name: '', url: ''),
    ),
  );
  final accountFuture = Future.value(account);
  HomeDrawer drawer({bool persistent = false}) => HomeDrawer(
    persistent: persistent,
    userInfoFuture: accountFuture,
    userinfo: account,
    onUserInfoUpdate: () {},
  );
  final wide = size.width >= 900;
  return RepaintBoundary(
    key: captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          platformBrightness: dark ? Brightness.dark : Brightness.light,
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => ChangeNotifierProvider<GroupsManager>.value(
          value: manager,
          child: Row(
            children: [
              if (wide) ...[
                SizedBox(width: 256, child: drawer(persistent: true)),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ],
              Expanded(
                child: Scaffold(
                  key: scaffoldKey,
                  appBar: AppBar(
                    automaticallyImplyLeading: !wide,
                    leading: wide
                        ? null
                        : Builder(
                            builder: (context) => IconButton(
                              tooltip: '打开账户与设置',
                              icon: const Icon(Icons.menu),
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                            ),
                          ),
                    title: const Text(
                      '我的印迹',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  drawer: wide ? null : drawer(),
                  body: SafeArea(
                    child: ThemePage(
                      themes,
                      onCreateTheme: onCreateTheme ?? () {},
                      onCreateGroup: onCreateGroup ?? () {},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Map<String, List<Group>> _sampleGroups() => {
  'daily': [
    _group('default', '默认分组'),
    _group('reading', '读书与摘录'),
    _group('long', '在忙碌的日常中慢慢收集那些值得留下来的细小瞬间'),
  ],
  'travel': [_group('walk', '山间散步')],
};

Group _group(String id, String name) => Group(
  id: id,
  name: name,
  config: GroupConfig.getDefault(),
  updateAt: DateTime(2026, 10, 14),
  overAt: null,
);

class _FixtureGroupsManager extends GroupsManager {
  _FixtureGroupsManager(this.groups);
  final Map<String, List<Group>> groups;
  bool success = true;
  Completer<bool>? pending;
  int loadCalls = 0;

  @override
  List<Group> getItems(String themeId) => groups[themeId] ?? [];

  @override
  List<Group> get items => getItems(tid);

  @override
  Future<bool> get([String? targetTid]) async {
    loadCalls++;
    if (pending != null) return pending!.future;
    return success;
  }

  @override
  void setThemeID(String id) {
    tid = id;
    notifyListeners();
  }
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  Directory output,
  String name,
) async {
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/icon.png'),
      tester.element(find.byType(ThemePage)),
    ),
  );
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

/// Traverse the real focus tree without requestFocus or pointer clicks. The
/// screenshot captures the production keyboard focus treatment for review.
Future<void> _tabTo(WidgetTester tester, Finder target, Size viewport) async {
  for (int step = 0; step < 48; step++) {
    if (_focusedWithin(target)) {
      final bounds = tester.getRect(target);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(viewport.width));
      expect(bounds.bottom, lessThanOrEqualTo(viewport.height));
      expect(FocusManager.instance.primaryFocus!.hasPrimaryFocus, isTrue);
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
  fail('Tab traversal did not reach $target');
}

bool _focusedWithin(Finder target) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final targets = target.evaluate().toSet();
  if (targets.contains(context)) return true;
  bool found = false;
  context.visitAncestorElements((element) {
    if (targets.contains(element)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
