import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'package:whispering_time/page/doc/model.dart';
import 'package:whispering_time/page/doc/browser/image_utils.dart';

void showDocsBubble({
  required BuildContext context,
  required List<Doc> docs,
  required Function(Doc) onEdit,
  required Function(Doc) onSetting,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${docs.length} 篇印迹'),
      content: SizedBox(
        width: 480,
        height: math.min(
          MediaQuery.sizeOf(dialogContext).height * .5,
          math.max(
            104.0,
            docs.fold<double>(
              0,
              (height, doc) =>
                  height +
                  (doc.config.displayPriority == 2 &&
                              extractImages(doc.content).isNotEmpty
                          ? 168
                          : 112) *
                      MediaQuery.textScalerOf(dialogContext).scale(16) /
                      16,
            ),
          ),
        ),
        child: ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 16),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final images = extractImages(doc.content);
            String plain = '';
            try {
              final decoded = jsonDecode(doc.content);
              final rich = decoded is Map && decoded['rich'] is List
                  ? decoded['rich']
                  : decoded;
              if (rich is List &&
                  rich.any((op) => op is Map && op.containsKey('insert'))) {
                plain = Document.fromJson(rich).toPlainText().trim();
              } else if (rich is List) {
                plain = rich
                    .whereType<Map>()
                    .map(
                      (s) =>
                          '${s['title'] ?? '刻度'} · ${s['current_value'] ?? '未填写'}',
                    )
                    .join(' · ');
              }
            } catch (_) {
              plain = doc.content;
            }
            final title = doc.title.isEmpty
                ? (plain.isEmpty ? '未命名' : plain.split('\n').first)
                : doc.title;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${DateFormat('HH:mm').format(doc.createAt)}${plain.isEmpty ? '' : ' · $plain'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '印迹设置',
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      onSetting(doc);
                    },
                  ),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    onEdit(doc);
                  },
                ),
                if (doc.config.displayPriority == 2 && images.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text('查看图片（${images.length}）'),
                    onPressed: () => showDialog<void>(
                      context: dialogContext,
                      builder: (imageContext) => Dialog(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                tooltip: '关闭图片',
                                onPressed: () => Navigator.pop(imageContext),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(imageContext).height *
                                    .65,
                              ),
                              child: InteractiveViewer(
                                child: DocImage(imageSource: images.first),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

List<String> extractImages(String content) {
  try {
    final decoded = jsonDecode(content);
    final json = (decoded is Map && decoded['rich'] is List)
        ? decoded['rich']
        : decoded;
    if (json is List) {
      List<String> images = [];
      for (var op in json) {
        if (op is Map && op.containsKey('insert')) {
          if (op['insert'] is Map && op['insert'].containsKey('image')) {
            images.add(op['insert']['image']);
          }
        }
      }
      return images;
    }
  } catch (_) {
    // best effort: ignore invalid/legacy payload
  }
  return [];
}
