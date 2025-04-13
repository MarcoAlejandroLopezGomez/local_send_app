import 'package:flutter/material.dart';
import 'package:local_send_app/providers/settings_provider.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    // Initialize controller with the current name from the provider
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _nameController = TextEditingController(text: settingsProvider.deviceName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveName() {
    final newName = _nameController.text.trim();
    if (newName.isNotEmpty) {
       Provider.of<SettingsProvider>(context, listen: false).setDeviceName(newName);
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Device name saved! Discovery will restart.')),
       );
       // Optionally pop navigator after saving
       // Navigator.pop(context);
    } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device name cannot be empty.')),
        );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Device Name:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Enter device name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveName,
              child: const Text('Save Name'),
            ),
            const SizedBox(height: 8),
            Text(
              'This name will be shown to other devices on the network.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}