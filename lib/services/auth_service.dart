import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Default URL - override at build time via --dart-define=APPS_SCRIPT_URL=...
  // Leave as placeholder (YOUR_SCRIPT_ID) for a clean public build; the app
  // then tells the user to configure it from the login screen.
  static const String defaultAppsScriptUrl = String.fromEnvironment(
    'APPS_SCRIPT_URL',
    defaultValue: 'https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec',
  );

  // Apps Script /exec cold-starts can take 15+ seconds. Keep the timeout
  // generous or the first request fails with "Failed to connect" while the
  // user's script is spinning up, which matches the "no OTP arrives but the
  // second tap works" symptom.
  static const Duration _requestTimeout = Duration(seconds: 25);

  String appsScriptUrl;
  // Reusing one Client across requests lets the TLS connection and any
  // session cookie Apps Script sets on the first /exec hit carry over to
  // the follow-up call, so the script doesn't cold-start twice.
  final http.Client _client;

  AuthService({String? customUrl, http.Client? httpClient})
      : appsScriptUrl = customUrl ?? defaultAppsScriptUrl,
        _client = httpClient ?? http.Client();

  Future<void> updateScriptUrl(String url) async {
    appsScriptUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_script_url', appsScriptUrl);
  }

  Future<void> loadSavedScriptUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('auth_script_url');
    if (saved != null && saved.isNotEmpty) {
      appsScriptUrl = saved;
    }
  }

  bool get isConfigured =>
      appsScriptUrl.trim().isNotEmpty &&
      appsScriptUrl.startsWith('https://') &&
      !appsScriptUrl.contains('YOUR_SCRIPT_ID');

  Uri _buildUri(Map<String, String> params) {
    // Cache-buster defeats any intermediary caching that might make a
    // repeated action=send_otp look like a duplicate and silently drop it.
    final all = {
      ...params,
      '_cb': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    final base = Uri.parse(appsScriptUrl);
    return base.replace(queryParameters: {...base.queryParameters, ...all});
  }

  Future<Map<String, dynamic>> _getJsonWithRetry(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(uri).timeout(_requestTimeout);
        if (response.statusCode == 200 || response.statusCode == 302) {
          try {
            final decoded = json.decode(response.body);
            if (decoded is Map<String, dynamic>) return decoded;
            lastError = "Unexpected response shape";
          } catch (e) {
            lastError = "Invalid server response";
          }
        } else {
          lastError = "Server error: ${response.statusCode}";
        }
      } catch (e) {
        lastError = e;
      }
      if (attempt == 0) {
        // One retry with a brief gap: the first call often wakes a cold
        // Apps Script; the second call then runs the actual sendEmail.
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    }
    return {"success": false, "message": "Failed to reach auth server ($lastError)."};
  }

  /// Sends OTP to user's email via Google Apps Script
  Future<Map<String, dynamic>> sendOtp(String email) async {
    if (!isConfigured) {
      return {
        "success": false,
        "message": "Set your Google Apps Script URL first (tap the gear icon on the login screen).",
      };
    }
    final uri = _buildUri({'action': 'send_otp', 'email': email});
    final result = await _getJsonWithRetry(uri);
    // Apps Script may return 200 with {success:false}; propagate that
    // honestly instead of showing a green "OTP sent" when nothing was sent.
    if (result['success'] != true && result['message'] == null) {
      result['message'] = "Apps Script did not confirm the OTP was sent.";
    }
    return result;
  }

  /// Verifies OTP code via Google Apps Script
  Future<Map<String, dynamic>> verifyOtp(String email, String otp) async {
    if (!isConfigured) {
      return {
        "success": false,
        "message": "Set your Google Apps Script URL first.",
      };
    }
    final uri = _buildUri({
      'action': 'verify_otp',
      'email': email,
      'otp': otp,
    });
    return _getJsonWithRetry(uri);
  }
}
