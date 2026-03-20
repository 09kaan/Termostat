import 'package:flutter/material.dart';
import '../models/schedule.dart'; // Assuming Schedule model is here

class ScheduleRow extends StatelessWidget {
  final Schedule schedule;
  final void Function(bool) onToggle;
  final VoidCallback onTap; // For navigating to edit details

  const ScheduleRow({
    Key? key,
    required this.schedule,
    required this.onToggle,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(schedule.name),
      subtitle: Text('${schedule.entries.length} entries'), // You can customize this subtitle
      trailing: Switch(
        value: schedule.isEnabled,
        onChanged: onToggle,
      ),
      onTap: onTap,
    );
  }
} 