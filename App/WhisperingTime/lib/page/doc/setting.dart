import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whispering_time/page/group/manager.dart';
import 'package:whispering_time/service/grpc/grpc.dart';
import 'package:whispering_time/util/env.dart';
import 'package:whispering_time/page/doc/model.dart';

class LastStateDocSetting {
  LastState state;
  DateTime? createAt;
  DocConfig? config;
  LastStateDocSetting({required this.state, this.config, this.createAt});
}

class DocSettingsDialog extends StatefulWidget {
  final String gid;
  final String? did;
  final DocConfig config;
  final bool fromBrowser;

  DocSettingsDialog({
    required this.gid,
    required this.did,
    required this.config,
    this.fromBrowser = false,
  });

  @override
  State<DocSettingsDialog> createState() => _DocSettingsDialogState();
}

class _DocSettingsDialogState extends State<DocSettingsDialog> {
  late int displayPriority;
  bool isChanged = false;
  bool _savingPriority = false;
  int _priorityFieldRevision = 0;

  void _touchGroup() {
    if (!mounted) return;
    context.read<GroupsManager>().touch(gid: widget.gid);
  }

  @override
  void initState() {
    super.initState();
    displayPriority = widget.config.displayPriority ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('文档设置'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey(_priorityFieldRevision),
                initialValue: displayPriority,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '显示优先',
                  helperText: _savingPriority
                      ? '正在保存显示方式…'
                      : _getDisplayPriorityDesc(displayPriority),
                ),
                onChanged: _savingPriority ? null : _setDisplayPriority,
                items: [
                  DropdownMenuItem(value: 0, child: Text('完整')),
                  DropdownMenuItem(value: 1, child: Text('文字优先')),
                  DropdownMenuItem(value: 2, child: Text('媒体优先')),
                ],
              ),
              const SizedBox(height: 20),
              // 删除文档按钮
              if (widget.did != null)
                ListTile(
                  leading: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    '删除文档',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () async {
                    final ok = await _deleteDoc();
                    if (!ok) return;
                    if (!mounted) return;
                    Navigator.of(this.context)
                        .pop({'changed': false, 'deleted': true});
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消'),
        ),
        ElevatedButton(
          onPressed: _savingPriority
              ? null
              : () {
                  Navigator.of(context).pop({
                    'changed': isChanged,
                    'config': DocConfig(displayPriority: displayPriority),
                  });
                },
          child: Text('确定'),
        ),
      ],
    );
  }

  // 设置显示优先
  Future<void> _setDisplayPriority(int? value) async {
    if (value == null || value == displayPriority || _savingPriority) return;
    setState(() {
      _savingPriority = true;
    });
    try {
      if (widget.did != null) {
        final res = await Grpc(
          gid: widget.gid,
          did: widget.did,
        ).putDoc(RequestUpdateDoc(config: DocConfig(displayPriority: value)));
        if (!mounted) return;
        if (res.isNotOK) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('设置失败，请重试')));
          return;
        }
        _touchGroup();
      }
      if (!mounted) return;
      setState(() {
        displayPriority = value;
        isChanged = true;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置失败，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingPriority = false;
          // 重建表单字段，将失败的选择恢复成最后成功保存的值。
          _priorityFieldRevision++;
        });
      }
    }
  }

  String _getDisplayPriorityDesc(int priority) {
    switch (priority) {
      case 0:
        return '详细显示印迹，图文混排';
      case 1:
        return '文字为主，图片以缩略图形式';
      case 2:
        return '媒体为主，文字最小化显示';
      default:
        return '';
    }
  }

  // 删除文档
  Future<bool> _deleteDoc() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('确定要删除这篇文档吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return false;
    }

    final res = await Grpc(gid: widget.gid, did: widget.did).deleteDoc();
    if (!mounted) return false;

    if (res.isNotOK) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败')));
      return false;
    }

    _touchGroup();
    return true;
  }
}
