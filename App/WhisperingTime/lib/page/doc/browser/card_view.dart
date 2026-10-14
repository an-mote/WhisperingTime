import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:intl/intl.dart';
import 'package:whispering_time/page/doc/model.dart';
import 'package:whispering_time/page/doc/manager.dart';
import 'package:whispering_time/util/env.dart';
import 'package:whispering_time/service/isar/config.dart';
import 'package:whispering_time/page/doc/browser/image_utils.dart';
import 'package:whispering_time/page/doc/browser/bubble.dart';

class DocCardList extends StatefulWidget {
  final DocsManager docsManager;
  final int? expandedIndex;
  final Map<String, bool> flippedStates;
  final Function(int?) onToggleExpand;
  final Function(int, Doc) onEdit;
  final Function(Doc) onSetting;
  final Function(String, bool) onFlip;

  const DocCardList({
    super.key,
    required this.docsManager,
    required this.expandedIndex,
    required this.flippedStates,
    required this.onToggleExpand,
    required this.onEdit,
    required this.onSetting,
    required this.onFlip,
  });

  @override
  State<DocCardList> createState() => _DocCardListState();
}

class _DocCardListState extends State<DocCardList> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth < 600 ? 16.0 : 32.0;
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
          itemCount: widget.docsManager.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final item = widget.docsManager.items[index];
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: _buildCard(index, item),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCard(int index, Doc item) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final expanded = widget.expandedIndex == index;
    final priority = item.config.displayPriority ?? 0;
    final images = extractImages(item.content);
    final flipped = widget.flippedStates[item.id] ?? false;
    final level = item.level.clamp(0, Level.l.length - 1);
    final textOnly = priority == 1;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child:
                    (item.title.isNotEmpty || Config.instance.visualNoneTitle)
                    ? Text(
                        item.title.isEmpty ? '未命名' : item.title,
                        style: theme.textTheme.titleLarge,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '印迹设置',
                icon: const Icon(Icons.more_horiz),
                onPressed: () => widget.onSetting(item),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: Icon(
                  level >= 3 ? Icons.bookmark_outline : Icons.label_outline,
                  size: 18,
                ),
                label: Text(Level.l[level]),
                backgroundColor: level >= 3
                    ? cs.primaryContainer
                    : cs.surfaceContainerLow,
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  color: level >= 3
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
              _DocDateLabel(time: item.createAt),
            ],
          ),
          const SizedBox(height: 16),
          if (flipped) ...[
            if (images.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('这篇印迹还没有图片。', style: theme.textTheme.bodyMedium),
              )
            else
              _DocImageGallery(images: images),
          ] else ...[
            if (expanded)
              _DocRichContent(
                content: item.content,
                textOnly: textOnly || images.isNotEmpty,
              )
            else
              InkWell(
                onTap: () => widget.onToggleExpand(index),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _plainContent(item.content).isEmpty
                        ? '这篇印迹还没有正文。'
                        : _plainContent(item.content),
                    maxLines: priority == 2 ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            if (images.isNotEmpty && (!textOnly || priority == 2)) ...[
              const SizedBox(height: 16),
              _DocImageGallery(images: images),
            ],
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () {
                  if (flipped) {
                    widget.onFlip(item.id, false);
                  } else {
                    widget.onToggleExpand(expanded ? null : index);
                  }
                },
                icon: Icon(
                  flipped
                      ? Icons.article_outlined
                      : expanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                label: Text(
                  flipped
                      ? '返回正文'
                      : expanded
                      ? '收起正文'
                      : '展开正文',
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onEdit(index, item),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
              if (textOnly && images.isNotEmpty && !flipped)
                TextButton.icon(
                  onPressed: () => widget.onFlip(item.id, true),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text('图片 ${images.length}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _plainContent(String content) {
  if (content.isEmpty) return '';
  try {
    final decoded = jsonDecode(content);
    final rich = decoded is Map && decoded['rich'] is List
        ? decoded['rich']
        : decoded;
    if (rich is List &&
        rich.any((op) => op is Map && op.containsKey('insert'))) {
      return rich
          .whereType<Map>()
          .map((op) => op['insert'] is String ? op['insert'] as String : '')
          .join()
          .trim();
    }
    final scales = decoded is Map ? decoded['scales'] : decoded;
    if (scales is List) {
      return scales
          .whereType<Map>()
          .map((scale) {
            final title = scale['title'] ?? '刻度';
            final value = scale['current_value'] ?? '未填写';
            final unit = scale['has_unit'] == true ? scale['unit'] ?? '' : '';
            return '$title · $value${unit.toString().isEmpty ? '' : ' $unit'}';
          })
          .join('\n');
    }
  } catch (_) {
    return content;
  }
  return content;
}

class _DocDateLabel extends StatefulWidget {
  final DateTime time;
  const _DocDateLabel({required this.time});
  @override
  State<_DocDateLabel> createState() => _DocDateLabelState();
}

class _DocDateLabelState extends State<_DocDateLabel> {
  bool _showTime = false;
  String _relativeDate() {
    final difference = DateTime.now().difference(widget.time);
    if (difference.inSeconds < 60) return '刚刚';
    if (difference.inMinutes < 60) return '${difference.inMinutes}分钟前';
    if (difference.inHours < 24) return '${difference.inHours}小时前';
    if (difference.inDays < 7) return '${difference.inDays}天前';
    if (difference.inDays < 30) return '${difference.inDays ~/ 7}周前';
    if (difference.inDays < 365) return '${difference.inDays ~/ 30}月前';
    return '${difference.inDays ~/ 365}年前';
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          '创建于 ${DateFormat('yyyy年M月d日 HH:mm').format(widget.time)}，点击切换日期显示',
      child: TextButton.icon(
        onPressed: () => setState(() => _showTime = !_showTime),
        icon: const Icon(Icons.schedule_outlined, size: 16),
        label: Text(
          _showTime
              ? DateFormat('yyyy年M月d日 HH:mm').format(widget.time)
              : _relativeDate(),
        ),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DocImageGallery extends StatefulWidget {
  final List<String> images;
  const _DocImageGallery({required this.images});
  @override
  State<_DocImageGallery> createState() => _DocImageGalleryState();
}

class _DocImageGalleryState extends State<_DocImageGallery> {
  final PageController _controller = PageController();
  int _page = 0;
  @override
  void didUpdateWidget(covariant _DocImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.images, widget.images)) {
      _page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: PageView.builder(
                controller: _controller,
                scrollBehavior: const MaterialScrollBehavior().copyWith(
                  dragDevices: {
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                onPageChanged: (page) => setState(() => _page = page),
                itemCount: widget.images.length,
                itemBuilder: (context, index) => Semantics(
                  label: '印迹图片 ${index + 1}，共 ${widget.images.length} 张',
                  image: true,
                  child: DocImage(imageSource: widget.images[index]),
                ),
              ),
            ),
          ),
        ),
        if (widget.images.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一张图片',
                onPressed: _page == 0
                    ? null
                    : () => _controller.jumpToPage(_page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_page + 1} / ${widget.images.length}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              IconButton(
                tooltip: '下一张图片',
                onPressed: _page == widget.images.length - 1
                    ? null
                    : () => _controller.jumpToPage(_page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}

class _DocRichContent extends StatefulWidget {
  final String content;
  final bool textOnly;
  const _DocRichContent({required this.content, required this.textOnly});
  @override
  State<_DocRichContent> createState() => _DocRichContentState();
}

class _DocRichContentState extends State<_DocRichContent> {
  QuillController? _controller;
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DocRichContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.textOnly != widget.textOnly) {
      _controller?.dispose();
      _controller = null;
      _load();
    }
  }

  void _load() {
    try {
      final decoded = jsonDecode(widget.content);
      var rich = decoded is Map && decoded['rich'] is List
          ? decoded['rich']
          : decoded;
      if (rich is! List ||
          !rich.any((op) => op is Map && op.containsKey('insert'))) {
        return;
      }
      if (widget.textOnly) {
        rich = rich
            .where(
              (op) =>
                  !(op is Map &&
                      op['insert'] is Map &&
                      (op['insert'] as Map).containsKey('image')),
            )
            .toList();
      }
      _controller = QuillController(
        document: Document.fromJson(rich),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } catch (_) {
      // Legacy and scale payloads are rendered as text below.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      final text = _plainContent(widget.content);
      return Text(
        text.isEmpty ? '这篇印迹还没有正文。' : text,
        style: Theme.of(context).textTheme.bodyLarge,
      );
    }
    return QuillEditor(
      controller: _controller!,
      focusNode: _focus,
      scrollController: _scroll,
      config: QuillEditorConfig(
        embedBuilders: [
          CustomImageEmbedBuilder(),
          ...(kIsWeb
                  ? FlutterQuillEmbeds.editorWebBuilders()
                  : FlutterQuillEmbeds.editorBuilders())
              .where((builder) => builder.key != 'image'),
        ],
        scrollable: false,
        autoFocus: false,
        expands: false,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
