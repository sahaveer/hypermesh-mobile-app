import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hypermesh_player/providers/hypermesh_provider.dart';
import 'package:hypermesh_player/screens/videos_screen.dart';
import 'package:hypermesh_player/services/api_service.dart';
import 'package:hypermesh_player/services/extension_patch_service.dart';

void main() {
  group('Audio and Video Library Search', () {
    test('HypermeshProvider filters songs and videos independently', () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((req) async {
        if (req.url.path == '/api/songs') {
          return http.Response(
            json.encode({
              'songs': [
                {'id': 's1', 'title': 'Believer', 'artist': 'Imagine Dragons', 'album': 'Evolve', 'duration': 204},
                {'id': 's2', 'title': 'Ocean Eyes', 'artist': 'Billie Eilish', 'album': 'EP', 'duration': 200},
              ],
            }),
            200,
          );
        }
        if (req.url.path == '/api/videos') {
          return http.Response(
            json.encode({
              'videos': [
                {'id': 'v1', 'title': '777 Charlie', 'resolution': '1080p', 'duration': 300},
                {'id': 'v2', 'title': 'Interstellar Cut', 'resolution': '4K', 'duration': 420},
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final api = ApiService(initialHost: 'http://127.0.0.1:8000', httpClient: client);
      final provider = HypermeshProvider(apiService: api);
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await provider.refreshLibrary();

      expect(provider.filteredSongs.length, 2);
      expect(provider.filteredVideos.length, 2);

      // Audio search filters songs without affecting videos
      provider.setSearchQuery('Imagine');
      expect(provider.filteredSongs.map((s) => s.id).toList(), ['s1']);
      expect(provider.filteredVideos.length, 2);

      // Video search filters videos without affecting songs
      provider.setVideoSearchQuery('Interstellar');
      expect(provider.filteredVideos.map((v) => v.id).toList(), ['v2']);
      expect(provider.filteredSongs.map((s) => s.id).toList(), ['s1']);

      // Clearing video search restores all videos
      provider.setVideoSearchQuery('');
      expect(provider.filteredVideos.length, 2);
    });

    testWidgets('VideosScreen renders a search bar that filters available videos and clears cleanly', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((req) async {
        if (req.url.path == '/api/songs') {
          return http.Response(json.encode({'songs': []}), 200);
        }
        if (req.url.path == '/api/videos') {
          return http.Response(
            json.encode({
              'videos': [
                {'id': 'v1', 'title': '777 Charlie Movie', 'resolution': '1080p', 'duration': 300},
                {'id': 'v2', 'title': 'Nature 4K Showcase', 'resolution': '4K', 'duration': 180},
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final api = ApiService(initialHost: 'http://127.0.0.1:8000', httpClient: client);
      late HypermeshProvider provider;
      await tester.runAsync(() async {
        provider = HypermeshProvider(apiService: api);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await provider.refreshLibrary();
      });
      addTearDown(provider.dispose);
      final patchService = ExtensionPatchService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<HypermeshProvider>.value(value: provider),
            ChangeNotifierProvider<ExtensionPatchService>.value(value: patchService),
          ],
          child: const MaterialApp(
            home: Scaffold(body: VideosScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('777 Charlie Movie'), findsOneWidget);
      expect(find.text('Nature 4K Showcase'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Charlie');
      await tester.pump();

      expect(find.text('777 Charlie Movie'), findsOneWidget);
      expect(find.text('Nature 4K Showcase'), findsNothing);

      await tester.tap(find.byTooltip('Clear video search'));
      await tester.pump();

      expect(find.text('777 Charlie Movie'), findsOneWidget);
      expect(find.text('Nature 4K Showcase'), findsOneWidget);

      // Non-matching search offers Clear Search empty state
      await tester.enterText(find.byType(TextField), 'nonexistent-clip');
      await tester.pump();

      expect(find.text('No Matching Videos'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Clear Search'));
      await tester.pump();

      expect(find.text('777 Charlie Movie'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
