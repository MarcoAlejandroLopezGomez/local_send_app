import 'package:flutter/material.dart';
import 'package:local_send_app/models/peer.dart';
import 'package:local_send_app/providers/discovery_provider.dart';
import 'package:local_send_app/providers/settings_provider.dart';
import 'package:local_send_app/providers/transfer_provider.dart';
import 'package:local_send_app/screens/settings_screen.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  @override
  void initState() {
    super.initState();
    // Make sure the TransferProvider can tell the DiscoveryProvider its port
    // Needs slight delay or post-frame callback as providers might not be fully ready instantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final transferProvider = Provider.of<TransferProvider>(context, listen: false);
      final discoveryProvider = Provider.of<DiscoveryProvider>(context, listen: false);
      transferProvider.setDiscoveryProvider(discoveryProvider); // Link providers

      // Start discovery only *after* server port is likely set
       // Or trigger discovery from within setDiscoveryProvider or setServerPort in DiscoveryProvider
      discoveryProvider.startDiscovery();
    });
  }

  @override
  void dispose() {
      // Stop discovery when the screen is disposed (or manage globally)
     Provider.of<DiscoveryProvider>(context, listen: false).stopDiscovery();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    // Use Consumers or context.watch to listen to specific providers
    final settings = context.watch<SettingsProvider>();
    final discovery = context.watch<DiscoveryProvider>();
    final transfer = context.watch<TransferProvider>(); // Watch for progress updates

    return Scaffold(
      appBar: AppBar(
        title: Text('LocalSend - ${settings.deviceName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          // Button to manually start/stop discovery (optional)
          IconButton(
              icon: Icon(discovery.isDiscovering ? Icons.stop_circle_outlined : Icons.radar),
              tooltip: discovery.isDiscovering ? 'Stop Discovery' : 'Start Discovery',
              onPressed: () {
                 final dp = Provider.of<DiscoveryProvider>(context, listen: false);
                  if (dp.isDiscovering) {
                      dp.stopDiscovery();
                  } else {
                      dp.startDiscovery();
                  }
              },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Network Guidance ---
             Card(
               child: Padding(
                 padding: const EdgeInsets.all(12.0),
                 child: Text(
                   'Instructions:\n1. Ensure one device has enabled its Mobile Hotspot (from OS Settings).\n2. Connect other devices to that Hotspot Wi-Fi.\n3. Open LocalSend on all devices.\n   Your Port: ${transfer.serverPort > 0 ? transfer.serverPort : "Starting..."}\n   Discovery: ${discovery.isDiscovering ? "Active" : "Stopped"}',
                   style: Theme.of(context).textTheme.bodySmall,
                 ),
               ),
             ),
            const SizedBox(height: 16),

            // --- Discovered Peers ---
            Text('Nearby Devices:', style: Theme.of(context).textTheme.titleLarge),
            if (discovery.peers.isEmpty && discovery.isDiscovering)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(child: Column(
                      children: [
                         CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text("Searching for devices..."),
                      ],
                    )),
                )
             else if (discovery.peers.isEmpty && !discovery.isDiscovering)
                const Padding(
                     padding: EdgeInsets.symmetric(vertical: 16.0),
                     child: Center(child: Text("Discovery stopped or failed.")),
                 )
             else
                Expanded(
                  child: ListView.builder(
                    itemCount: discovery.peers.length,
                    itemBuilder: (context, index) {
                      final peer = discovery.peers[index];
                      return ListTile(
                        leading: const Icon(Icons.devices),
                        title: Text(peer.name),
                        subtitle: Text('${peer.address.address}:${peer.port}'),
                        trailing: ElevatedButton(
                          child: const Text('Send File'),
                          onPressed: () {
                            // Use the TransferProvider to initiate sending
                             Provider.of<TransferProvider>(context, listen: false).sendFile(peer);
                          },
                        ),
                         // TODO: Maybe show an icon if a transfer is active with this peer
                      );
                    },
                  ),
                ),

             const SizedBox(height: 16),

             // --- Transfer Progress ---
            Text('Transfers:', style: Theme.of(context).textTheme.titleLarge),
            _buildProgressList(context, "Sending", transfer.sendProgress),
            _buildProgressList(context, "Receiving", transfer.receiveProgress),

             // TODO: Add section for incoming transfer requests needing confirmation
          ],
        ),
      ),
    );
  }

  Widget _buildProgressList(BuildContext context, String title, Map<String, double> progressMap) {
     if (progressMap.isEmpty) {
         // return const SizedBox.shrink(); // Or show placeholder
         return Padding(
             padding: const EdgeInsets.symmetric(vertical: 8.0),
             child: Text("$title: None active."),
         );
     }
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(title, style: Theme.of(context).textTheme.titleMedium),
             ...progressMap.entries.map((entry) {
                 return Padding(
                     padding: const EdgeInsets.symmetric(vertical: 4.0),
                     child: Row(
                         children: [
                             Expanded(child: Text(entry.key)), // Use better ID later
                             SizedBox(
                                 width: 100, // Fixed width for progress bar
                                 child: LinearProgressIndicator(value: entry.value),
                             ),
                             const SizedBox(width: 8),
                             Text('${(entry.value * 100).toStringAsFixed(1)}%'),
                         ],
                     ),
                 );
             }).toList(),
          ],
      );
  }
}