import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:local_send_app/models/peer.dart'; // Ensure Peer class is defined correctly
import 'package:local_send_app/providers/settings_provider.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';

// IMPORTANT: Define the constants used for discovery
const String serviceType = '_localsend._tcp';
// const int discoveryPort = 50333; // Port is mainly for the TCP server now
const Duration peerTimeout = Duration(seconds: 35);

class DiscoveryProvider with ChangeNotifier {
  final SettingsProvider _settingsProvider;
  MDnsClient? _mdnsClient;
  Timer? _peerCleanupTimer;

  final Map<String, Peer> _peers = {};
  bool _isDiscovering = false;

  List<Peer> get peers => _peers.values.toList();
  bool get isDiscovering => _isDiscovering;

  int _serverPort = 0; // Port received from TransferProvider

  DiscoveryProvider(this._settingsProvider) {
    _settingsProvider.addListener(_handleSettingsChange);
  }

  // Called by TransferProvider when its server starts/stops or name changes
  void setServerPort(int port) {
     if (port >= 0 && port != _serverPort) {
       _serverPort = port;
       debugPrint('DiscoveryProvider: Server port awareness updated to $_serverPort');
       // Restart discovery if it was running and the port became valid > 0
       // Or if name changed requiring re-handling (handled by _handleSettingsChange)
       // Stopping discovery if port becomes 0 is handled in stopServer flow typically
        if (_isDiscovering && _serverPort > 0) {
            debugPrint("Server port changed while discovering, restarting discovery.");
            stopDiscovery();
             // Add small delay before restarting
            Future.delayed(const Duration(milliseconds: 100), startDiscovery);
        } else if (_serverPort == 0 && _isDiscovering) {
             debugPrint("Server port became 0, stopping discovery.");
             stopDiscovery(); // Stop if server goes down
        }
     }
  }

  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      debugPrint('DiscoveryProvider: Already discovering.');
      return;
    }
    // Removed check for _serverPort > 0 here, allow starting discovery listener
    // even if server isn't ready yet (won't advertise but can find others).

    if (!_settingsProvider.isLoaded) {
      await _settingsProvider.loadDeviceName();
    }

    _isDiscovering = true;
    notifyListeners();
    debugPrint('Starting mDNS discovery listener...');

    try {
      final factory = (dynamic host, int port, {bool? reuseAddress, bool? reusePort, int? ttl}) {
        return RawDatagramSocket.bind(host, port, reuseAddress: true, reusePort: false, ttl: 255);
      };

      _mdnsClient = MDnsClient(rawDatagramSocketFactory: factory);
      await _mdnsClient!.start();

      // --- *** FIX: Removed explicit advertise call *** ---
      // Advertising is now reliant on OS-level services or implicit behavior.
      // This app instance might not be properly discoverable by name/port via mDNS.
      debugPrint("NOTE: Explicit mDNS advertising call removed due to API issues.");
      debugPrint("This instance will listen but may not advertise itself correctly via mDNS.");
      // ----------------------------------------------------

      // Listen for other services
      _mdnsClient!.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(serviceType))
          .listen((PtrResourceRecord ptr) {
            debugPrint('Discovered potential peer service: ${ptr.domainName}');
            // Query for SRV and TXT records for the discovered service instance
            _mdnsClient!
                .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
                .listen((SrvResourceRecord srv) => _handleSrvRecord(srv, ptr.domainName));
            _mdnsClient!
                .lookup<TxtResourceRecord>(ResourceRecordQuery.text(ptr.domainName))
                .listen((TxtResourceRecord txt) => _handleTxtRecord(txt, ptr.domainName));

          }, onError: (dynamic error) {
               debugPrint("mDNS PtrResourceRecord lookup error: $error");
          }, onDone: () {
               debugPrint("mDNS PtrResourceRecord lookup stream closed.");
               // Consider if restart is needed or if this indicates stopDiscovery was called
          });

      _peerCleanupTimer?.cancel();
      _peerCleanupTimer = Timer.periodic(peerTimeout, (_) => _cleanupPeers());

    } catch (e) {
       debugPrint('Error starting mDNS client or initial lookup: $e');
       stopDiscovery();
    }
  }

  void _handleSrvRecord(SrvResourceRecord srv, String serviceName) {
    debugPrint('Received SRV record for $serviceName: ${srv.target}:${srv.port}');
    _mdnsClient!.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
        .where((record) => record.address.type == InternetAddressType.IPv4)
        .first
        .then((IPAddressResourceRecord ipRecord) {
          final address = ipRecord.address;
          debugPrint('Resolved ${srv.target} to IP: ${address.address}');
          final String peerId = serviceName;
          String initialDeviceName = serviceName.split('.$serviceType').first;
          initialDeviceName = initialDeviceName.replaceAll('_', '.');

          // Create a potential peer object (name might be updated by TXT)
          final potentialPeer = Peer(
              id: peerId,
              name: initialDeviceName,
              address: address,
              port: srv.port,
              lastSeen: DateTime.now(),
          );
          _updatePeer(potentialPeer); // Pass the *new* object

        }).catchError((e) {
             debugPrint("Error resolving IPAddressResourceRecord (IPv4) for ${srv.target}: $e");
        });
  }

  void _handleTxtRecord(TxtResourceRecord txt, String serviceName) {
    final String peerId = serviceName;
    final existingPeer = _peers[peerId];

    if (existingPeer != null) {
      // --- *** FIX: Use txt.text (String) and parse it *** ---
      try {
        final String allTextData = txt.text; // Get the single concatenated string
        debugPrint("Received TXT for $serviceName: '$allTextData'");

        // Manually parse the string to find our key "dn="
        // This assumes simple key=value format within the concatenated string.
        // It might be fragile if other TXT records exist without clear delimiters.
        String? customName;
        final searchKey = 'dn=';
        int keyIndex = allTextData.indexOf(searchKey);

        if (keyIndex != -1) {
           // Find the end of the value. Assume it ends at the end of the string,
           // or potentially before another implicit key starts (this logic is basic).
           // For simplicity, take everything after "dn=".
           customName = allTextData.substring(keyIndex + searchKey.length);
           // You might need more sophisticated parsing if multiple TXT entries exist
           // and are concatenated without clear separators by the package.
           // E.g., find the next potential key start or assume standard length limits.
        }


        if (customName != null && customName.isNotEmpty && existingPeer.name != customName) {
           debugPrint("Updating peer $peerId name to '$customName' from parsed TXT record.");
           // Create NEW Peer object for update
           final updatedPeer = Peer(
               id: existingPeer.id,
               name: customName, // New name from TXT
               address: existingPeer.address,
               port: existingPeer.port,
               lastSeen: DateTime.now(),
           );
           _updatePeer(updatedPeer);
        } else {
           // No name found in TXT or name hasn't changed, just update timestamp
           debugPrint("No new 'dn=' name found or name unchanged in TXT for $serviceName. Updating timestamp.");
           final updatedPeer = Peer(
               id: existingPeer.id,
               name: existingPeer.name, // Keep existing name
               address: existingPeer.address,
               port: existingPeer.port,
               lastSeen: DateTime.now(), // Update timestamp
           );
           _updatePeer(updatedPeer);
        }

      } catch (e) {
        debugPrint("Error processing TXT record text for $serviceName: $e");
        // Still update timestamp even if parsing failed
         final updatedPeer = Peer(
             id: existingPeer.id,
             name: existingPeer.name,
             address: existingPeer.address,
             port: existingPeer.port,
             lastSeen: DateTime.now(),
         );
         _updatePeer(updatedPeer);
      }
    } else {
      debugPrint("Received TXT record for unknown or resolving peer: $serviceName. Ignoring for now.");
    }
  }

  void _updatePeer(Peer newPeerData) {
    // Basic self-discovery check placeholder
    // if (isSelf(newPeerData.address)) return;

    final existingPeer = _peers[newPeerData.id];
    bool changed = false;

    if (existingPeer == null) {
      // Add new peer
      debugPrint("Adding new peer: ${newPeerData.name} (${newPeerData.address.address}:${newPeerData.port})");
      _peers[newPeerData.id] = newPeerData; // Add the new object
      changed = true;
    } else {
      // Update existing peer: check if data actually changed before replacing
      if (existingPeer.name != newPeerData.name ||
          existingPeer.address.address != newPeerData.address.address ||
          existingPeer.port != newPeerData.port ||
          // Always update if timestamp is significantly newer (or just replace)
          newPeerData.lastSeen.isAfter(existingPeer.lastSeen))
      {
        debugPrint("Updating existing peer data: ${newPeerData.name} (${newPeerData.address.address}:${newPeerData.port})");
        // --- *** FIX: Replace object in map instead of modifying *** ---
        _peers[newPeerData.id] = newPeerData;
        changed = true; // Data changed or timestamp updated
      }
      // If only timestamp changed and no other data, 'changed' remains false
      // if we don't compare timestamps, but replacing ensures latest timestamp.
      // Let's keep it simple: if we call _updatePeer, we replace.
      // The check above is mainly for logging detail.
      _peers[newPeerData.id] = newPeerData; // Ensure replacement happens
    }

    // Notify listeners only if a peer was added or its data potentially changed
    // (Replacing with identical data except timestamp might not need UI update,
    // but for simplicity, notify on any _updatePeer call resulting in map change).
    if (changed) {
       notifyListeners();
    }
  }


  void _cleanupPeers() {
    final now = DateTime.now();
    int initialCount = _peers.length;
    _peers.removeWhere((id, peer) {
      final remove = now.difference(peer.lastSeen) > peerTimeout;
      if (remove) {
        debugPrint("Removing stale peer: ${peer.name} (ID: $id), last seen ${peer.lastSeen}");
      }
      return remove;
    });

    if (_peers.length != initialCount) {
      notifyListeners(); // Notify if any peers were removed
    }
  }

  void stopDiscovery() {
    if (!_isDiscovering) return;

    debugPrint('Stopping mDNS discovery listener...');
    _peerCleanupTimer?.cancel();
    _peerCleanupTimer = null;

    try {
      _mdnsClient?.stop();
    } catch (e) {
      debugPrint("Error stopping MDnsClient: $e");
    }
    _mdnsClient = null;
    _peers.clear(); // Clear peers when stopping discovery
    _isDiscovering = false;
    notifyListeners(); // Notify UI that discovery stopped and peers cleared
    debugPrint('mDNS discovery listener stopped.');
  }

  void _handleSettingsChange() {
     // If discovery is active, restart it to potentially reflect name changes elsewhere
     // Note: Since we removed explicit advertising, restarting discovery might not
     // be strictly necessary just for a name change *unless* we implement a way
     // for peers to re-query TXT records or rely on new PTR announcements.
     // Keeping the restart for now as it ensures the provider uses the latest name internally.
     if (_isDiscovering) {
       debugPrint("Settings changed (e.g., device name), restarting discovery...");
       stopDiscovery();
       Future.delayed(const Duration(milliseconds: 100), startDiscovery);
     }
  }

  @override
  void dispose() {
    debugPrint("Disposing DiscoveryProvider...");
    stopDiscovery();
    _settingsProvider.removeListener(_handleSettingsChange);
    _peerCleanupTimer?.cancel();
    super.dispose();
  }
}