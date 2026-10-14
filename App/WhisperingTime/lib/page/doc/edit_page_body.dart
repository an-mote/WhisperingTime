import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:provider/provider.dart';

import 'package:whispering_time/page/doc/zk_model.dart';
import 'package:whispering_time/page/doc/scale_template_creator_dialog.dart';
import 'package:whispering_time/service/scale/scale_service.dart';

enum ImageTextLayout { mixed, separated }

enum TextFormat { richText, markdown }

class EditPageBody extends StatefulWidget {
  final QuillController quillController;
  final FocusNode focusNode;
  final bool showToolbar;
  final VoidCallback onPaste;
  final List<EmbedBuilder> embedBuilders;
  final ScaleService scaleService;
  final bool showScalePanel;
  final bool showImageTextPanel;
  final ImageTextLayout imageTextLayout;
  final TextFormat textFormat;
  final TextEditingController markdownController;
  final ValueChanged<ImageTextLayout>? onImageTextLayoutChanged;

  const EditPageBody({
    super.key,
    required this.quillController,
    required this.focusNode,
    required this.showToolbar,
    required this.onPaste,
    required this.embedBuilders,
    required this.scaleService,
    this.showScalePanel = true,
    this.showImageTextPanel = true,
    this.imageTextLayout = ImageTextLayout.mixed,
    this.textFormat = TextFormat.richText,
    required this.markdownController,
    this.onImageTextLayoutChanged,
  });

  @override
  State<EditPageBody> createState() => _EditPageBodyState();
}

class _EditPageBodyState extends State<EditPageBody> {
  final ScrollController _editorScroll = ScrollController();
  StreamSubscription<DocChange>? _contentChanges;
  bool _isImageTextEditorEmpty = true;
  bool _isScaleEditMode = false;

  bool _hasTappedImageTextPanel = false;
  bool _showImageTextLayoutSelector = false;

  bool _computeIsEditorEmpty(Document doc) {
    final plain = doc.toPlainText().trim();
    final hasEmbed = doc.toDelta().toList().any(
      (op) => op.data is Map<String, dynamic> || op.data is Map,
    );
    return plain.isEmpty && !hasEmbed;
  }

  bool _computeIsMarkdownEmpty(String text) {
    return text.trim().isEmpty;
  }

  void _onEditorChanged() {
    final next = widget.textFormat == TextFormat.markdown
        ? _computeIsMarkdownEmpty(widget.markdownController.text)
        : _computeIsEditorEmpty(widget.quillController.document);
    if (next != _isImageTextEditorEmpty) {
      setState(() {
        _isImageTextEditorEmpty = next;
      });
    }
  }

