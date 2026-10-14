import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whispering_time/design/widgets.dart';
import 'package:whispering_time/page/group/browser.dart';
import 'package:whispering_time/page/group/manager.dart';

import 'settings.dart';

class ThemeItem {
  String id;
  String name;
  ThemeItem({required this.id, required this.name});
}

class ThemePage extends StatefulWidget {
  final List<ThemeItem> titems;
  final VoidCallback? onCreateTheme;
  final VoidCallback? onCreateGroup;

  const ThemePage(
    this.titems, {
    super.key,
    this.onCreateTheme,
    this.onCreateGroup,
  });

  @override
  State<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> with TickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedThemeId;
  DateTime _lastWheelEvent = DateTime.fromMillisecondsSinceEpoch(0);
  static const _wheelThrottle = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _tabController = _createTabController(widget.titems.length);
    _scheduleSelection();
  }

  @override
  void didUpdateWidget(ThemePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcileController();
    _scheduleSelection();
  }

  void _reconcileController() {
    final oldIndex = _tabController.index;
    final selectedIndex = widget.titems.indexWhere(
      (theme) => theme.id == _selectedThemeId,
    );
    final newIndex = widget.titems.isEmpty
        ? 0
        : selectedIndex >= 0
        ? selectedIndex
        : oldIndex.clamp(0, widget.titems.length - 1);
    if (_tabController.length != widget.titems.length ||
        _tabController.index != newIndex) {
      _disposeTabController();
      _tabController = _createTabController(
        widget.titems.length,
        initialIndex: newIndex,
      );
    }
  }

  void _scheduleSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onTabChanged();
    });
  }

  @override
  void dispose() {
    _disposeTabController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.titems.isEmpty) {
      return ImprintEmptyState(
        icon: Icons.collections_bookmark_outlined,
        title: '从一个主题开始',
        message: '为生活、旅途或灵感建立主题，让每一份记录都有归处。',
        action: widget.onCreateTheme == null
            ? null
            : FilledButton.icon(
                onPressed: widget.onCreateTheme,
                icon: const Icon(Icons.add),
                label: const Text('新建主题'),
              ),
      );
    }
    final theme = Theme.of(context);
    final current = widget.titems[_tabController.index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(inset, 16, inset, 0),
              child: Listener(
                onPointerSignal: _handlePointerSignal,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: EdgeInsets.zero,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  dividerColor: theme.colorScheme.outlineVariant,
                  tabs: widget.titems
                      .asMap()
                      .entries
                      .map(
                        (entry) => Tab(
                          child: GestureDetector(
                            onLongPress: () => showThemeSettings(entry.key),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(
                                entry.value.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(inset, 24, inset, 0),
              child: ImprintSectionHeader(
                title: current.name,
                subtitle: '按分组整理，随时回顾',
                trailing: IconButton(
                  tooltip: '管理当前主题',
                  icon: const Icon(Icons.tune_outlined),
                  onPressed: () => showThemeSettings(_tabController.index),
                ),
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: const MaterialScrollBehavior().copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: TabBarView(
                  controller: _tabController,
                  children: widget.titems
                      .map(
                        (theme) => GroupPage(
                          key: ValueKey(theme.id),
                          themename: theme.name,
                          tid: theme.id,
                          onCreateGroup: widget.onCreateGroup,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void showThemeSettings(int index) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (modalContext) => ThemeSettings(
        theme: widget.titems[index],
        onRenamed: (newName) {
          if (!mounted) return;
          setState(() => widget.titems[index].name = newName);
        },
        onDeleted: () {
          if (!mounted) return;
          setState(() {
            widget.titems.removeAt(index);
            _reconcileController();
          });
          _scheduleSelection();
        },
      ),
    );
  }

  TabController _createTabController(int length, {int initialIndex = 0}) {
    final controller = TabController(
      length: length,
      vsync: this,
      initialIndex: initialIndex,
    );
    controller.addListener(_onTabChanged);
    return controller;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || widget.titems.length < 2) return;
    final now = DateTime.now();
    if (now.difference(_lastWheelEvent) < _wheelThrottle) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    _lastWheelEvent = now;
    _goToIndex(_tabController.index + (delta > 0 ? 1 : -1));
  }

  void _goToIndex(int index) {
    if (index < 0 || index >= widget.titems.length) return;
    _tabController.animateTo(
      index,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
    );
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging || !mounted) return;
    final id = widget.titems.isEmpty
        ? ''
        : widget.titems[_tabController.index].id;
    final groups = context.read<GroupsManager>();
    if (_selectedThemeId != id || groups.tid != id) {
      _selectedThemeId = id;
      groups.setThemeID(id);
      setState(() {});
    }
  }

  void _disposeTabController() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
  }
}
