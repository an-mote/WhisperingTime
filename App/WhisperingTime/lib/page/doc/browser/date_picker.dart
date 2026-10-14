import 'package:flutter/material.dart';
import 'package:whispering_time/page/doc/manager.dart';

class DocDatePickerDialog extends StatefulWidget {
  final DocsManager docsManager;
  final DateTime initialDate;
  final ValueChanged<DateTime> onConfirm;
  const DocDatePickerDialog({
    super.key,
    required this.docsManager,
    required this.initialDate,
    required this.onConfirm,
  });
  @override
  State<DocDatePickerDialog> createState() => DocDatePickerDialogState();
}

class DocDatePickerDialogState extends State<DocDatePickerDialog> {
  late int selectedYear;
  late int selectedMonth;
  late List<int> years;
  late List<int> months;
  @override
  void initState() {
    super.initState();
    years = widget.docsManager.getAvailableYears();
    if (years.isEmpty) years = [widget.initialDate.year];
    selectedYear = years.contains(widget.initialDate.year)
        ? widget.initialDate.year
        : years.first;
    selectedMonth = widget.initialDate.month;
    _updateMonths();
  }

  void _updateMonths() {
    months = widget.docsManager
        .getAvailableMonth(selectedYear)
        .map(int.parse)
        .toList();
    if (months.isEmpty) months = [widget.initialDate.month];
    if (!months.contains(selectedMonth)) selectedMonth = months.first;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('定位月份', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '选择一个月份，回看当时的印迹。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<int>(
              initialValue: selectedYear,
              decoration: const InputDecoration(labelText: '年份'),
              items: years
                  .map(
                    (year) =>
                        DropdownMenuItem(value: year, child: Text('$year 年')),
                  )
                  .toList(),
              onChanged: (year) {
                if (year != null) {
                  setState(() {
                    selectedYear = year;
                    _updateMonths();
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: ValueKey('$selectedYear-$selectedMonth'),
              initialValue: selectedMonth,
              decoration: const InputDecoration(labelText: '月份'),
              items: months
                  .map(
                    (month) =>
                        DropdownMenuItem(value: month, child: Text('$month 月')),
                  )
                  .toList(),
              onChanged: (month) {
                if (month != null) setState(() => selectedMonth = month);
              },
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    widget.onConfirm(DateTime(selectedYear, selectedMonth));
                    Navigator.pop(context);
                  },
                  child: const Text('查看月份'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