  Widget _buildCenteredAddButton({
    required ThemeData theme,
    required VoidCallback onPressed,
    String? label,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            label == '添加刻度'
                ? Icons.straighten_outlined
                : Icons.article_outlined,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            label == '添加刻度' ? '看见生活里的变化' : '整理这一刻的图文',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            label == '添加刻度' ? '用数值或文字，记录值得关注的日常。' : '图文草稿暂不保存，离开页面后不会保留。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add),
            label: Text(label ?? '添加'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _isImageTextEditorEmpty = widget.textFormat == TextFormat.markdown
        ? _computeIsMarkdownEmpty(widget.markdownController.text)
        : _computeIsEditorEmpty(widget.quillController.document);
    widget.quillController.addListener(_onEditorChanged);
    _contentChanges = widget.quillController.document.changes.listen(
      (_) => _onEditorChanged(),
    );
    widget.markdownController.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _contentChanges?.cancel();
    _editorScroll.dispose();
    widget.quillController.removeListener(_onEditorChanged);
    widget.markdownController.removeListener(_onEditorChanged);
    super.dispose();
  }

  Future<void> _openTemplatePicker() async {
    final model = context.read<DocumentModel>();

    final selected = await showDialog<ScaleTemplatePlain>(
      context: context,
      builder: (ctx) {
        var templatesFuture = _loadTemplatesPlain();

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> refresh() async {
              setState(() {
                templatesFuture = _loadTemplatesPlain();
              });
            }

            return AlertDialog(
              title: const Text('添加刻度'),
              content: SizedBox(
                width: 360,
                height: 360,
                child: FutureBuilder<List<ScaleTemplatePlain>>(
                  future: templatesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_outlined),
                            const SizedBox(height: 12),
                            const Text(
                              '暂时无法载入刻度模板',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: refresh,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      );
                    }
                    final items = snapshot.data ?? const <ScaleTemplatePlain>[];
                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.straighten_outlined),
                            const SizedBox(height: 12),
                            Text(
                              '还没有刻度模板',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '新建一个模板，记录步数、心情或自己的生活指标。',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final t = items[i];
                        final unitPart = (t.hasUnit && t.unit.trim().isNotEmpty)
                            ? ' · 单位: ${t.unit.trim()}'
                            : '';
                        return ListTile(
                          title: Text(t.title.isEmpty ? '(未命名)' : t.title),
                          subtitle: Text(
                            "记录方式: ${t.interactionMode == ScaleInteractionMode.selection ? '选项选择' : '手动填写'} · "
                            "数据格式: ${t.dataType == ScaleDataType.text ? '文字' : '数值'}$unitPart",
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '编辑',
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () async {
                                  final updated =
                                      await showDialog<ScaleTemplatePlain>(
                                        context: ctx,
                                        builder: (dCtx) =>
                                            ScaleTemplateCreatorDialog(
                                              scaleService: widget.scaleService,
                                              initialTemplate: t,
                                            ),
                                      );
                                  if (updated != null) {
                                    await refresh();
                                  }
                                },
                              ),
                              IconButton(
                                tooltip: '删除',
                                icon: const Icon(Icons.delete, size: 18),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: ctx,
                                    builder: (cCtx) => AlertDialog(
                                      title: const Text('删除刻度模板'),
                                      content: Text(
                                        '确定删除“${t.title.isEmpty ? '(未命名)' : t.title}”？',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(cCtx).pop(false),
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(cCtx).pop(true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirmed != true) return;

                                  await widget.scaleService.deleteScaleTemplate(
                                    id: t.id,
                                  );
                                  await refresh();
                                },
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(ctx).pop(t),
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _openCreateTemplate();
                  },
                  child: const Text('新建模板'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (selected != null) {
      model.addScaleFromTemplate(selected);
    }
  }

  Future<List<ScaleTemplatePlain>> _loadTemplatesPlain() async {
    final encrypted = await widget.scaleService.listScaleTemplates();
    final plain = <ScaleTemplatePlain>[];
    for (final record in encrypted) {
      final meta = await widget.scaleService.decryptMetadata(
        record.encryptedMetadata,
      );
      plain.add(ScaleTemplatePlain.fromMetadata(id: record.id, metadata: meta));
    }
    return plain;
  }

  Future<void> _openCreateTemplate() async {
    final created = await showDialog<ScaleTemplatePlain>(
      context: context,
      builder: (ctx) =>
          ScaleTemplateCreatorDialog(scaleService: widget.scaleService),
    );

    if (!mounted) return;
    if (created != null) {
      context.read<DocumentModel>().addScaleFromTemplate(created);
    }
  }

  Widget _buildScalePanel(ThemeData theme) {
    final cs = theme.colorScheme;
    return Consumer<DocumentModel>(
      builder: (context, model, _) {
        return _DashedBorder(
          color: cs.outlineVariant,
          radius: 18,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(16),
            child: model.scales.isEmpty
                ? SingleChildScrollView(
                    child: _buildCenteredAddButton(
                      theme: theme,
                      onPressed: _openTemplatePicker,
                      label: '添加刻度',
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '生活刻度',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (!_isScaleEditMode)
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _isScaleEditMode = true),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('编辑'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: model.scales.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final scale = model.scales[index];
                            return _ScaleInstanceTile(
                              title: scale.title,
                              interactionMode: scale.interactionMode,
                              dataType: scale.dataType,
                              options: scale.options,
                              unit: scale.hasUnit ? scale.unit : null,
                              value: scale.currentValue,
                              onChanged: (value) =>
                                  model.setScaleValue(index, value),
                              onRemove: () => model.removeScaleAt(index),
                              textColor: cs.onSurface,
                              isEditing: _isScaleEditMode,
                            );
                          },
                        ),
                      ),
                      if (_isScaleEditMode) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _openTemplatePicker,
                              icon: const Icon(Icons.add),
                              label: const Text('添加刻度'),
                            ),
                            FilledButton.icon(
                              onPressed:
                                  model.scales.every(
                                    (scale) =>
                                        scale.interactionMode !=
                                            ScaleInteractionMode.input ||
                                        (scale.currentValue
                                                ?.trim()
                                                .isNotEmpty ??
                                            false),
                                  )
                                  ? () =>
                                        setState(() => _isScaleEditMode = false)
                                  : null,
                              icon: const Icon(Icons.check),
                              label: const Text('完成'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildImageTextPanel(ThemeData theme) {
    final cs = theme.colorScheme;
    final panelRadius = BorderRadius.circular(18);

    Widget buildLayoutSelector() {
      final hint = cs.onSurfaceVariant;

      Widget tile({
        required ImageTextLayout value,
        required IconData icon,
        required String title,
        required String desc,
      }) {
        final titleColor = cs.onSurface;
        final iconColor = cs.onSurfaceVariant;
        final descColor = hint;

        return InkWell(
          onTap: () {
            setState(() {
              _showImageTextLayoutSelector = false;
            });
            widget.onImageTextLayoutChanged?.call(value);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: iconColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        desc,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: descColor,
                          height: 1.2,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tile(
              value: ImageTextLayout.mixed,
              icon: Icons.view_quilt_outlined,
              title: '图文混排',
              desc: '公众号文章、邮件等',
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
            tile(
              value: ImageTextLayout.separated,
              icon: Icons.view_column_outlined,
              title: '图文分隔',
              desc: '朋友圈、微博等',
            ),
          ],
        ),
      );
    }

    if (_isImageTextEditorEmpty && !_hasTappedImageTextPanel) {
      return _DashedBorder(
        color: cs.outlineVariant,
        radius: 18,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: panelRadius,
          ),
          padding: const EdgeInsets.all(12),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _hasTappedImageTextPanel = true;
                _showImageTextLayoutSelector = true;
              });
            },
            child: _buildCenteredAddButton(
              theme: theme,
              onPressed: () {
                setState(() {
                  _hasTappedImageTextPanel = true;
                  _showImageTextLayoutSelector = true;
                });
              },
              label: '添加图文',
            ),
          ),
        ),
      );
    }

    if (_showImageTextLayoutSelector) {
      return _DashedBorder(
        color: cs.outlineVariant,
        radius: 18,
        child: Material(
          color: cs.surface,
          borderRadius: panelRadius,
          clipBehavior: Clip.hardEdge,
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 260),
            child: buildLayoutSelector(),
          ),
        ),
      );
    }

    Widget editorBody;
    if (widget.imageTextLayout == ImageTextLayout.separated) {
      editorBody = Center(
        child: Text(
          '分割模式（开发中）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    } else if (widget.textFormat == TextFormat.markdown) {
      editorBody = Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: widget.markdownController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(border: InputBorder.none),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
              ),
            ),
          ),
          if (_isImageTextEditorEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      '在这里开始输入…\n支持 Markdown 纯文本',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      editorBody = Stack(
        children: [
          Positioned.fill(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                    widget.onPaste,
                const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                    widget.onPaste,
              },
              child: QuillEditor(
                controller: widget.quillController,
                focusNode: widget.focusNode,
                scrollController: _editorScroll,
                config: QuillEditorConfig(
                  embedBuilders: widget.embedBuilders,
                  scrollable: true,
                  autoFocus: false,
                  expands: true,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ),
          if (_isImageTextEditorEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      '在这里开始输入…\n支持粘贴、图片等',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return _DashedBorder(
      color: cs.outlineVariant,
      radius: 18,
      child: ClipRRect(
        borderRadius: panelRadius,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: panelRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('图文草稿', style: theme.textTheme.titleMedium),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showImageTextLayoutSelector = true),
                      icon: const Icon(Icons.view_quilt_outlined, size: 18),
                      label: const Text('排版'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '图文草稿暂不保存，离开页面后不会保留。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(height: 1),
              if (widget.showToolbar)
                QuillSimpleToolbar(
                  controller: widget.quillController,
                  config: QuillSimpleToolbarConfig(
                    color: cs.surface,
                    toolbarSize: 44,
                    multiRowsDisplay: false,
                    embedButtons: FlutterQuillEmbeds.toolbarButtons(),
                  ),
                ),
              Expanded(child: editorBody),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final editorHeight =
            (constraints.maxHeight - (widget.showScalePanel ? 232 : 0)).clamp(
              360.0,
              720.0,
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showScalePanel)
                SizedBox(
                  height: _isScaleEditMode ? 360 : 220,
                  child: _buildScalePanel(theme),
                ),
              if (widget.showScalePanel && widget.showImageTextPanel)
                const SizedBox(height: 24),
              if (widget.showImageTextPanel)
                SizedBox(
                  height: editorHeight,
                  child: _buildImageTextPanel(theme),
                ),
              if (!widget.showScalePanel && !widget.showImageTextPanel)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '在文档选项中开启刻度或图文面板，继续记录。',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScaleInstanceTile extends StatelessWidget {
  final String title;
  final ScaleInteractionMode interactionMode;
  final ScaleDataType dataType;
  final List<String> options;
  final String? unit;
  final String? value;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRemove;
  final Color textColor;
  final bool isEditing;

  const _ScaleInstanceTile({
    required this.title,
    required this.interactionMode,
    required this.dataType,
    required this.options,
    required this.unit,
    required this.value,
    required this.onChanged,
    required this.onRemove,
    required this.textColor,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isSelectionMode = interactionMode == ScaleInteractionMode.selection;
    final unitText = (unit ?? '').trim();
    final displayTitle = title.isEmpty ? '(未命名)' : title;

    if (!isEditing) {
      final displayValue = value?.isEmpty ?? true ? '未填写' : value!;
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            displayTitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            displayValue,
            style: theme.textTheme.titleLarge?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (unitText.isNotEmpty)
            Text(
              unitText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      );
    }

    final inputDecoration = InputDecoration(
      isDense: true,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      suffixText: unitText.isEmpty ? null : unitText,
      suffixStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    Widget inputWidget;
    if (isSelectionMode) {
      inputWidget = DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : null,
        decoration: inputDecoration,
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(growable: false),
        onChanged: options.isEmpty ? null : onChanged,
      );
    } else {
      inputWidget = TextFormField(
        initialValue: value,
        decoration: inputDecoration,
        keyboardType: dataType == ScaleDataType.number
            ? TextInputType.number
            : null,
        onChanged: (v) => onChanged(v.trim().isEmpty ? null : v.trim()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          displayTitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: inputWidget),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              tooltip: '移除刻度',
            ),
          ],
        ),
      ],
    );
  }
}

class _DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;

  const _DashedBorder({
    required this.child,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: const EdgeInsets.all(1), child: child),
    );
  }
}
