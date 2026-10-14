import 'package:flutter/material.dart';
import 'package:whispering_time/service/grpc/grpc.dart';
import 'package:whispering_time/util/ui.dart';
import 'package:whispering_time/util/export.dart';

import 'browser.dart';

class ThemeSettings extends StatefulWidget {
  final ThemeItem theme;
  final Function(String newName) onRenamed;
  final Function() onDeleted;

  const ThemeSettings({
    super.key,
    required this.theme,
    required this.onRenamed,
    required this.onDeleted,
  });

  @override
  State<ThemeSettings> createState() => _ThemeSettingsState();
}

class _ThemeSettingsState extends State<ThemeSettings> {
  late final FocusNode _textFieldFocusNode;
  final TextEditingController _textController = TextEditingController();
  late String _lastSyncedName;
  Future<void>? _savingName;
  String? _nameError;
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    _textFieldFocusNode = FocusNode();
    _textController.text = widget.theme.name;
    _lastSyncedName = widget.theme.name;

    // 监听焦点变化，失去焦点时自动保存
    _textFieldFocusNode.addListener(() {
      if (!_textFieldFocusNode.hasFocus) {
        if (_textController.text != _lastSyncedName) {
          rename(_textController.text);
        }
      }
    });
  }

  @override
  void dispose() {
    _disposing = true;
    if (_textController.text != _lastSyncedName) {
      rename(_textController.text);
    }
    _textFieldFocusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// 重命名主题
  /// 在设置页面修改名称后，同步到服务器并更新本地状态
  Future<void> rename(String newName, {bool ishttp = true}) async {
    if (newName.trim().isEmpty) {
      return;
    }

    if (!ishttp) {
      if (!_disposing && mounted) widget.onRenamed(newName);
      return;
    }
    if (_savingName == null && newName == _lastSyncedName) return;
    final task = _saveNameAfter(_savingName, newName);
    _savingName = task;
    if (!_disposing && mounted) setState(() {});
    await task;
    if (identical(_savingName, task)) _savingName = null;
    if (!_disposing && mounted) setState(() {});
  }

  Future<void> _saveNameAfter(Future<void>? pending, String newName) async {
    if (pending != null) await pending;
    if (newName == _lastSyncedName) return;
    await _saveName(newName);
  }

  Future<void> _saveName(String newName) async {
    try {
      final res = await Grpc(tid: widget.theme.id)
          .updateTheme(RequestUpdateTheme(name: newName));
      if (res.isNotOK) {
        _nameError = '名称保存失败，请重试';
        return;
      }
      _lastSyncedName = newName;
      _nameError = null;
    } catch (_) {
      _nameError = '名称保存失败，请重试';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('主题设置', style: theme.textTheme.titleLarge),
              const SizedBox(height: 24),
              TextField(
                focusNode: _textFieldFocusNode,
                controller: _textController,
                decoration: InputDecoration(
                  labelText: '主题名称',
                  errorText: _nameError,
                  helperText: _savingName != null ? '正在保存名称…' : null,
                ),
                onChanged: (value) {
                  rename(_textController.text, ishttp: false);
                },
              ),
              if (_nameError != null)
                TextButton(
                  onPressed: _savingName == null
                      ? () => rename(_textController.text)
                      : null,
                  child: const Text('重试保存'),
                ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: clickExport,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('导出'),
                  ),
                  TextButton.icon(
                    onPressed: clickDeleteTheme,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 按钮：删除主题
  /// 位置：在设置中
  void clickDeleteTheme() async {
    if (!(await showConfirmationDialog(
      context,
      MyDialog(content: "是否删除？", title: "提示"),
    ))) {
      return;
    }

    final res = await Grpc(tid: widget.theme.id).deleteTheme();

    if (res.isNotOK) {
      return;
    }

    if (mounted) {
      widget.onDeleted();
      Navigator.of(context).pop();
    }
  }

  /// 按钮：导出当前主题
  /// 位置：在设置中
  void clickExport() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Export(ResourceType.theme, tid: widget.theme.id);
      },
    );
  }
}
