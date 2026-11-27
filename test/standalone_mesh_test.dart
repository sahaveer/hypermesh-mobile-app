import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hypermesh_player/services/local_media_store.dart';
import 'package:hypermesh_player/services/api_service.dart';
import 'package:hypermesh_player/services/local_mesh_server.dart';
import 'package:hypermesh_player/services/app_update_service.dart';
import 'package:hypermesh_player/config/app_config.dart';
import 'package:hypermesh_player/services/local_mesh_discovery.dart';
import 'package:hypermesh_player/providers/hypermesh_provider.dart';
import 'package:hypermesh_player/models/peer_node.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Standalone Mobile Mesh Unit Tests', () {
    test('LocalMediaStore title cleaning and resolution guessing', () {
      expect(LocalMediaStore.cleanTitle('Inception.2010.1080p.BluRay.x264.mp4'), 'Inception 2010 1080p BluRay x264');
      expect(LocalMediaStore.cleanTitle('Dune.Part.Two.2024.4K.mkv'), 'Dune Part Two 2024 4K');
      expect(LocalMediaStore.cleanTitle('Starboy_The_Weeknd.mp3'), 'Starboy The Weeknd');
    });

    test('PeerNode model parsing from beacon data', () {
      final jsonMap = {
        'id': 'phone_alex_123',
        'name': 'Alex (Cabin 14)',
        'host': '192.168.43.50',
        'port': 8080,
        'music_count': 15,
        'video_count': 3,
        'is_online': true,
      };

      final peer = PeerNode.fromJson(jsonMap);
      expect(peer.id, 'phone_alex_123');
      expect(peer.name, 'Alex (Cabin 14)');
      expect(peer.host, '192.168.43.50');
      expect(peer.port, 8080);
      expect(peer.musicCount, 15);
      expect(peer.videoCount, 3);
      expect(peer.baseUrl, 'http://192.168.43.50:8080');
    });

    test('LocalMeshServer HTTP endpoints responding properly', () async {
      final store = LocalMediaStore();
      final server = LocalMeshServer(
        mediaStore: store,
        deviceId: 'test_node_01',
        deviceName: 'Test Phone',
        presetToken: 'test-mesh-token-xyz',
      );

      final started = await server.start();
      expect(started, true);
      expect(server.isRunning, true);
      expect(server.meshToken.isNotEmpty, true);

      final token = server.meshToken;
      final client = http.Client();

      // /api/info stays public so a fresh scan can read the peer's name.
      final infoRes = await client.get(Uri.parse('${server.serverUrl}/api/info'));
      expect(infoRes.statusCode, 200);
      final infoJson = json.decode(infoRes.body);
      expect(infoJson['device_name'], 'Test Phone');
      expect(infoJson['is_online'], true);

      // Unauthenticated data endpoints must be rejected.
      final unauthSongs = await client.get(Uri.parse('${server.serverUrl}/api/songs'));
      expect(unauthSongs.statusCode, 401);

      // With the token header they succeed.
      final songsRes = await client.get(
        Uri.parse('${server.serverUrl}/api/songs'),
        headers: {'x-mesh-token': token},
      );
      expect(songsRes.statusCode, 200);
      final songsJson = json.decode(songsRes.body);
      expect(songsJson['songs'], isA<List>());

      // The ?t= query parameter also works (for media players that can't set headers).
      final videosRes = await client.get(
        Uri.parse('${server.serverUrl}/api/videos?t=${Uri.encodeQueryComponent(token)}'),
      );
      expect(videosRes.statusCode, 200);
      final videosJson = json.decode(videosRes.body);
      expect(videosJson['videos'], isA<List>());

      // APK version endpoint also gated.
      final unauthAppVer = await client.get(Uri.parse('${server.serverUrl}/api/app/version'));
      expect(unauthAppVer.statusCode, 401);
      final appVerRes = await client.get(
        Uri.parse('${server.serverUrl}/api/app/version'),
        headers: {'x-mesh-token': token},
      );
      expect(appVerRes.statusCode, 200);
      final appVerJson = json.decode(appVerRes.body);
      expect(appVerJson['version'], isNotNull);
      expect(appVerJson['build_number'], isNotNull);

      await server.stop();
      expect(server.isRunning, false);
      client.close();
    });

    test('AppUpdateService detects newer peer updates on local mesh', () {
      final peers = [
        PeerNode(
          id: 'peer-old',
          name: 'Old Peer',
          host: '192.168.1.10',
          appVersion: '1.0.0',
          buildNumber: 1,
        ),
        PeerNode(
          id: 'peer-new',
          name: 'Alex (New Node)',
          host: '192.168.1.50',
          appVersion: '9.9.9',
          buildNumber: AppConfig.buildNumber + 2,
        ),
      ];

      final update = AppUpdateService.checkPeerUpdates(peers);
      expect(update, isNotNull);
      expect(update!.version, '9.9.9');
      expect(update.buildNumber, AppConfig.buildNumber + 2);
      expect(update.isPeerUpdate, true);
      expect(update.sourceName, 'Alex (New Node)');
    });

    test('LocalMediaStore scans multiple folders and removes folder cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      final tempRoot = await Directory.systemTemp.createTemp('hypermesh_folders_');
      try {
        final musicDir = await Directory('${tempRoot.path}/Music').create();
        final moviesDir = await Directory('${tempRoot.path}/Movies/Sub').create(recursive: true);

        await File('${musicDir.path}/track1.mp3').writeAsBytes([1, 2, 3]);
        await File('${musicDir.path}/notes.txt').writeAsString('ignore');
        await File('${moviesDir.path}/clip.mp4').writeAsBytes([4, 5, 6]);

        final store = LocalMediaStore();
        final addedMusic = await store.addAndScanFolder(musicDir.path);
        final addedMovies = await store.addAndScanFolder('${tempRoot.path}/Movies');

        expect(addedMusic, hasLength(1));
        expect(addedMovies, hasLength(1));
        expect(store.sharedFolders, hasLength(2));
        expect(store.sharedSongs, hasLength(1));
        expect(store.sharedVideos, hasLength(1));
        expect(store.countFilesInFolder(musicDir.path), 1);

        // Rescanning same folder does not duplicate
        final dupScan = await store.addAndScanFolder(musicDir.path);
        expect(dupScan, isEmpty);
        expect(store.sharedSongs, hasLength(1));

        // Removing music folder leaves movies intact
        await store.removeFolder(musicDir.path);
        expect(store.sharedFolders, hasLength(1));
        expect(store.sharedSongs, isEmpty);
        expect(store.sharedVideos, hasLength(1));
      } finally {
        await tempRoot.delete(recursive: true);
      }
    });

    test('QR peer address parsing and manual peer retention', () {
      expect(HypermeshProvider.parsePeerAddress('http://192.168.43.1:8080'), ('192.168.43.1', 8080, null));
      expect(HypermeshProvider.parsePeerAddress('192.168.1.25:9000'), ('192.168.1.25', 9000, null));
      expect(HypermeshProvider.parsePeerAddress('192.168.1.25'), ('192.168.1.25', 8080, null));
      expect(
        HypermeshProvider.parsePeerAddress('{"host":"10.0.0.5","port":8081}'),
        ('10.0.0.5', 8081, null),
      );
      expect(
        HypermeshProvider.parsePeerAddress('{"host":"10.0.0.5","port":8081,"token":"abc123"}'),
        ('10.0.0.5', 8081, 'abc123'),
      );
      expect(HypermeshProvider.parsePeerAddress(''), isNull);

      final discovery = LocalMeshDiscovery(
        deviceId: 'self',
        deviceName: 'Self',
        serverPort: 8080,
      );
      discovery.addManualPeer('192.168.1.44', 8080, name: 'Friend Phone');
      expect(discovery.peers, hasLength(1));
      expect(discovery.peers.first.name, 'Friend Phone');
    });
  });

  test('Offline demo resolves playable asset entries without HTTP', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final api = ApiService(initialHost: 'http://demo.hub');
    await HttpOverrides.runZoned(() async {
      final peer = (await api.fetchDiscoveredPeers()).single;
      final songs = [...await api.fetchLocalSongs(), ...await api.fetchPeerSongs(peer)];
      final videos = [...await api.fetchLocalVideos(), ...await api.fetchPeerVideos(peer)];
      expect(songs, hasLength(2));
      expect(videos, hasLength(2));
      for (final asset in [
        ...songs.map((song) => song.demoAsset!),
        ...videos.map((video) => video.demoAsset!),
      ]) {
        final data = await rootBundle.load(asset);
        expect(data.lengthInBytes, greaterThan(8));
        expect(String.fromCharCodes(data.buffer.asUint8List(data.offsetInBytes + 4, 4)), 'ftyp');
      }
    }, createHttpClient: (_) => throw StateError('Demo attempted to use HTTP'));
  });
}
