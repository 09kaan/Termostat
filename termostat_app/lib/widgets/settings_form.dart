import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:termostat_app/providers/settings_provider.dart';

class SettingsForm extends StatefulWidget {
  const SettingsForm({super.key});

  @override
  _SettingsFormState createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SettingsProvider>(context);
    final hysteresisController =
        TextEditingController(text: provider.hysteresis.toString());
    final timeoutController =
        TextEditingController(text: provider.overrideTimeout.toString());

    return ListView(
      children: [
        TextField(
          controller: hysteresisController,
          decoration: const InputDecoration(labelText: 'Hysteresis (°C)'),
          keyboardType: TextInputType.number,
          onSubmitted: (val) =>
              provider.setHysteresis(double.tryParse(val) ?? 0.5),
        ),
        TextField(
          controller: timeoutController,
          decoration:
              const InputDecoration(labelText: 'Override Timeout (min)'),
          keyboardType: TextInputType.number,
          onSubmitted: (val) =>
              provider.setOverrideTimeout(int.tryParse(val) ?? 60),
        ),
      ],
    );
  }
}
