import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whispering_time/design/widgets.dart';
import 'package:whispering_time/page/doc/browser/doc_list.dart';

import 'manager.dart';
import 'model.dart';
import 'settings.dart';

class GroupPage extends StatefulWidget {
  final String? id;
  final String tid;
  final String themename;
  final VoidCallback? onCreateGroup;

  const GroupPage({
    super.key,
    required this.themename,
    required this.tid,
    this.id,
    this.onCreateGroup,
  });

  @override
  State<GroupPage> createState() => _GroupPage();
}

class _GroupPage extends State<GroupPage> with AutomaticKeepAliveClientMixin {
  Future<bool>? _loadGroups;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  void _reload() {
    final future = context.read<GroupsManager>().get(widget.tid);
    setState(() {
      _loadGroups = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final groups = context.watch<GroupsManager>();
    final items = groups.getItems(widget.tid);
    return FutureBuilder<bool>(
      future: _loadGroups,
      builder: (context, snapshot) {
        if (_loadGroups == null ||
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == false) {
          return ImprintEmptyState(
            icon: Icons.cloud_off_outlined,
            title: '分组暂时无法加载',
            message: '请检查网络连接后重试，你的记录仍会保留。',
            action: OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          );
        }
        if (items.isEmpty) {
          return ImprintEmptyState(
            icon: Icons.folder_open_outlined,
            title: '给这个主题添一个分组',
            message: '将相近的记录放在一起，日后更容易找到。',
            action: widget.onCreateGroup == null
                ? null
                : FilledButton.icon(
                    onPressed: widget.onCreateGroup,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('新建分组'),
                  ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(inset, 24, inset, 32),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _groupCard(items[index], index),
            );
          },
        );
      },
    );
  }

  Widget _groupCard(Group item, int index) {
    final theme = Theme.of(context);
    final status = item.getoverAtStatus();
    final caption = status == 2
        ? '已定格 · 打开回顾'
        : status == 1
        ? '定格缓冲期 · 打开查看'
        : '打开分组，继续记录';
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        minLeadingWidth: 40,
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              status == 2 ? Icons.inventory_2_outlined : Icons.folder_outlined,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          item.name,
          style: theme.textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(caption, style: theme.textTheme.bodyMedium),
        ),
        trailing: IconButton(
          tooltip: '管理${item.name}',
          icon: const Icon(Icons.more_horiz),
          onPressed: () => _showSettings(item, index),
        ),
        onLongPress: () => _showSettings(item, index),
        onTap: () {
          final manager = context.read<GroupsManager>();
          if (manager.tid != widget.tid) manager.setThemeID(widget.tid);
          manager.setIndex(index);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                value: manager,
                child: DocList(group: item, tid: widget.tid),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSettings(Group item, int index) {
    final manager = context.read<GroupsManager>();
    if (manager.tid != widget.tid) manager.setThemeID(widget.tid);
    manager.setIndex(index);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: manager,
        child: GroupSettings(group: item, tid: widget.tid),
      ),
    );
  }
}
