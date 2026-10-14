import 'package:flutter/material.dart';
import 'package:whispering_time/page/theme/browser.dart';
import 'package:whispering_time/page/home/drawer.dart';
import 'package:whispering_time/util/ui.dart';
import 'package:whispering_time/design/widgets.dart';
import 'package:whispering_time/service/sp/sp.dart';
import 'package:whispering_time/util/env.dart';
import 'package:whispering_time/service/http/official.dart' as official;
import 'package:whispering_time/service/grpc/grpc.dart';
import 'package:provider/provider.dart';
import 'package:whispering_time/page/group/manager.dart';

class HomePage extends StatefulWidget {
  @override
  State createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GlobalKey<ScaffoldState> scaffoldKey = GlobalKey();
  late Future<UserBasicInfo> _userInfoFuture;
  late Future<List<ThemeItem>> _initThemeFuture;
  UserBasicInfo userinfo = UserBasicInfo(
    email: "",
    profile: Profile(
      nickname: "",
      avatar: Avatar(name: "", url: ""),
    ),
  ); // 初始化 user
  List<ThemeItem> themes = [];
  String? _languageCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (_languageCode != language) {
      _languageCode = language;
      SP().setLanguageCode(language);
    }
  }

  Future<UserBasicInfo> init() async {
    final value = await official.Http().userInfo();
    if (value.isNotOK) {
      throw StateError('账户信息加载失败');
    }
    final info = UserBasicInfo(email: value.email, profile: value.profile);
    if (mounted) setState(() => userinfo = info);
    return info;
  }

  @override
  initState() {
    super.initState();
    _userInfoFuture = init();
    _initThemeFuture = initTheme();
  }

  @override
  Widget build(BuildContext context) {
    return body();
  }

  Widget body() {
    return ChangeNotifierProvider(
      create: (_) => GroupsManager(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Row(
            children: [
              if (wide) ...[
                SizedBox(width: 256, child: _drawer(persistent: true)),
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
                    automaticallyImplyLeading: false,
                    leading: wide
                        ? null
                        : FutureBuilder<UserBasicInfo>(
                            future: _userInfoFuture,
                            builder: (context, snapshot) => IconButton(
                              tooltip: '打开账户与设置',
                              icon:
                                  snapshot.connectionState ==
                                      ConnectionState.waiting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.menu),
                              onPressed: () =>
                                  scaffoldKey.currentState?.openDrawer(),
                            ),
                          ),
                    title: const Text(
                      '我的印迹',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    centerTitle: false,
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: PopupMenuButton<int>(
                          tooltip: '新建主题或分组',
                          onSelected: (value) {
                            if (value == 1) dialogAddTheme();
                            if (value == 3) dialogAddGroup();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 1,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.collections_bookmark_outlined,
                                ),
                                title: Text('新建主题'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 3,
                              enabled: context
                                  .read<GroupsManager>()
                                  .tid
                                  .isNotEmpty,
                              child: const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.create_new_folder_outlined),
                                title: Text('新建分组'),
                              ),
                            ),
                          ],
                          child: Ink(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ExcludeSemantics(
                                      child: Icon(
                                        Icons.add,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '新建',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  drawer: wide ? null : _drawer(),
                  body: SafeArea(
                    child: FutureBuilder<List<ThemeItem>>(
                      future: _initThemeFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return ImprintEmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: '暂时无法载入印迹',
                            message: '连接服务器失败，请检查网络后重试。',
                            action: OutlinedButton.icon(
                              onPressed: () => setState(() {
                                _initThemeFuture = initTheme();
                              }),
                              icon: const Icon(Icons.refresh),
                              label: const Text('重新加载'),
                            ),
                          );
                        }
                        return ThemePage(
                          snapshot.data ?? [],
                          onCreateTheme: dialogAddTheme,
                          onCreateGroup: dialogAddGroup,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  HomeDrawer _drawer({bool persistent = false}) => HomeDrawer(
    persistent: persistent,
    userInfoFuture: _userInfoFuture,
    userinfo: userinfo,
    onUserInfoUpdate: () {
      if (!mounted) return;
      final future = init();
      setState(() {
        _userInfoFuture = future;
      });
    },
  );

  Future<List<ThemeItem>> initTheme() async {
    final list = await Grpc().getthemes();
    if (list.isNotOK) throw StateError('服务器连接失败');
    themes = list.data
        .where((item) => item.id.isNotEmpty)
        .map((item) => ThemeItem(id: item.id, name: item.name))
        .toList();
    return themes;
  }

  // 窗口: 新增主题
  void dialogAddTheme() async {
    final controller = TextEditingController();
    bool creating = false;
    String? error;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> create() async {
            final name = controller.text.trim();
            if (name.isEmpty) {
              setDialogState(() => error = '请输入主题名称');
              return;
            }
            setDialogState(() {
              creating = true;
              error = null;
            });
            try {
              final res = await Grpc().createTheme(
                RequestCreateTheme(name: name),
              );
              if (!dialogContext.mounted) return;
              if (res.isNotOK) {
                setDialogState(() {
                  creating = false;
                  error = '创建失败，请检查连接后重试';
                });
                return;
              }
              Navigator.of(dialogContext).pop(true);
            } catch (_) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                creating = false;
                error = '创建失败，请稍后重试';
              });
            }
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('新建主题'),
            content: TextField(
              controller: controller,
              autofocus: true,
              enabled: !creating,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => create(),
              decoration: InputDecoration(
                labelText: '主题名称',
                hintText: '例如：日常、旅途、灵感',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: creating
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: creating ? null : create,
                child: Text(creating ? '创建中…' : '创建'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (created == true && mounted) {
      final future = initTheme();
      setState(() {
        _initThemeFuture = future;
      });
    }
  }

  // 窗口: 新增分组
  void dialogAddGroup() async {
    final scaffoldContext = scaffoldKey.currentContext;
    if (scaffoldContext == null) return;
    final manager = Provider.of<GroupsManager>(scaffoldContext, listen: false);
    if (manager.tid.isEmpty) {
      showErrMsg(context, '请先新建或选择一个主题');
      return;
    }
    final controller = TextEditingController();
    int freezeDays = 30;
    int step = 0;
    bool creating = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(step == 0 ? '新建分组' : '选择自动定格时间'),
          content: step == 0
              ? TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '分组名称',
                    hintText: '例如：随手记、阅读摘录',
                    errorText: error,
                  ),
                )
              : RadioGroup<int>(
                  groupValue: freezeDays,
                  onChanged: (value) {
                    if (value != null && !creating) {
                      setDialogState(() => freezeDays = value);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('若在选定时间内未操作，分组将自动进入定格缓冲期。'),
                      const SizedBox(height: 8),
                      ...[7, 30, 60, 90].map(
                        (days) => RadioListTile<int>(
                          title: Text('$days 天'),
                          value: days,
                        ),
                      ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
          actions: [
            TextButton(
              onPressed: creating
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            if (step == 1)
              TextButton(
                onPressed: creating
                    ? null
                    : () => setDialogState(() {
                        step = 0;
                        error = null;
                      }),
                child: const Text('上一步'),
              ),
            FilledButton(
              onPressed: creating
                  ? null
                  : () async {
                      final name = controller.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() => error = '请输入分组名称');
                        return;
                      }
                      if (step == 0) {
                        setDialogState(() {
                          step = 1;
                          error = null;
                        });
                        return;
                      }
                      setDialogState(() {
                        creating = true;
                        error = null;
                      });
                      try {
                        final ok = await manager.add(
                          name,
                          freezeDays: freezeDays,
                        );
                        if (!dialogContext.mounted) return;
                        if (ok) {
                          Navigator.of(dialogContext).pop();
                        } else {
                          setDialogState(() {
                            creating = false;
                            error = '创建失败，请检查网络后重试';
                          });
                        }
                      } catch (_) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          creating = false;
                          error = '创建失败，请稍后重试';
                        });
                      }
                    },
              child: Text(
                creating
                    ? '创建中…'
                    : step == 0
                    ? '下一步'
                    : '创建',
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}
