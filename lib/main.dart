import 'package:flutter/material.dart';
import 'package:local_send_app/providers/discovery_provider.dart';
import 'package:local_send_app/providers/settings_provider.dart';
import 'package:local_send_app/providers/transfer_provider.dart';
import 'package:local_send_app/screens/home_screen.dart';
import 'package:provider/provider.dart';

void main() async {
  // Ensure widgets are initialized before accessing platform channels
  WidgetsFlutterBinding.ensureInitialized();

  // Load settings asynchronously before starting the app
  final settingsProvider = SettingsProvider();
  await settingsProvider.loadDeviceName(); // Load name initially

  // Initialize other providers that might depend on settings
  final discoveryProvider = DiscoveryProvider(settingsProvider);
  final transferProvider = TransferProvider(settingsProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: discoveryProvider),
        ChangeNotifierProvider.value(value: transferProvider),
        // Add other providers if needed
      ],
      child: const LocalSendApp(),
    ),
  );
}

class LocalSendApp extends StatelessWidget {
  const LocalSendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalSend',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}