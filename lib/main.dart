import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'providers/hypermesh_provider.dart';
import 'providers/player_provider.dart';
import 'providers/auth_provider.dart';
import 'services/extension_patch_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  final apiService = ApiService();
  await apiService.init();
  final authService = AuthService();
  await authService.loadSavedScriptUrl();
  runApp(HypermeshApp(apiService: apiService, authService: authService));
}

class HypermeshApp extends StatelessWidget {
  final ApiService? apiService;
  final AuthService? authService;

  const HypermeshApp({
    super.key,
    this.apiService,
    this.authService,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveApiService = apiService ?? ApiService();
    final effectiveAuthService = authService ?? AuthService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authService: effectiveAuthService),
        ),
        ChangeNotifierProvider(
          create: (_) => HypermeshProvider(apiService: effectiveApiService),
        ),
        ChangeNotifierProvider(
          create: (_) => PlayerProvider(apiService: effectiveApiService),
        ),
        ChangeNotifierProvider(
          create: (_) => ExtensionPatchService(),
        ),
      ],
      child: MaterialApp(
        title: 'Hypermesh Player',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const HomeScreen(),
      ),
    );
  }
}
