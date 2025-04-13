import 'dart:io';

class Peer {
  final String id; // Unique identifier (maybe based on service name)
  final String name;
  final InternetAddress address;
  final int port;
  DateTime lastSeen;

  Peer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.lastSeen,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Peer &&
          runtimeType == other.runtimeType &&
          id == other.id; // Compare based on a unique ID

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Peer{id: $id, name: $name, address: ${address.address}:$port, lastSeen: $lastSeen}';
  }
}