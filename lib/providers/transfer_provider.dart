import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:local_send_app/models/peer.dart';
import 'package:local_send_app/providers/discovery_provider.dart'; // To inform about port
import 'package:local_send_app/providers/settings_provider.dart';
import 'package:path_provider/path_provider.dart'; // To find downloads folder
import 'package:path/path.dart' as p; // For path manipulation

class TransferProvider with ChangeNotifier {
  final SettingsProvider _settingsProvider;
  ServerSocket? _serverSocket;
  bool _isServerRunning = false;
  int _serverPort = 0; // Store the actual port the server is listening on

  // Reference to DiscoveryProvider to set the port
  // This should be passed in or retrieved via context if structure allows
  DiscoveryProvider? discoveryProvider; // NEEDS TO BE SET AFTER INIT

  // Simple transfer state representation
  final Map<String, double> _sendProgress = {}; // key: unique file ID, value: progress (0.0-1.0)
  final Map<String, double> _receiveProgress = {}; // key: unique file ID, value: progress (0.0-1.0)
  // Add states for pending incoming transfers, errors etc.

  bool get isServerRunning => _isServerRunning;
  int get serverPort => _serverPort;
  Map<String, double> get sendProgress => _sendProgress;
  Map<String, double> get receiveProgress => _receiveProgress;


  TransferProvider(this._settingsProvider);

  // Call this after providers are initialized in main.dart
  void setDiscoveryProvider(DiscoveryProvider dp) {
      discoveryProvider = dp;
      // Now that we have the discovery provider, start the server
      startServer();
  }


