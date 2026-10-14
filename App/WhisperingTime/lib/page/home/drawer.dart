import 'package:flutter/material.dart';
import 'package:whispering_time/design/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:whispering_time/page/home/setting.dart';
import 'package:whispering_time/page/feedback/feedback.dart';
import 'package:whispering_time/page/font_manager/font_manager.dart';
import 'package:whispering_time/page/home/config_management.dart';
import 'package:whispering_time/page/home/appbar.dart';
import 'package:whispering_time/page/home/task_manager.dart';
import 'package:whispering_time/service/isar/config.dart';
import 'package:whispering_time/service/sp/sp.dart';
import 'package:whispering_time/util/ui.dart';
import 'package:whispering_time/util/export.dart';
import 'package:whispering_time/util/env.dart';
import 'package:whispering_time/service/http/base.dart';
import 'package:whispering_time/service/http/official.dart' as official;
import 'package:whispering_time/welcome.dart';
import 'package:whispering_time/util/secure.dart';

class HomeDrawer extends StatefulWidget {
  final Future<UserBasicInfo> userInfoFuture;
  final UserBasicInfo userinfo;
  final VoidCallback onUserInfoUpdate;
  final bool persistent;

  const HomeDrawer({
    super.key,
    required this.userInfoFuture,
    required this.userinfo,
    required this.onUserInfoUpdate,
    this.persistent = false,
  });

  @override
  State<HomeDrawer> createState() => _HomeDrawerState();
}

class _HomeDrawerState extends State<HomeDrawer> {
  bool isEdit = false;
  bool _savingNickname = false;
  late TextEditingController nicknameController;

  @override
  void initState() {
    super.initState();
    nicknameController = TextEditingController(
      text: widget.userinfo.profile.nickname,
    );
  }

  @override
  void dispose() {
    nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: ImprintBrand(compact: true),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  _buildAvatarSection(),
                  const SizedBox(height: 24),
                  _tile(
                    icon: Icons.auto_stories_outlined,
                    title: '我的印迹',
                    selected: true,
                    onTap: _closeDrawer,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    child: Divider(height: 1),
                  ),
                  _tile(
                    icon: Icons.settings_outlined,
                    title: '设置',
                    onTap: () => _navigate(SettingPage()),
                  ),
                  _tile(
                    icon: Icons.task_alt_outlined,
                    title: '任务管理',
                    onTap: () => _navigate(TaskManagerPage()),
                  ),
                  _tile(
                    icon: Icons.file_download_outlined,
                    title: '内容导出',
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Export(ResourceType.theme),
                    ),
                  ),
                  _tile(
                    icon: Icons.tune_outlined,
                    title: '配置管理',
                    onTap: () {
                      final navigator = Navigator.of(context);
                      showDialog(
                        context: context,
                        builder: (_) => const ConfigManagementDialog(),
                      ).then((needRefresh) {
                        if (navigator.mounted && needRefresh == true) {
                          navigator.pushReplacement(
                            MaterialPageRoute(builder: (_) => HomePage()),
                          );
                        }
                      });
                    },
                  ),
                  _tile(
                    icon: Icons.font_download_outlined,
                    title: '字体',
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => FontManager(),
                    ),
                  ),
                  _tile(
                    icon: Icons.chat_bubble_outline,
                    title: '反馈',
                    onTap: () => _navigate(FeedbackPage()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: _tile(
                icon: Icons.logout_outlined,
                title: '退出登录',
                onTap: _logout,
              ),
            ),
          ],
        ),
      ),
    );
    return widget.persistent ? content : Drawer(width: 280, child: content);
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool selected = false,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    onTap: onTap,
    selected: selected,
    selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  );

  void _closeDrawer() {
    if (!widget.persistent) Scaffold.of(context).closeDrawer();
  }

  void _navigate(Widget page) {
    final navigator = Navigator.of(context);
    _closeDrawer();
    navigator.push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildAvatarSection() {
    return FutureBuilder<UserBasicInfo>(
      future: widget.userInfoFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final failed = snapshot.hasError;
        final profile = snapshot.data?.profile;
        final avatarUrl = profile?.avatar.url;
        final nickname = profile?.nickname ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                tooltip: '更换头像',
                onPressed: loading ? null : _updateAvatar,
                icon: CircleAvatar(
                  radius: 28,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(
                          '${HTTPConfig.indexServerAddress}$avatarUrl',
                        )
                      : null,
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : avatarUrl == null || avatarUrl.isEmpty
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              if (isEdit)
                TextField(
                  controller: nicknameController,
                  autofocus: true,
                  enabled: !_savingNickname,
                  onSubmitted: _editDone,
                  decoration: const InputDecoration(labelText: '昵称'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        loading
                            ? '正在加载账户…'
                            : failed
                            ? '账户信息未加载'
                            : nickname.isEmpty
                            ? '我的账户'
                            : nickname,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!loading && !failed)
                      IconButton(
                        tooltip: '修改昵称',
                        onPressed: () => setState(() {
                          nicknameController.text = nickname;
                          isEdit = true;
                        }),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                  ],
                ),
              if (isEdit)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _savingNickname
                          ? null
                          : () => setState(() => isEdit = false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: _savingNickname
                          ? null
                          : () => _editDone(nicknameController.text),
                      child: Text(_savingNickname ? '保存中…' : '保存'),
                    ),
                  ],
                )
              else if (failed)
                TextButton.icon(
                  onPressed: widget.onUserInfoUpdate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新加载'),
                )
              else if (snapshot.data?.email.isNotEmpty ?? false)
                Text(
                  snapshot.data!.email,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editDone(String nickname) async {
    final value = nickname.trim();
    if (value.isEmpty) {
      showErrMsg(context, '昵称不能为空');
      return;
    }
    setState(() => _savingNickname = true);
    try {
      final res = await official.Http().userProfile(
        official.RequestUpdateUserProfile(nickname: value),
      );
      if (!mounted) return;
      if (res.isNotOK) {
        setState(() => _savingNickname = false);
        showErrMsg(context, '昵称保存失败，请重试');
        return;
      }
      setState(() {
        isEdit = false;
        _savingNickname = false;
      });
      showSuccessMsg(context, '昵称已保存');
      widget.onUserInfoUpdate();
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingNickname = false);
      showErrMsg(context, '昵称保存失败，请稍后重试');
    }
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    _closeDrawer();
    await Config().close();
    await Storage().deleteCookie();
    SP().setIsAutoLogin(false);
    if (!navigator.mounted) return;
    navigator.pushReplacement(MaterialPageRoute(builder: (_) => Welcome()));
  }

  void _updateAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) {
      return;
    }
    final String ext = path.extension(image.path).toLowerCase();
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    switch (ext) {
      case '.png':
      case '.jpg':
      case '.jpeg':
        break;
      default:
        showErrMsg(context, "不支持的图片格式: $ext");
        return;
    }

    official.RequestUpdateUserProfile req = official.RequestUpdateUserProfile(
      bytes: bytes,
      ext: ext,
    );

    official.Http().userProfile(req).then((value) {
      if (value.isNotOK) return;
      if (mounted) {
        showSuccessMsg(context, "上传成功");
      }
      if (mounted) widget.onUserInfoUpdate();
    });
  }
}
