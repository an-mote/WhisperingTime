import 'package:flutter/material.dart';
import 'package:whispering_time/util/env.dart';
import 'package:whispering_time/design/widgets.dart';

class FilterBottomSheet extends StatefulWidget {
  final int initialViewType;
  final int initialSortType;
  final List<bool> initialLevels;
  final Function(int, int, List<bool>) onChanged;

  const FilterBottomSheet({
    super.key,
    required this.initialViewType,
    required this.initialSortType,
    required this.initialLevels,
    required this.onChanged,
  });
  @override
  State<FilterBottomSheet> createState() => FilterBottomSheetState();
}

class FilterBottomSheetState extends State<FilterBottomSheet> {
  late int viewType;
  late int sortType;
  late List<bool> levels;
  @override
  void initState() {
    super.initState();
    viewType = widget.initialViewType;
    sortType = widget.initialSortType;
    levels = List.from(widget.initialLevels);
  }

  void _updateState(VoidCallback fn) {
    setState(fn);
    widget.onChanged(viewType, sortType, levels);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
          maxWidth: 640,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const ImprintSectionHeader(
                title: '筛选与排序',
                subtitle: '按自己的方式，回看生活的片段。',
              ),
              const SizedBox(height: 24),
              Text('视图', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.view_agenda_outlined, size: 18),
                    label: const Text('卡片'),
                    selected: viewType == 0,
                    onSelected: (selected) {
                      if (selected) _updateState(() => viewType = 0);
                    },
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: const Text('日历'),
                    selected: viewType == 1,
                    onSelected: (selected) {
                      if (selected) _updateState(() => viewType = 1);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('排序依据', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('创建时间'),
                    selected: sortType == 0,
                    onSelected: (selected) {
                      if (selected) _updateState(() => sortType = 0);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('更新时间'),
                    selected: sortType == 1,
                    onSelected: (selected) {
                      if (selected) _updateState(() => sortType = 1);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('分级筛选', style: theme.textTheme.titleSmall),
                  ),
                  TextButton(
                    onPressed: () => _updateState(
                      () => levels = List.filled(Level.l.length, true),
                    ),
                    child: const Text('全选'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  Level.l.length,
                  (index) => FilterChip(
                    label: Text(Level.l[index]),
                    selected: index < levels.length && levels[index],
                    onSelected: (selected) => _updateState(() {
                      while (levels.length < Level.l.length) {
                        levels.add(false);
                      }
                      levels[index] = selected;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