  Future<void> startServer() async {
    if (_isServerRunning) return;
    debugPrint("Starting TCP server...");
    try {
        // Bind to any IPv4 address on an OS-assigned port (0)
        // Or use the predefined discoveryPort if desired, ensure it matches DiscoveryProvider
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0); // Let OS pick port
      _isServerRunning = true;
      _serverPort = _serverSocket!.port; // Get the actual port

      // ****** CRITICAL STEP ********
      // Inform the DiscoveryProvider about the port it should advertise
      discoveryProvider?.setServerPort(_serverPort);
      // ****************************

      notifyListeners();
      debugPrint('TCP Server listening on port $_serverPort');

      _serverSocket!.listen(
        _handleConnection,
        onError: (error) {
          debugPrint('Server socket error: $error');
          stopServer();
        },
        onDone: () {
           debugPrint('Server socket closed.');
           _isServerRunning = false;
           notifyListeners();
        },
        cancelOnError: false, // Keep listening even if one connection fails
      );
    } catch (e) {
       debugPrint('Error starting TCP server: $e');
       _isServerRunning = false;
       _serverPort = 0;
       notifyListeners();
    }
  }

  void _handleConnection(Socket clientSocket) async {
    final clientAddress = clientSocket.remoteAddress.address;
    final clientPort = clientSocket.remotePort;
    debugPrint('Accepted connection from $clientAddress:$clientPort');

    // --- Simplified Receive Logic ---
    // TODO: Implement proper protocol negotiation:
    // 1. Read metadata (sender name, filename, filesize)
    // 2. Show confirmation dialog to the user (requires UI interaction!)
    // 3. If accepted, start reading file data
    // 4. If rejected, close socket gracefully.

    final downloadDir = await getDownloadsDirectory();
    if (downloadDir == null) {
        debugPrint("Error: Could not get downloads directory.");
        clientSocket.close();
        return;
    }
    final tempFilename = 'received_file_${DateTime.now().millisecondsSinceEpoch}';
    final filePath = p.join(downloadDir.path, tempFilename); // Use path package
    final file = File(filePath);
    final sink = file.openWrite();
    int totalBytesRead = 0;
    final receiveId = 'recv_${clientAddress}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await clientSocket.listen(
        (Uint8List data) {
          sink.add(data);
          totalBytesRead += data.length;
          // Simplified progress update - assumes total size is known later
          _receiveProgress[receiveId] = 0.5; // Placeholder
          notifyListeners();
          debugPrint('Received ${data.length} bytes ($totalBytesRead total)');
        },
        onError: (error) {
          debugPrint('Error receiving data from $clientAddress: $error');
          sink.close(); // Close sink on error
           _receiveProgress.remove(receiveId);
           notifyListeners();
          // Delete potentially incomplete file
          if (file.existsSync()) { file.delete(); }
        },
        onDone: () {
           debugPrint('Connection closed by $clientAddress. Total received: $totalBytesRead bytes.');
           sink.close().then((_) { // Ensure sink is closed before marking complete
                debugPrint('File successfully received: $filePath');
                // TODO: Rename file based on metadata received earlier
                _receiveProgress[receiveId] = 1.0; // Mark as complete
                notifyListeners();
                // Optionally remove from progress map after a delay
                Future.delayed(const Duration(seconds: 5), () {
                    _receiveProgress.remove(receiveId);
                    notifyListeners();
                });
           });
        },
        cancelOnError: true, // Stop listening for this socket on error
      ).asFuture(); // Convert listen stream to a future to await completion/error

    } catch(e) {
         debugPrint("Error during socket listening/writing: $e");
          _receiveProgress.remove(receiveId);
          notifyListeners();
         try { await sink.close(); } catch (_) {} // Attempt to close sink
          if (file.existsSync()) { file.delete(); } // Clean up temp file
          clientSocket.close(); // Ensure socket is closed
    }
    // Note: Explicit clientSocket.close() might not be needed if listen().asFuture() completes/errors
  }


  Future<void> sendFile(Peer recipient) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final file = File(filePath);
      final fileName = p.basename(filePath);
      final fileSize = await file.length();

      debugPrint("Attempting to send '$fileName' ($fileSize bytes) to ${recipient.name} at ${recipient.address.address}:${recipient.port}");

      final sendId = 'send_${recipient.id}_${DateTime.now().millisecondsSinceEpoch}';
      _sendProgress[sendId] = 0.0;
      notifyListeners();

      Socket? socket; // Define socket outside try block

      try {
         // Connect to the recipient
        socket = await Socket.connect(recipient.address, recipient.port, timeout: const Duration(seconds: 10));
         debugPrint('Connected to ${recipient.name} for sending.');

         // --- Simplified Send Logic ---
         // TODO: Implement proper protocol negotiation:
         // 1. Send metadata (device name, filename, filesize)
         // 2. Wait for confirmation from recipient (optional but recommended)
         // 3. Start streaming file data.

         int bytesSent = 0;
         final stream = file.openRead();

         await socket.addStream(stream.map((chunk) {
             bytesSent += chunk.length;
             double progress = (bytesSent / fileSize).clamp(0.0, 1.0);
              _sendProgress[sendId] = progress;
              // Throttle notifications slightly if needed
              // if (bytesSent % (1024 * 100) == 0 || progress == 1.0) { // Example: Update every 100KB or at end
                   notifyListeners();
              // }
              debugPrint('Sent ${chunk.length} bytes ($bytesSent/$fileSize) -> ${progress * 100}%');
             return chunk;
         }));

         await socket.flush(); // Ensure all data is sent
         await socket.close(); // Close the connection gracefully FROM THE SENDER SIDE
          debugPrint('File "$fileName" sent successfully.');
          _sendProgress[sendId] = 1.0; // Mark as complete
          notifyListeners();
          // Optionally remove from progress map after a delay
          Future.delayed(const Duration(seconds: 5), () {
              _sendProgress.remove(sendId);
              notifyListeners();
          });

      } catch (e) {
         debugPrint('Error sending file to ${recipient.name}: $e');
         _sendProgress.remove(sendId); // Remove on error
         notifyListeners();
         socket?.destroy(); // Force close socket on error
      }

    } else {
      // User canceled the picker
      debugPrint('File picking cancelled.');
    }
  }

  void stopServer() {
    debugPrint("Stopping TCP server...");
    _serverSocket?.close();
    _serverSocket = null;
    _isServerRunning = false;
    _serverPort = 0;
    // Also clear any ongoing transfer states if appropriate
    _sendProgress.clear();
    _receiveProgress.clear();
    notifyListeners();
    // Crucially, inform discovery to stop advertising or advertise port 0 (or handle accordingly)
     discoveryProvider?.setServerPort(0); // Indicate server is down
  }

  @override
  void dispose() {
    stopServer();
    super.dispose();
  }
}