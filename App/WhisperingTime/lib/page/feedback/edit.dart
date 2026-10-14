import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whispering_time/design/widgets.dart';
import 'package:whispering_time/service/http/official.dart';
import 'package:whispering_time/util/device.dart';
import 'package:whispering_time/util/env.dart';
import 'package:whispering_time/util/ui.dart';

class Edit extends StatefulWidget {
  const Edit({super.key});

  @override
  State<Edit> createState() => _EditState();
}

class _EditState extends State<Edit> {
  final title = TextEditingController();
  final desc = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  final _descFocus = FocusNode();
  final List<String> images = [];
  FeedbackType feedbackType = FeedbackType.optFeature;
  bool isUploadDeviceInfo = true;
  bool isPublic = true;
  bool _isSubmitting = false;
  bool _isPickingImage = false;

  bool get _busy => _isSubmitting || _isPickingImage;

  @override
  void dispose() {
    title.dispose();
    desc.dispose();
    _titleFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('提交反馈')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('让枫迹更好用', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      '告诉我们遇到的问题，或分享你的建议。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ImprintPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          typeDropwown(),
                          const SizedBox(height: 24),
                          titleEdit(),
                          const SizedBox(height: 24),
                          descEdit(),
                          const SizedBox(height: 24),
                          Text('图片附件', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            '最多添加 3 张图片，点击图片可查看或删除。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          imageButton(),
                          const SizedBox(height: 24),
                          moreCheckbox(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    submitButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget titleEdit() {
    return TextFormField(
      controller: title,
      focusNode: _titleFocus,
      enabled: !_busy,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: '标题',
        helperText: '不超过 30 个字',
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return '标题不能为空';
        if (value.length > 30) return '标题不能超过30个字';
        return null;
      },
    );
  }

  Widget typeDropwown() {
    return DropdownButtonFormField<FeedbackType>(
      initialValue: feedbackType,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '反馈类型'),
      items: const [
        DropdownMenuItem(value: FeedbackType.optFeature, child: Text('优化功能')),
        DropdownMenuItem(value: FeedbackType.bug, child: Text('问题缺陷')),
        DropdownMenuItem(value: FeedbackType.newFeature, child: Text('新增功能')),
        DropdownMenuItem(value: FeedbackType.other, child: Text('其他')),
      ],
      onChanged: _busy
          ? null
          : (value) {
              if (value != null) setState(() => feedbackType = value);
            },
    );
  }

  Widget descEdit() {
    return TextFormField(
      controller: desc,
      focusNode: _descFocus,
      enabled: !_busy,
      minLines: 4,
      maxLines: 8,
      keyboardType: TextInputType.multiline,
      decoration: const InputDecoration(
        labelText: '详细描述',
        helperText: '请描述遇到的问题，或希望改进的地方。',
      ),
      validator: (value) => value == null || value.isEmpty ? '请添加描述' : null,
    );
  }

  Widget imageButton() {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(3, (index) {
        final hasImage = images.length > index;
        final label = hasImage
            ? '查看第 ${index + 1} 张图片'
            : '添加第 ${index + 1} 张图片';
        return Semantics(
          button: true,
          enabled: !_busy,
          label: label,
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Material(
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _busy
                    ? null
                    : () =>
                          hasImage ? screenImage(index) : getLocalimage(index),
                child: SizedBox.square(
                  dimension: 80,
                  child: ExcludeSemantics(
                    child: hasImage
                        ? Image.file(
                            File(images[index]),
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stackTrace) => Icon(
                              Icons.broken_image_outlined,
                              color: colors.onSurfaceVariant,
                            ),
                          )
                        : Icon(
                            Icons.add_photo_alternate_outlined,
                            color: colors.onSurfaceVariant,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Future<void> getLocalimage(int index) async {
    if (_busy || images.length >= 3) return;
    setState(() => _isPickingImage = true);
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted || image == null) return;
      setState(() => images.add(image.path));
    } catch (_) {
      if (mounted) showErrMsg(context, '图片未添加，请重试。');
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void screenImage(int index) {
    if (index >= images.length) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('图片附件'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.55,
          ),
          child: Image.file(
            File(images[index]),
            fit: BoxFit.contain,
            errorBuilder: (_, error, stackTrace) =>
                const Text('图片无法显示，请删除后重新添加。'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () {
              if (mounted && index < images.length) {
                setState(() => images.removeAt(index));
              }
              Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget moreCheckbox() {
    return Column(
      children: [
        CheckboxListTile(
          title: const Text('上传设备信息'),
          subtitle: const Text('帮助定位问题，可按需关闭。'),
          value: isUploadDeviceInfo,
          onChanged: _busy
              ? null
              : (value) => setState(() => isUploadDeviceInfo = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          title: const Text('公开'),
          value: isPublic,
          onChanged: _busy
              ? null
              : (value) => setState(() => isPublic = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget submitButton() {
    return FilledButton.icon(
      onPressed: _busy ? null : submit,
      icon: _isSubmitting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send_outlined, size: 20),
      label: Text(_isSubmitting ? '正在提交…' : '提交'),
    );
  }

  Future<void> submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (title.text.isEmpty || title.text.length > 30) {
        _titleFocus.requestFocus();
      } else {
        _descFocus.requestFocus();
      }
      return;
    }
    final req = RequestCreateFeedback(
      fbType: feedbackType,
      title: title.text,
      content: desc.text,
      isPublic: isPublic,
    );
    final attachDeviceInfo = isUploadDeviceInfo;
    final selectedImages = List<String>.of(images);
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      if (attachDeviceInfo) req.deviceFilePath = await Device().write();
      if (!mounted) return;
      if (selectedImages.isNotEmpty) req.images = selectedImages;
      final value = await Http().postFeedback(req);
      if (!mounted) return;
      if (value.isNotOK) {
        showErrMsg(context, '反馈提交失败，请重试。填写的内容已保留。');
        return;
      }
      showSuccessMsg(context, '提交成功');
    } catch (_) {
      if (mounted) {
        showErrMsg(context, '反馈提交失败，请重试。填写的内容已保留。');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
