import 'dart:async';

import 'package:flutter/material.dart';
import 'package:whispering_time/design/widgets.dart';
import 'package:whispering_time/service/http/official.dart';
import 'package:whispering_time/service/sp/sp.dart';
import 'package:whispering_time/util/ui.dart';

import 'edit.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  List<FeedBack> _items = [];
  final searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  int _requestNumber = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    getItems();
  }

  @override
  void dispose() {
    _requestNumber++;
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> getItems() async {
    _searchDebounce?.cancel();
    final request = ++_requestNumber;
    final query = searchController.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = query.isEmpty
          ? await Http().getFeedbacks()
          : await Http().getFeedbacks(text: query);
      if (!mounted || request != _requestNumber) return;
      if (value.isNotOK) {
        setState(() => _error = '反馈暂时无法加载，请重试。');
        return;
      }
      setState(() => _items = value.data);
    } catch (_) {
      if (mounted && request == _requestNumber) {
        setState(() => _error = '反馈暂时无法加载，请重试。');
      }
    } finally {
      if (mounted && request == _requestNumber) {
        setState(() => _loading = false);
      }
    }
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    // Invalidate existing responses immediately, including the debounce window.
    _requestNumber++;
    setState(() {
      _loading = true;
      _error = null;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) getItems();
    });
  }

  Future<void> add() async {
    if (SP().getIsVisitor()) {
      showErrMsg(context, '游客无法创建反馈');
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (context) => const Edit()),
    );
    if (mounted) getItems();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('反馈'),
        actions: [
          IconButton(
            tooltip: '提交反馈',
            icon: const Icon(Icons.add_rounded),
            onPressed: add,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: TextField(
                    controller: searchController,
                    onChanged: (_) => _scheduleSearch(),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => getItems(),
                    decoration: InputDecoration(
                      labelText: '搜索反馈',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: '清除搜索',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                searchController.clear();
                                getItems();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                Expanded(child: _buildContent(theme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: '正在加载反馈'),
      );
    }
    if (_error != null) {
      return ImprintEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '加载未完成',
        message: _error!,
        action: OutlinedButton.icon(
          onPressed: getItems,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
      );
    }
    if (_items.isEmpty) {
      return ImprintEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: searchController.text.isEmpty ? '还没有反馈' : '没有匹配的反馈',
        message: searchController.text.isEmpty
            ? '遇到问题或有新的建议，可以在这里告诉我们。'
            : '试试其他关键词，或清除搜索查看全部反馈。',
        action: searchController.text.isEmpty
            ? OutlinedButton.icon(
                onPressed: add,
                icon: const Icon(Icons.add_rounded),
                label: const Text('提交反馈'),
              )
            : TextButton(
                onPressed: () {
                  searchController.clear();
                  getItems();
                },
                child: const Text('清除搜索'),
              ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: _items.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  item.content.length > 100
                      ? '${item.content.substring(0, 100)}…'
                      : item.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '创建时间：${item.createAt}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
