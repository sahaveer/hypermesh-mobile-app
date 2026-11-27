import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hypermesh_player/models/video_item.dart';
import 'package:hypermesh_player/services/api_service.dart';
import 'package:hypermesh_player/services/local_media_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('VideoItem builds HLS stream URL with quality and optional token', () {
    final v1 = VideoItem(
      id: 'vid123',
      title: 'Test Movie',
      duration: 120,
      ownerId: 'host',
      ownerName: 'Host',
      sourceNodeName: 'My Hub',
      sourceNodeHost: 'https://hub.example.ts.net/',
    );
    expect(
      v1.getHlsStreamUrl('http://localhost:8000', quality: '480p'),
      'https://hub.example.ts.net/api/hls/vid123/index.m3u8?quality=480p',
    );

    final v2 = VideoItem(
      id: 'vid456',
      title: 'Peer Clip',
      duration: 30,
      ownerId: 'peer1',
      ownerName: 'Peer',
      sourceNodeName: 'Peer',
      sourceNodeHost: 'http://192.168.1.50:8080',
      streamToken: 'tok+1',
    );
    expect(
      v2.getHlsStreamUrl('http://localhost:8000', quality: '720p'),
      'http://192.168.1.50:8080/api/hls/vid456/index.m3u8?quality=720p&t=tok%2B1',
    );
  });

  test('ApiService.checkExistingPhotoHashes posts hashes and returns existing set', () async {
    final mockClient = MockClient((req) async {
      expect(req.url.toString(), 'http://hub.local:8000/api/upload/photos/check');
      final body = json.decode(req.body) as Map<String, dynamic>;
      expect(body['hashes'], ['aaa', 'bbb']);
      return http.Response(json.encode({'existing': ['aaa'], 'missing': ['bbb']}), 200);
    });

    final api = ApiService(initialHost: 'http://hub.local:8000', httpClient: mockClient);
    final existing = await api.checkExistingPhotoHashes(['aaa', 'bbb']);
    expect(existing, {'aaa'});
  });

  test('ApiService.uploadFileChunked sends chunks in order and finalizes', () async {
    final tempDir = await Directory.systemTemp.createTemp('hypermesh_chunk_test');
    addTearDown(() => tempDir.delete(recursive: true));

    final file = File('${tempDir.path}/sample.bin');
    final payload = List<int>.generate(10, (i) => i + 1);
    await file.writeAsBytes(payload);
    final expectedSha = sha256.convert(payload).toString();

    final seenOffsets = <String>[];
    final mockClient = MockClient((req) async {
      if (req.url.path == '/api/upload/chunked/init') {
        final body = json.decode(req.body) as Map<String, dynamic>;
        expect(body['content_hash'], expectedSha);
        expect(body['total_size'], 10);
        return http.Response(
          json.encode({
            'status': 'created',
            'deduplicated': false,
            'upload_id': 'u-1',
            'chunk_size': 4,
            'next_offset': 0,
          }),
          200,
        );
      }
      if (req.url.path == '/api/upload/chunked/u-1' && req.method == 'PUT') {
        final offset = int.parse(req.url.queryParameters['offset']!);
        seenOffsets.add('$offset:${req.bodyBytes.length}');
        final next = offset + req.bodyBytes.length;
        return http.Response(json.encode({'next_offset': next, 'complete': next >= 10}), 200);
      }
      if (req.url.path == '/api/upload/chunked/u-1/complete') {
        return http.Response(json.encode({'status': 'ok', 'filename': 'sample.bin'}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final api = ApiService(initialHost: 'http://hub.local:8000', httpClient: mockClient);
    final res = await api.uploadFileChunked(file: file, chunkSize: 4);
    expect(res['ok'], true);
    expect(seenOffsets, ['0:4', '4:4', '8:2']);
  });

  test('ApiService.uploadFileChunked short-circuits on duplicate', () async {
    final tempDir = await Directory.systemTemp.createTemp('hypermesh_dup_test');
    addTearDown(() => tempDir.delete(recursive: true));

    final file = File('${tempDir.path}/dup.jpg');
    await file.writeAsBytes([1, 2, 3, 4]);

    final mockClient = MockClient((req) async {
      expect(req.url.path, '/api/upload/chunked/init');
      return http.Response(json.encode({'status': 'duplicate', 'deduplicated': true}), 200);
    });

    final api = ApiService(initialHost: 'http://hub.local:8000', httpClient: mockClient);
    final res = await api.uploadFileChunked(file: file);
    expect(res['ok'], true);
    expect(res['deduplicated'], true);
  });

  test('LocalMediaStore keeps folders private by default and supports folder tickbox & multi-select share', () async {
    SharedPreferences.setMockInitialValues({});
    final tempRoot = await Directory.systemTemp.createTemp('hypermesh_privacy_');
    addTearDown(() => tempRoot.delete(recursive: true));

    final dir = await Directory('${tempRoot.path}/MyMusic').create();
    await File('${dir.path}/song_a.mp3').writeAsBytes([1, 2, 3]);
    await File('${dir.path}/song_b.mp3').writeAsBytes([4, 5, 6]);

    final store = LocalMediaStore();
    await store.addAndScanFolder(dir.path);

    // Folder stays open in app for playback, but private from mesh by default
    expect(store.sharedSongs, hasLength(2));
    expect(store.meshSongs, isEmpty);
    expect(store.isFolderAutoShared(dir.path), isFalse);

    // Multi-select explicit share of just one file
    final firstId = store.sharedSongs.first.id;
    await store.setFilesSharedWithMesh([firstId], true);
    expect(store.meshSongs, hasLength(1));
    expect(store.meshSongs.first.id, firstId);

    // Ticking "share everything in folder" shares all existing + future rescanned files
    await store.setFolderAutoShare(dir.path, true);
    expect(store.isFolderAutoShared(dir.path), isTrue);
    expect(store.meshSongs, hasLength(2));

    await File('${dir.path}/song_c.mp3').writeAsBytes([7, 8, 9]);
    await store.rescanAllFolders();
    expect(store.sharedSongs, hasLength(3));
    expect(store.meshSongs, hasLength(3));

    // Unticking reverts folder files back to explicit/private mode
    await store.setFolderAutoShare(dir.path, false);
    expect(store.isFolderAutoShared(dir.path), isFalse);
    expect(store.meshSongs, isEmpty);
  });
}
