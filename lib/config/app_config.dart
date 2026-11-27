class AppConfig {
  static const String appVersion = "1.0.4";
  static const int buildNumber = 5;

  /// Public repository link people can scan from the Settings "Share this app" QR.
  static const String shareAppUrl = "https://github.com/sahaveer/hypermesh-mobile-app";

  /// GitHub repo used for app updates. Must match a repo publishing GitHub
  /// Releases whose tag is "vX.Y.Z+N" (or "X.Y.Z+N") with an .apk asset.
  static const String githubReleaseRepo = "sahaveer/hypermesh-mobile-app";

  /// Public privacy policy document for store listings and in-app disclosure.
  static const String privacyPolicyUrl =
      "https://github.com/sahaveer/hypermesh-mobile-app/blob/main/PRIVACY_POLICY.md";
}
