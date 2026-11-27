import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hypermesh_player/providers/hypermesh_provider.dart';
import 'package:hypermesh_player/services/api_service.dart';
import 'package:hypermesh_player/widgets/server_downloader_dialog.dart';

void main() {
  group('Server Downloader API & UI', () {
    test('normalizes formats, qualities, and download URLs for MediaPlayer backend', () {
      expect(ApiService.normalizeDownloadFormat('mp3'), 'audio');
      expect(ApiService.normalizeDownloadFormat('audio'), 'audio');
      expect(ApiService.normalizeDownloadFormat('mp4'), 'video');
      expect(ApiService.normalizeDownloadFormat('video'), 'video');

      expect(ApiService.normalizeDownloadQuality('audio', '320'), 'best');
      expect(ApiService.normalizeDownloadQuality('video', '1080'), '1080p');
      expect(ApiService.normalizeDownloadQuality('video', '720p'), '720p');
      expect(ApiService.normalizeDownloadQuality('video', 'anything'), 'best');

      final api = ApiService(initialHost: 'http://192.168.1.50:8000/');
      expect(
        api.resolveDownloadFileUrl({'id': 'abc-123', 'download_url': '/api/downloads/abc-123/file'}),
        'http://192.168.1.50:8000/api/downloads/abc-123/file',
      );
      expect(
        api.resolveDownloadFileUrl({'id': 'abc 123'}),
        'http://192.168.1.50:8000/api/downloads/abc%20123/file',
      );
    });

    test('startServerDownload sends backend-compatible payload and surfaces errors', () async {
      Map<String, dynamic>? lastBody;
      final client = MockClient((req) async {
        if (req.url.path == '/api/downloads/status') {
          return http.Response(json.encode({'tasks': []}), 200);
        }
        if (req.url.path == '/api/download' && req.method == 'POST') {
          lastBody = json.decode(req.body) as Map<String, dynamic>;
          if ((lastBody!['url'] as String).contains('bad')) {
            return http.Response(json.encode({'detail': 'Invalid media link'}), 400);
          }
          return http.Response(
            json.encode({
              'task_id': 'task-1',
              'destination': lastBody!['destination'],
              'message': 'Download started in background',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(initialHost: 'http://127.0.0.1:8000', httpClient: client);
      expect(await api.checkDownloaderAvailable(), isTrue);

      final okRes = await api.startServerDownload(
        url: 'https://youtube.com/watch?v=dQw4w9WgXcQ',
        format: 'mp3',
        quality: '320',
        destination: 'client',
        clientId: 'phone-1',
        deviceName: 'Pixel',
      );
      expect(okRes['ok'], isTrue);
      expect(okRes['task_id'], 'task-1');
      expect(lastBody?['format'], 'audio');
      expect(lastBody?['quality'], 'best');
      expect(lastBody?['destination'], 'client');
      expect(lastBody?['client_id'], 'phone-1');

      final errRes = await api.startServerDownload(url: 'bad', format: 'video', quality: '1080');
      expect(errRes['ok'], isFalse);
      expect(errRes['error'], 'Invalid media link');

      final demoApi = ApiService(initialHost: 'http://demo.hub', httpClient: client);
      expect(await demoApi.checkDownloaderAvailable(), isFalse);
    });

    testWidgets('ServerDownloaderDialog lets user choose destination, format, and shows failed tasks', (tester) async {
      SharedPreferences.setMockInitialValues({});
      Map<String, dynamic>? postedBody;

      final client = MockClient((req) async {
        if (req.url.path == '/api/downloads/status') {
          return http.Response(
            json.encode({
              'tasks': [
                {
                  'id': 't-fail',
                  'title': 'Blocked Video',
                  'status': 'failed',
                  'progress': 0,
                  'destination': 'server',
                  'error': 'YouTube requires sign-in cookies.',
                },
              ],
            }),
            200,
          );
        }
        if (req.url.path == '/api/download' && req.method == 'POST') {
          postedBody = json.decode(req.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({'task_id': 't-2', 'destination': postedBody!['destination']}),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(initialHost: 'http://127.0.0.1:8000', httpClient: client);
      final provider = HypermeshProvider(apiService: api);

      await tester.pumpWidget(
        ChangeNotifierProvider<HypermeshProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: ServerDownloaderDialog()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Shows failed task error from server
      expect(find.text('Blocked Video'), findsOneWidget);
      expect(find.text('YouTube requires sign-in cookies.'), findsOneWidget);

      // Switch to Video -> 1080p -> Download to Phone
      await tester.tap(find.text('Video (MP4)'));
      await tester.pump();
      expect(find.text('1080p'), findsOneWidget);
      await tester.tap(find.text('1080p'));
      await tester.tap(find.text('Download to Phone').first);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'https://youtu.be/dQw4w9WgXcQ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download to Phone'));
      await tester.pump();
      await tester.pump();

      expect(postedBody?['format'], 'video');
      expect(postedBody?['quality'], '1080p');
      expect(postedBody?['destination'], 'client');

      // Dispose dialog timer cleanly
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ServerDownloaderDialog search shows server match without YouTube, or YouTube Download & Play when missing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      Map<String, dynamic>? lastDownloadBody;

      final client = MockClient((req) async {
        if (req.url.path == '/api/downloads/status') {
          return http.Response(json.encode({'tasks': []}), 200);
        }
        if (req.url.path == '/api/downloader/search') {
          final q = req.url.queryParameters['q'] ?? '';
          if (q.toLowerCase().contains('existing')) {
            return http.Response(
              json.encode({
                'query': q,
                'in_library': true,
                'local_matches': [
                  {
                    'id': 'srv-1',
                    'title': 'Existing Server Anthem',
                    'artist': 'Local Band',
                    'media_type': 'audio',
                    'duration': 185,
                  },
                ],
                'youtube_results': [],
              }),
              200,
            );
          }
          return http.Response(
            json.encode({
              'query': q,
              'in_library': false,
              'local_matches': [],
              'youtube_results': [
                {
                  'id': 'yt-99',
                  'title': 'Brand New Song Official',
                  'channel': 'MusicChannel',
                  'duration': 210,
                  'thumbnail': '',
                  'url': 'https://www.youtube.com/watch?v=yt-99',
                },
              ],
            }),
            200,
          );
        }
        if (req.url.path == '/api/download' && req.method == 'POST') {
          lastDownloadBody = json.decode(req.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({'task_id': 't-yt', 'destination': 'server'}),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(initialHost: 'http://127.0.0.1:8000', httpClient: client);
      final provider = HypermeshProvider(apiService: api);

      await tester.pumpWidget(
        ChangeNotifierProvider<HypermeshProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: ServerDownloaderDialog()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 1. Search song that IS on server -> points to server, no YouTube results
      await tester.enterText(find.byType(TextField), 'Existing Song');
      await tester.tap(find.byTooltip('Search Server & YouTube'));
      await tester.pumpAndSettle();

      expect(find.text('ALREADY ON SERVER (1)'), findsOneWidget);
      expect(find.text('Existing Server Anthem'), findsOneWidget);
      expect(find.text('Download & Play'), findsNothing);

      // 2. Search song NOT on server -> shows YouTube Download & Play
      await tester.enterText(find.byType(TextField), 'Brand New Song');
      await tester.tap(find.byTooltip('Search Server & YouTube'));
      await tester.pumpAndSettle();

      expect(find.text('YOUTUBE RESULTS (1)'), findsOneWidget);
      expect(find.text('Brand New Song Official'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download & Play'));
      await tester.pump();

      expect(lastDownloadBody?['url'], 'https://www.youtube.com/watch?v=yt-99');
      expect(lastDownloadBody?['destination'], 'server');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ServerDownloaderDialog treats plain words as search when Download is tapped and supports pause/resume/delete', (tester) async {
      SharedPreferences.setMockInitialValues({});
      var downloadCalled = false;
      var searchCalled = false;
      String? lastAction;
      final tasks = <Map<String, dynamic>>[
        {
          'id': 't-active',
          'title': 'Active Processing Movie',
          'status': 'processing',
          'progress': 100,
          'destination': 'server',
        },
        {
          'id': 't-paused',
          'title': 'Paused Track',
          'status': 'paused',
          'progress': 45,
          'destination': 'server',
        },
      ];

      final client = MockClient((req) async {
        if (req.url.path == '/api/downloads/status') {
          return http.Response(json.encode({'tasks': tasks}), 200);
        }
        if (req.url.path == '/api/downloader/search') {
          searchCalled = true;
          return http.Response(
            json.encode({
              'query': req.url.queryParameters['q'] ?? '',
              'in_library': false,
              'local_matches': [],
              'youtube_results': [],
            }),
            200,
          );
        }
        if (req.url.path == '/api/download' && req.method == 'POST') {
          downloadCalled = true;
          return http.Response(json.encode({'task_id': 't-x', 'destination': 'server'}), 200);
        }
        if (req.url.path == '/api/downloads/t-active/pause' && req.method == 'POST') {
          lastAction = 'pause';
          tasks[0]['status'] = 'paused';
          return http.Response(json.encode({'message': 'paused'}), 200);
        }
        if ((req.url.path == '/api/downloads/t-active/resume' || req.url.path == '/api/downloads/t-paused/resume') && req.method == 'POST') {
          lastAction = 'resume';
          final id = req.url.pathSegments[2];
          for (final t in tasks) {
            if (t['id'] == id) t['status'] = 'pending';
          }
          return http.Response(json.encode({'message': 'resumed'}), 200);
        }
        if (req.url.path == '/api/downloads/t-active' && req.method == 'DELETE') {
          lastAction = 'delete';
          tasks.removeWhere((t) => t['id'] == 't-active');
          return http.Response(json.encode({'message': 'deleted'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(initialHost: 'http://127.0.0.1:8000', httpClient: client);
      final provider = HypermeshProvider(apiService: api);

      await tester.pumpWidget(
        ChangeNotifierProvider<HypermeshProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: ServerDownloaderDialog()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Plain text + tapping Download button should search instead of downloading directly
      await tester.enterText(find.byType(TextField), 'charlie full movie');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Start Server Download'));
      await tester.pumpAndSettle();

      expect(searchCalled, isTrue);
      expect(downloadCalled, isFalse);

      // Pause active processing task
      await tester.tap(find.byTooltip('Pause download').first);
      await tester.pumpAndSettle();
      expect(lastAction, 'pause');

      // Resume paused task
      await tester.tap(find.byTooltip('Resume download').first);
      await tester.pumpAndSettle();
      expect(lastAction, 'resume');

      // Delete task while in queue
      await tester.tap(find.byTooltip('Delete download').first);
      await tester.pumpAndSettle();
      expect(lastAction, 'delete');
      expect(find.text('Active Processing Movie'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
