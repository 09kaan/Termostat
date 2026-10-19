import 'package:flutter/material.dart';

/// One-tap local appearance preference. Device operations are not involved.
class AppearanceSelector extends StatefulWidget {
  const AppearanceSelector(
      {super.key, required this.value, required this.onChanged});
  final String value;
  final Future<void> Function(String) onChanged;
  @override
  State<AppearanceSelector> createState() => _AppearanceSelectorState();
}

class _AppearanceSelectorState extends State<AppearanceSelector> {
  bool _saving = false;
  Future<void> _select(String? value) async {
    if (value == null || value == widget.value || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onChanged(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tema kaydedilemedi. Tekrar dene.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(children: [
                Expanded(
                    child: Text('Görünüm',
                        style: Theme.of(context).textTheme.titleLarge)),
                if (_saving)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ])),
          RadioListTile<String>(
              key: const ValueKey('appearance-original'),
              value: 'original',
              groupValue: widget.value,
              onChanged: _saving ? null : _select,
              title: const Text('Orijinal'),
              subtitle: const Text('Eski mavi renkler ve gölgeli kartlar')),
          RadioListTile<String>(
              key: const ValueKey('appearance-warm'),
              value: 'warm_minimal',
              groupValue: widget.value,
              onChanged: _saving ? null : _select,
              title: const Text('Sıcak Minimal'),
              subtitle: const Text('Krem yüzeyler ve kiremit tonları')),
          const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Koyu mod iki görünümde de ayrıca kullanılabilir.')),
        ]),
      ));
}
