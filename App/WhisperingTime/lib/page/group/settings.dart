import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whispering_time/service/grpc/grpc.dart';
import 'package:whispering_time/util/ui.dart';
import 'package:whispering_time/util/export.dart';
import 'package:whispering_time/util/time.dart';

import 'model.dart';
import 'manager.dart';

class GroupSettings extends StatefulWidget {
  final Group group;
  final String tid;
  GroupSettings({required this.group, required this.tid});

  @override
  State<GroupSettings> createState() => _GroupSettingsState();
}

class _GroupSettingsState extends State<GroupSettings> {
  late final FocusNode _textFieldFocusNode;
  final TextEditingController _textController = TextEditingController();
  String _lastSyncedName = '';
  GroupsManager? _groups;
  Future<void> _renameQueue = Future<void>.value();
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _textFieldFocusNode = FocusNode();
    _lastSyncedName = widget.group.name;
    _textController.text = widget.group.name;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _groups = context.read<GroupsManager>();
  }

  @override
  void dispose() {
    // 在销毁前，如果名称有变化，确保同步到服务器
    if (_textController.text != _lastSyncedName) {
      rename(_textController.text);
    }
    _textFieldFocusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// 重命名分组
  /// 在设置页面修改名称后，同步到服务器并更新本地状态
  Future<void> rename(String newName, {bool ishttp = true}) async {
    if (newName.trim().isEmpty) return;
    final groups = _groups;
    if (groups == null) return;
    // Settings belong to the group that opened them, even if selection changes.
    final tid = widget.tid;
    final id = widget.group.id;
    if (mounted && !ishttp) {
      widget.group.name = newName;
      for (final item in groups.getItems(tid)) {
        if (item.id == id) item.name = newName;
      }
      groups.updateConfig();
    }
    if (!ishttp) return;
    _renameQueue = _renameQueue.then(
      (_) => _saveNameAfter(newName, tid, id, groups),
    );
    await _renameQueue;
  }

  Future<void> _saveNameAfter(
    String newName,
    String tid,
    String id,
    GroupsManager groups,
  ) async {
    // Compare at execution time so A → B → A saves the final A correctly.
    if (newName == _lastSyncedName) return;
    try {
      final res = await Grpc(
        tid: tid,
        gid: id,
      ).putGroup(RequestUpdateGroup(name: newName));
      if (res.isNotOK) {
        if (mounted) showErrMsg(context, '名称保存失败，请重试。');
        return;
      }
      _lastSyncedName = newName;
      if (!mounted) return;
      if (groups.tid == tid) groups.touch(gid: id);
    } catch (_) {
      if (mounted) showErrMsg(context, '名称保存失败，请重试。');
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
              Text('分组设置', style: theme.textTheme.titleLarge),
              const SizedBox(height: 24),
              TextField(
                focusNode: _textFieldFocusNode,
                controller: _textController,
                decoration: const InputDecoration(labelText: '分组名称'),
                onChanged: (value) {
                  rename(_textController.text, ishttp: false);
                },
              ),
              const SizedBox(height: 24),
              FreezeSwitchTile(
                item: widget.group,
                tid: widget.tid,
                onFreezeChanged: (newStatus, newIsFreezed) {
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: clickExportData,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('导出'),
                  ),
                  TextButton.icon(
                    onPressed: _isDeleting ? null : clickDeleteGroup,
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

  /// 按钮：删除分组
  /// 位置：在设置中
  Future<void> clickDeleteGroup() async {
    if (_isDeleting) return;
    final groups = _groups;
    if (groups == null) return;
    final id = widget.group.id;
    final tid = widget.tid;
    final confirmed = await showConfirmationDialog(
      context,
      MyDialog(content: '是否删除？', title: '提示'),
    );
    if (!mounted || !confirmed) return;
    setState(() => _isDeleting = true);
    try {
      final result = await Grpc(tid: tid, gid: id).deleteGroup();
      if (!mounted) return;
      if (result.isNotOK) {
        showErrMsg(context, '删除失败，请重试。');
        return;
      }
      final items = groups.getItems(tid);
      final index = items.indexWhere((item) => item.id == id);
      if (index >= 0) {
        if (groups.tid == tid) {
          groups.removeAt(index);
        } else {
          items.removeAt(index);
          groups.updateConfig();
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) showErrMsg(context, '删除失败，请重试。');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  /// 按钮：导出当前分组的印迹
  void clickExportData() {
    final gid = widget.group.id;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Export(ResourceType.group, tid: widget.tid, gid: gid);
      },
    );
  }

  /// 按钮：导出当前分组的配置
  void clickExportConfig() {
    Grpc(
      tid: widget.tid,
      gid: widget.group.id,
    ).exportGroupConfig().then((configData) {});
  }
}

/// 定格开关组件
/// 根据分组的定格状态显示不同的开关和说明
class FreezeSwitchTile extends StatefulWidget {
  final Group item;
  final String? tid;
  final void Function(int status, bool isFreezed) onFreezeChanged;
  const FreezeSwitchTile({
    super.key,
    required this.item,
    this.tid,
    required this.onFreezeChanged,
  });

  @override
  State<FreezeSwitchTile> createState() => _FreezeSwitchTileState();
}

class _FreezeSwitchTileState extends State<FreezeSwitchTile> {
  late int status;
  late bool isManual;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void didUpdateWidget(covariant FreezeSwitchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item ||
        oldWidget.item.overAt != widget.item.overAt ||
        oldWidget.item.updateAt != widget.item.updateAt) {
      setState(_refreshStatus);
    }
  }

  void _refreshStatus() {
    status = widget.item.getoverAtStatus();
    isManual = widget.item.isManualBufTime() || widget.item.isManualFreezed();
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: status,
      children: [
        _buildNotFreezedTile(),
        _buildBufferPeriodTile(),
        _buildFreezedTile(),
      ],
    );
  }

  Future<void> _handleToggle(bool value) async {
    if (_isProcessing) return;
    final prevStatus = status;
    final prevManual = isManual;
    final groups = context.read<GroupsManager>();
    final tid = widget.tid ?? groups.tid;
    final id = widget.item.id;
    final time = value ? Time.getOverDay() : Time.getForver();
    setState(() {
      _isProcessing = true;
      status = value ? 1 : (widget.item.isAutoBufTime() ? 1 : 0);
      isManual = value;
    });
    try {
      final res = await Grpc(
        tid: tid,
        gid: id,
      ).putGroup(RequestUpdateGroup(overAt: time));
      if (!mounted) return;
      if (res.isNotOK) {
        setState(() {
          status = prevStatus;
          isManual = prevManual;
        });
        showErrMsg(context, '定格设置失败，请重试。');
        return;
      }
      widget.item.overAt = time;
      for (final item in groups.getItems(tid)) {
        if (item.id == id) {
          item.overAt = time;
          item.updateAt = DateTime.now();
        }
      }
      groups.updateConfig();
      setState(() {
        status = value ? 1 : (widget.item.isAutoBufTime() ? 1 : 0);
        isManual = value;
      });
      widget.onFreezeChanged(status, status != 0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        status = prevStatus;
        isManual = prevManual;
      });
      showErrMsg(context, '定格设置失败，请重试。');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildNotFreezedTile() {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('定格'),
      subtitle: const Text(
        "定格后无法编辑，仅供回顾。7天内可取消。",
        style: TextStyle(fontSize: 12),
      ),
      value: isManual,
      onChanged: _isProcessing ? null : (bool value) => _handleToggle(value),
    );
  }

  Widget _buildBufferPeriodTile() {
    final isAuto = widget.item.isAutoBufTime() && !isManual;
    final subtitle = isAuto
        ? "进入7天定格缓冲期,缓冲期内若无任何更新动作，则定格此分组"
        : "已进入缓冲期,定格时间:${widget.item.overAt?.toString() ?? ''}";
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('定格'),
      subtitle: Text(subtitle),
      value: isManual,
      onChanged: _isProcessing ? null : (bool value) => _handleToggle(value),
    );
  }

  Widget _buildFreezedTile() {
    final isAuto = !isManual;
    final frozenTime = isAuto
        ? widget.item.updateAt.add(
            Duration(days: widget.item.config.autoFreezeDays),
          )
        : widget.item.overAt;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('定格'),
      subtitle: Text("已定格于${frozenTime.toString()}"),
      value: true,
      onChanged: null,
    );
  }
}
