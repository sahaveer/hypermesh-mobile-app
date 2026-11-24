import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/peer_node.dart';
import '../config/app_config.dart';

class LocalMeshDiscovery {
  static const int broadcastPort = 52525;
  final String deviceId;
  String deviceName;
  int serverPort;
  int musicCount;
  int videoCount;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;

  final Map<String, PeerNode> _peers = {};
  final Function(List<PeerNode> peers)? onPeersChanged;

  bool _isDiscovering = false;

  LocalMeshDiscovery({
    required this.deviceId,
    required this.deviceName,
    required this.serverPort,
    this.musicCount = 0,
    this.videoCount = 0,
    this.onPeersChanged,
  });

  bool get isDiscovering => _isDiscovering;
  List<PeerNode> get peers => _peers.values.toList();

  Future<bool> start() async {
    if (_isDiscovering) return true;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        broadcastPort,
        reuseAddress: true,
        reusePort: true,
      );

      _socket!.broadcastEnabled = true;
      _isDiscovering = true;

      // Listen for incoming peer beacons
      _socket!.listen(_handleDatagram, onError: (e) {
        debugPrint("LocalMeshDiscovery socket error: $e");
      });

      // Start periodic UDP broadcast beacon (every 3 seconds)
      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _sendBeacon();
      });

      // Start periodic dead-peer pruner (every 5 seconds)
      _pruneTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _pruneOfflinePeers();
      });

      // Send initial beacon immediately
      _sendBeacon();

      debugPrint("📡 LocalMeshDiscovery started on UDP port $broadcastPort");
      return true;
    } catch (e) {
      debugPrint("Failed to bind UDP discovery socket: $e");
      return false;
    }
  }

  void updateMediaCounts({required int music, required int video}) {
    musicCount = music;
    videoCount = video;
  }

  void _sendBeacon() {
    if (_socket == null || !_isDiscovering) return;

    try {
      final beacon = {
        'type': 'hypermesh_beacon',
        'id': deviceId,
        'name': deviceName,
        'port': serverPort,
        'music_count': musicCount,
        'video_count': videoCount,
        'app_version': AppConfig.appVersion,
        'build_number': AppConfig.buildNumber,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };

      final data = utf8.encode(json.encode(beacon));
      _socket!.send(data, InternetAddress("255.255.255.255"), broadcastPort);
    } catch (e) {
      debugPrint("Error sending UDP beacon: $e");
    }
  }

  void _handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) return;

    try {
      final datagram = _socket!.receive();
      if (datagram == null) return;

      final message = utf8.decode(datagram.data);
      final jsonMap = json.decode(message) as Map<String, dynamic>;

      if (jsonMap['type'] != 'hypermesh_beacon') return;

      final peerId = jsonMap['id']?.toString() ?? '';
      if (peerId.isEmpty || peerId == deviceId) return; // Ignore own beacons

      final peerName = jsonMap['name']?.toString() ?? 'Mobile Peer';
      final peerPort = (jsonMap['port'] is num) ? (jsonMap['port'] as num).toInt() : 8080;
      final peerMusic = (jsonMap['music_count'] is num) ? (jsonMap['music_count'] as num).toInt() : 0;
      final peerVideo = (jsonMap['video_count'] is num) ? (jsonMap['video_count'] as num).toInt() : 0;
      final peerAppVersion = jsonMap['app_version']?.toString() ?? '1.0.0';
      final peerBuildNumber = (jsonMap['build_number'] is num) ? (jsonMap['build_number'] as num).toInt() : 1;
      final peerIp = datagram.address.address;

      final updatedPeer = PeerNode(
        id: peerId,
        name: peerName,
        host: peerIp,
        port: peerPort,
        musicCount: peerMusic,
        videoCount: peerVideo,
        isOnline: true,
        lastSeen: DateTime.now(),
        appVersion: peerAppVersion,
        buildNumber: peerBuildNumber,
      );

      final isNew = !_peers.containsKey(peerId);
      _peers[peerId] = updatedPeer;

      if (isNew) {
        debugPrint("⚡ Discovered Mobile Peer: $peerName at http://$peerIp:$peerPort");
        onPeersChanged?.call(peers);
      }
    } catch (_) {}
  }

  void _pruneOfflinePeers() {
    final now = DateTime.now();
    bool changed = false;

    _peers.removeWhere((id, peer) {
      // If no beacon received for 10 seconds, remove peer
      if (now.difference(peer.lastSeen).inSeconds > 10) {
        debugPrint("Peer offline: ${peer.name} (${peer.host})");
        changed = true;
        return true;
      }
      return false;
    });

    if (changed) {
      onPeersChanged?.call(peers);
    }
  }

  /// Manually add peer by IP (for QR code scan or direct IP input)
  void addManualPeer(String host, int port, {String name = "Manual Peer"}) {
    final id = "manual_${host.replaceAll('.', '_')}_$port";
    _peers[id] = PeerNode(
      id: id,
      name: name,
      host: host,
      port: port,
      musicCount: 0,
      videoCount: 0,
      isOnline: true,
      lastSeen: DateTime.now(),
    );
    onPeersChanged?.call(peers);
  }

  Future<void> stop() async {
    _isDiscovering = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _peers.clear();
  }
}
