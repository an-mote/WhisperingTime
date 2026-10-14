import 'dart:io';

import 'package:flutter/material.dart';
import 'package:whispering_time/design/widgets.dart';
import 'package:whispering_time/service/isar/config.dart';
import 'package:whispering_time/service/sp/sp.dart';
import 'package:whispering_time/util/path.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:whispering_time/welcome.dart';
import 'package:whispering_time/service/http/official.dart';
import 'package:whispering_time/service/grpc/grpc.dart';
import 'package:whispering_time/grpc_generated/whisperingtime.pb.dart';
import 'package:whispering_time/util/secure.dart';

class SettingPage extends StatefulWidget {
  @override
  State createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool _isOpened = Config.instance.devlopMode;
  TextEditingController serverAddressControl = TextEditingController();
  String isarurl = '';
  bool visualNoneTitle = Config.instance.visualNoneTitle;
  bool defaultShowTool = Config.instance.defaultShowTool;
  bool keepAnimationWhenLostFocus = Config.instance.keepAnimationWhenLostFocus;

  @override
  void initState() {
    super.initState();
    serverAddressControl.text = Config.instance.serverAddress;
    init();
  }

  Future<void> init() async {
    final url = await Config().getInspectorURL();
    if (mounted) setState(() => isarurl = url);
  }

  @override
  void dispose() {
    serverAddressControl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: backPage,
        ),
        title: const Text('设置'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const ImprintSectionHeader(
                  title: '让记录更合心意',
                  subtitle: '显示偏好会自动保存',
                ),
                const SizedBox(height: 32),
                _section(
                  title: '显示',
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('隐藏空白标题'),
                        value: visualNoneTitle,
                        onChanged: (value) => setState(() {
                          visualNoneTitle = value;
                          Config.instance.setVisualNoneTitle(value);
                        }),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('默认显示工具栏'),
                        value: defaultShowTool,
                        onChanged: (value) => setState(() {
                          defaultShowTool = value;
                          Config.instance.setDefaultShowTool(value);
                        }),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('失去焦点保持动画'),
                        value: keepAnimationWhenLostFocus,
                        onChanged: (value) => setState(() {
                          keepAnimationWhenLostFocus = value;
                          Config.instance.setKeepAnimationWhenLostFocus(value);
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _section(
                  title: '账号与数据',
                  child: ListTile(
                    leading: Icon(
                      Icons.manage_accounts_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('清空账号'),
                    subtitle: const Text('删除应用数据或注销账户'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showClearAccountDialog,
                  ),
                ),
                const SizedBox(height: 24),
                _section(
                  title: '调试',
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('开发者模式'),
                        value: _isOpened,
                        onChanged: (value) => setState(() {
                          Config.instance.setDevlopMode(value);
                          _isOpened = value;
                        }),
                      ),
                      if (_isOpened) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: serverAddressControl,
                            maxLines: 1,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: '服务器地址',
                              prefixIcon: Icon(Icons.dns_outlined),
                            ),
                            onChanged: Config.instance.setServerAddress,
                          ),
                        ),
                        if (isarurl.isNotEmpty)
                          ListTile(
                            title: const Text('数据库后台管理'),
                            trailing: TextButton(
                              onPressed: () => _launchUrl(isarurl),
                              child: const Text('打开'),
                            ),
                          ),
                        ListTile(
                          title: const Text('本地数据管理'),
                          trailing: TextButton(
                            onPressed: cleanDatabase,
                            child: const Text('清空'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      ImprintPanel(padding: const EdgeInsets.all(8), child: child),
    ],
  );

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      throw Exception('Could not launch $url');
    }
  }

  void _showClearAccountDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('清空账号'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('删除应用数据'),
                subtitle: Text('执行后，当前应用的本地数据和云端数据将删除。'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(false);
                },
              ),
              ListTile(
                title: Text('删除账户'),
                subtitle: Text('执行后，当前账号的信息将无法登录任何应用。'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(bool isDeleteAccount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认操作'),
        content: Text(
          isDeleteAccount ? '确定要注销账户吗？此操作不可逆。' : '确定要删除应用数据吗？此操作不可逆。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _executeDelete(isDeleteAccount);
            },
            child: Text(
              '确定',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _executeDelete(bool isDeleteAccount) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. HTTP Request
      final http = Http();
      final res = isDeleteAccount
          ? await http.deleteAccount()
          : await http.unbindApp();
      if (!mounted) return;
      if (res.isNotOK) {
        Navigator.pop(context); // Dismiss loading
        return;
      }

      // 2. gRPC Request
      final grpcRes = await Grpc().deleteUserData(DeleteUserDataRequest());
      if (!mounted) return;
      if (grpcRes.isNotOK) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('服务器数据删除失败: ${grpcRes.msg}')));
        return;
      }

      // 3. Clear Local Data
      await Storage().deleteAll();
      cleanDatabase();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发生错误: $e')));
    }
  }

  void cleanDatabase() async {
    final isarPath = await Config().getFilePath();
    final isarLockPath = "$isarPath.lock";
    await Config().close();
    SP().over();
    final info = await PackageInfo.fromPlatform();
    final d = await getLibraryDir();
    final spPath = path.join(
      d.path,
      "Preferences",
      "${info.packageName}.plist",
    );
    print("isarPath: $isarPath");
    print("spPath: $spPath");

    final isarFile = File(isarPath);
    if (await isarFile.exists()) {
      await isarFile.delete();
    }
    final lockFile = File(isarLockPath);
    if (await lockFile.exists()) {
      await lockFile.delete();
    }
    final spFile = File(spPath);
    if (await spFile.exists()) {
      await spFile.delete();
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => Welcome()),
      );
    }
  }

  void backPage() {
    if (_isOpened != Config.instance.devlopMode) {
      Config.instance.setDevlopMode(_isOpened);
    }
    if (serverAddressControl.text != Config.instance.serverAddress) {
      Config.instance.setServerAddress(serverAddressControl.text);
    }
    Navigator.of(context).pop();
  }
}
