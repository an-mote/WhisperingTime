import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:whispering_time/page/doc/manager.dart';
import 'package:whispering_time/page/doc/model.dart';
import 'package:whispering_time/page/doc/browser/date_picker.dart';
import 'package:whispering_time/page/doc/browser/bubble.dart';

class DocCalendarView extends StatefulWidget {
  final DocsManager docsManager;
  final DateTime pickedDate;
  final Set<String> expandedRanges;
  final Map<String, GlobalKey> monthKeys;
  final Function(DateTime) onDatePicked;
  final Function(String) onGapExpanded;
  final Function(Doc) onEdit;
  final Function(Doc) onSetting;
  const DocCalendarView({
    super.key,
    required this.docsManager,
    required this.pickedDate,
    required this.expandedRanges,
    required this.monthKeys,
    required this.onDatePicked,
    required this.onGapExpanded,
    required this.onEdit,
    required this.onSetting,
  });
  @override
  State<DocCalendarView> createState() => _DocCalendarViewState();
}

class _DocCalendarViewState extends State<DocCalendarView> {
  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: _chooseDate,
          icon: const Icon(Icons.event_outlined),
          label: const Text('定位月份'),
        ),
      ),
      const SizedBox(height: 16),
    ];
    if (widget.docsManager.allFetchedDocs.isEmpty) {
      children.add(_buildMonth(widget.pickedDate));
    } else {
      DateTime minDate = widget.docsManager.allFetchedDocs.first.createAt;
      DateTime maxDate = minDate;
      for (final doc in widget.docsManager.allFetchedDocs) {
        if (doc.createAt.isBefore(minDate)) minDate = doc.createAt;
        if (doc.createAt.isAfter(maxDate)) maxDate = doc.createAt;
      }
      if (widget.pickedDate.isBefore(minDate)) minDate = widget.pickedDate;
      if (widget.pickedDate.isAfter(maxDate)) maxDate = widget.pickedDate;
      minDate = DateTime(minDate.year, minDate.month);
      maxDate = DateTime(maxDate.year, maxDate.month);
      final gaps = <DateTime>[];
      void flushGap() {
        if (gaps.isEmpty) return;
        final id =
            '${gaps.first.millisecondsSinceEpoch}-${gaps.last.millisecondsSinceEpoch}';
        if (widget.expandedRanges.contains(id)) {
          for (final date in gaps) {
            children.add(_buildMonth(date));
          }
        } else {
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextButton.icon(
                onPressed: () => widget.onGapExpanded(id),
                icon: const Icon(Icons.more_horiz),
                label: Text('展开 ${gaps.length} 个没有印迹的月份'),
              ),
            ),
          );
        }
        gaps.clear();
      }

      var current = minDate;
      while (!current.isAfter(maxDate)) {
        final hasDocs = widget.docsManager.allFetchedDocs.any(
          (doc) =>
              doc.createAt.year == current.year &&
              doc.createAt.month == current.month,
        );
        final picked =
            current.year == widget.pickedDate.year &&
            current.month == widget.pickedDate.month;
        if (hasDocs || picked) {
          flushGap();
          final key = widget.monthKeys.putIfAbsent(
            '${current.year}-${current.month}',
            () => GlobalKey(),
          );
          children.add(_buildMonth(current, key: key));
        } else {
          gaps.add(current);
        }
        current = DateTime(current.year, current.month + 1);
      }
      flushGap();
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < 600 ? 8 : 16,
              0,
              constraints.maxWidth < 600 ? 8 : 16,
              32,
            ),
            children: children,
          ),
        ),
      ),
    );
  }

  void _chooseDate() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: DocDatePickerDialog(
          docsManager: widget.docsManager,
          initialDate: widget.pickedDate,
          onConfirm: widget.onDatePicked,
        ),
      ),
    );
  }

  Widget _buildMonth(DateTime date, {Key? key}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = widget.docsManager.items
        .where(
          (doc) =>
              doc.createAt.year == date.year &&
              doc.createAt.month == date.month,
        )
        .length;
    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 24),
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: EdgeInsets.all(constraints.maxWidth < 600 ? 8 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    DateFormat('yyyy年 M月').format(date),
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    '$count 篇印迹',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(16) / 16;
                  final width = math.max(
                    constraints.maxWidth,
                    7.0 * math.max(48.0, 40.0 * textScale),
                  );
                  final calendar = SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        Row(
                          children: List.generate(
                            7,
                            (index) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Semantics(
                                  label:
                                      '星期${['一', '二', '三', '四', '五', '六', '日'][index]}',
                                  child: ExcludeSemantics(
                                    child: Text(
                                      [
                                        '一',
                                        '二',
                                        '三',
                                        '四',
                                        '五',
                                        '六',
                                        '日',
                                      ][index],
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildMonthGrid(date, math.max(64.0, 56 * textScale)),
                      ],
                    ),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (width > constraints.maxWidth)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '左右滚动查看完整日历',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: calendar,
                      ),
                    ],
                  );
                },
              ),
              if (count == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    '这个月还没有符合筛选的印迹。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthGrid(DateTime date, double cellHeight) {
    final days = DateTime(date.year, date.month + 1, 0).day;
    final weekday = DateTime(date.year, date.month, 1).weekday;
    final rows = ((days + weekday - 1) / 7).ceil();
    final today = DateTime.now();
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: cellHeight,
      ),
      itemCount: rows * 7,
      itemBuilder: (context, index) {
        final day = index - weekday + 2;
        if (day < 1 || day > days) return const SizedBox.shrink();
        final docs = widget.docsManager.items
            .where(
              (doc) =>
                  doc.createAt.year == date.year &&
                  doc.createAt.month == date.month &&
                  doc.createAt.day == day,
            )
            .toList();
        final isToday =
            today.year == date.year &&
            today.month == date.month &&
            today.day == day;
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(2),
          child: Semantics(
            label:
                '${date.year}年${date.month}月$day日${isToday ? '，今天' : ''}，${docs.length}篇印迹',
            child: Material(
              color: isToday
                  ? cs.primaryContainer
                  : docs.isNotEmpty
                  ? cs.surfaceContainerLow
                  : cs.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: docs.isEmpty
                    ? null
                    : () => showDocsBubble(
                        context: context,
                        docs: docs,
                        onEdit: widget.onEdit,
                        onSetting: widget.onSetting,
                      ),
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: isToday ? cs.onPrimaryContainer : cs.onSurface,
                          fontWeight: docs.isNotEmpty || isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      if (docs.isNotEmpty)
                        Text(
                          '${docs.length}篇',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: isToday
                                    ? cs.onPrimaryContainer
                                    : cs.primary,
                              ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
