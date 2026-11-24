import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService authService;

  bool _isLoggedIn = false;
  String? _currentUserEmail;
  String? _authToken;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  AuthProvider({required this.authService}) {
    checkInitialLoginStatus();
  }

  bool get isLoggedIn => _isLoggedIn;
  String? get currentUserEmail => _currentUserEmail;
  String? get authToken => _authToken;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;

  Future<void> checkInitialLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await authService.loadSavedScriptUrl();

    final savedEmail = prefs.getString('auth_user_email');
    final savedToken = prefs.getString('auth_token');

    if (savedEmail != null && savedToken != null) {
      _isLoggedIn = true;
      _currentUserEmail = savedEmail;
      _authToken = savedToken;
      notifyListeners();
    }
  }

  Future<bool> sendOtp(String email) async {
    _isLoading = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    final result = await authService.sendOtp(email);
    _isLoading = false;

    if (result['success'] == true) {
      _infoMessage = result['message'] ?? "OTP sent to your email!";
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message'] ?? "Failed to send OTP.";
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyOtp(String email, String otp) async {
    _isLoading = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    final result = await authService.verifyOtp(email, otp);
    _isLoading = false;

    if (result['success'] == true) {
      _isLoggedIn = true;
      _currentUserEmail = email;
      _authToken = result['token'] ?? "token_${DateTime.now().millisecondsSinceEpoch}";

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_user_email', _currentUserEmail!);
      await prefs.setString('auth_token', _authToken!);

      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message'] ?? "Invalid OTP code.";
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_user_email');
    await prefs.remove('auth_token');

    _isLoggedIn = false;
    _currentUserEmail = null;
    _authToken = null;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }
}
