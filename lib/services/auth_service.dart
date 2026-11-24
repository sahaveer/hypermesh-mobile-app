import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Default URL - replace with your Google Apps Script Web App URL (or leave as-is for built-in Demo Mode)
  static const String defaultAppsScriptUrl =
      "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec";

  String appsScriptUrl;

  AuthService({String? customUrl})
      : appsScriptUrl = customUrl ?? defaultAppsScriptUrl;

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

  /// Sends OTP to user's email via Google Apps Script
  Future<Map<String, dynamic>> sendOtp(String email) async {
    try {
      if (appsScriptUrl.contains("YOUR_SCRIPT_ID")) {
        // Mock fallback for immediate offline preview before pasting real script URL
        await Future.delayed(const Duration(seconds: 1));
        return {
          "success": true,
          "message": "Demo mode: OTP is 123456 (or set your Apps Script URL)",
          "demo_code": "123456",
        };
      }

      final uri = Uri.parse(
          "$appsScriptUrl?action=send_otp&email=${Uri.encodeComponent(email)}");
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 302) {
        return json.decode(response.body);
      } else {
        return {"success": false, "message": "Server error: ${response.statusCode}"};
      }
    } catch (e) {
      return {"success": false, "message": "Failed to connect: $e"};
    }
  }

  /// Verifies OTP code via Google Apps Script
  Future<Map<String, dynamic>> verifyOtp(String email, String otp) async {
    try {
      if (appsScriptUrl.contains("YOUR_SCRIPT_ID")) {
        // Mock demo verification
        await Future.delayed(const Duration(milliseconds: 800));
        if (otp.trim() == "123456") {
          return {
            "success": true,
            "token": "demo_token_${DateTime.now().millisecondsSinceEpoch}",
            "email": email,
          };
        } else {
          return {
            "success": false,
            "message": "Demo mode: Use code 123456 to log in.",
          };
        }
      }

      final uri = Uri.parse(
          "$appsScriptUrl?action=verify_otp&email=${Uri.encodeComponent(email)}&otp=${Uri.encodeComponent(otp)}");
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 302) {
        return json.decode(response.body);
      } else {
        return {"success": false, "message": "Server error: ${response.statusCode}"};
      }
    } catch (e) {
      return {"success": false, "message": "Verification failed: $e"};
    }
  }
}
