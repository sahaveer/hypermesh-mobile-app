import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../providers/auth_provider.dart';
import '../services/extension_patch_service.dart';
import '../widgets/server_downloader_dialog.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';
import '../widgets/app_update_dialog.dart';
import 'login_screen.dart';

class HubConnectScreen extends StatefulWidget {
  const HubConnectScreen({super.key});

  @override
  State<HubConnectScreen> createState() => _HubConnectScreenState();
}

class _HubConnectScreenState extends State<HubConnectScreen> {
  late TextEditingController _hostController;
  bool _isTesting = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    final hypermesh = context.read<HypermeshProvider>();
    _hostController = TextEditingController(text: hypermesh.apiService.hostUrl);
    hypermesh.apiService.init().then((_) {
      if (mounted) {
        setState(() {
          if (!mounted) return;
    _hostController.text = hypermesh.apiService.hostUrl;
        });
      }
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  void _applyAndTestHost(String host) async {
    setState(() {
      _isTesting = true;
      _statusMessage = null;
    });

    final hypermesh = context.read<HypermeshProvider>();
    await hypermesh.apiService.updateHost(host);
    _hostController.text = hypermesh.apiService.hostUrl;
    await hypermesh.refreshLibrary();

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _isSuccess = true;
      _statusMessage = hypermesh.apiService.isDemo
          ? "Offline demo loaded"
          : "Saved hub address ${hypermesh.apiService.hostUrl}";
    });
  }

  void _handleCheckUpdates() async {
    final hypermesh = context.read<HypermeshProvider>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Checking for updates from peers & server..."),
        duration: Duration(seconds: 1),
      ),
    );
    final update = await hypermesh.checkForUpdates();
    if (!mounted) return;
    if (update != null) {
      AppUpdateDialog.show(context, update);
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Hypermesh is up to date!"),
          backgroundColor: AppTheme.emeraldAccent,
        ),
      );
    }
  }

  void _showAdminLoginDialog() {
    final controller = TextEditingController();
    bool isVerifying = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.border),
          ),
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: AppTheme.cyanAccent, size: 22),
              SizedBox(width: 10),
              Text("Server Admin Login", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Enter your server administrator password to unlock permanent media deletion rights.",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: "Admin Password / Token",
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.key, color: AppTheme.cyanAccent, size: 18),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyanAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isVerifying
                  ? null
                  : () async {
                      final pass = controller.text.trim();
                      if (pass.isEmpty) return;
                      setDialogState(() {
                        isVerifying = true;
                        errorText = null;
                      });

                      final hypermesh = context.read<HypermeshProvider>();
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await hypermesh.verifyAdminPassword(pass);
                      if (!mounted) return;
                      if (ok) {
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text("Authenticated as Server Admin! Full deletion rights unlocked."),
                            backgroundColor: AppTheme.emeraldAccent,
                          ),
                        );
                      } else {
                        setDialogState(() {
                          isVerifying = false;
                          errorText = "Incorrect password or server unreachable.";
                        });
                      }
                    },
              child: Text(isVerifying ? "Verifying..." : "Login as Admin"),
            ),
          ],
        ),
      ),
    );
  }

  void _showScriptUrlDialog() {
    final auth = context.read<AuthProvider>();
    final controller = TextEditingController(text: auth.authService.appsScriptUrl);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Google Apps Script URL", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Update your Google Apps Script Web App endpoint:",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceLight,
                hintText: "https://script.google.com/macros/s/.../exec",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cyanAccent, foregroundColor: Colors.black),
            onPressed: () async {
              await auth.authService.updateScriptUrl(controller.text);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text("Save URL"),
          ),
        ],
      ),
    );
  }

  void _showLoadPatchDialog(BuildContext context, ExtensionPatchService patchService) {
    final controller = TextEditingController(text: patchService.patchSourceUrl);
    bool isFetching = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.cyanAccent),
          ),
          title: const Row(
            children: [
              Icon(Icons.extension, color: AppTheme.cyanAccent),
              SizedBox(width: 10),
              Text("Load GitHub Patch", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Enter a public GitHub raw URL or Gist manifest to unlock server-side yt-dlp downloading for your personal media server:",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: "https://raw.githubusercontent.com/.../patch.json",
                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  prefixIcon: const Icon(Icons.link, color: AppTheme.cyanAccent, size: 18),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyanAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isFetching
                  ? null
                  : () async {
                      setDialogState(() {
                        isFetching = true;
                        errorText = null;
                      });

                      final success = await patchService.fetchAndApplyPatch(controller.text);
                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? "Patch applied! Web Media Importer is now active." : "Failed to load patch."),
                            backgroundColor: success ? AppTheme.emeraldAccent : Colors.redAccent,
                          ),
                        );
                      }
                    },
              child: Text(isFetching ? "Loading..." : "Apply Patch"),
            ),
          ],
        ),
      ),
    );
  }

  void _showSelfHostGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.hub, color: AppTheme.cyanAccent, size: 24),
            SizedBox(width: 10),
            Text("Host Your Own Hub", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Transform your PC, Linux home server, or Raspberry Pi into a dedicated personal media cloud:",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              _buildGuideStep(
                step: "1",
                title: "Clone Server from GitHub",
                desc: "git clone https://github.com/sahaveer/hypermesh-media-hub.git\ncd hypermesh-media-hub && pip install -r requirements.txt\npython run_server.py",
              ),
              const SizedBox(height: 12),
              _buildGuideStep(
                step: "2",
                title: "Zero-Config Mesh with Tailscale",
                desc: "Install Tailscale on your server and phone. Your server gets a private 100.x.y.z IP accessible anywhere in the world without port forwarding.",
              ),
              const SizedBox(height: 12),
              _buildGuideStep(
                step: "3",
                title: "Connect & Ingest Media",
                desc: "Enter your server URL (e.g. http://100.x.y.z:8000) above. You can queue downloads directly on your server and stream anywhere!",
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyanAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Got It", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Widget _buildGuideStep({required String step, required String title, required String desc}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: AppTheme.cyanAccent,
                child: Text(step, style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final hypermesh = context.watch<HypermeshProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          "HUB SETTINGS",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Account / Profile Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.purpleAccent.withOpacity(0.12),
                  AppTheme.cyanAccent.withOpacity(0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.cyanAccent.withOpacity(0.2),
                  child: Icon(
                    auth.isLoggedIn ? Icons.person : Icons.person_outline,
                    color: AppTheme.cyanAccent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.isLoggedIn ? "LOGGED IN AS" : "PLAYER MODE",
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        auth.isLoggedIn
                            ? (auth.currentUserEmail ?? "demo@hypermesh.io")
                            : "Offline / Local Player",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (auth.isLoggedIn)
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
                    tooltip: "Log Out",
                    onPressed: () => auth.logout(),
                  )
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    child: const Text("Sign In", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Connection Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dns, color: AppTheme.cyanAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Media Hub Server URL",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "Enter the local IP (e.g. http://192.168.1.10:8000) or Cloudflare Tunnel HTTPS address.",
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _hostController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.surfaceLight,
                    hintText: "http://192.168.1.X:8000",
                    hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cyanAccent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyanAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: _isTesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.check_circle, size: 20),
                    label: Text(
                      _isTesting ? "Connecting..." : "Save & Connect",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isTesting ? null : () => _applyAndTestHost(_hostController.text),
                  ),
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isSuccess ? AppTheme.emeraldAccent.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isSuccess ? AppTheme.emeraldAccent : Colors.red,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isSuccess ? Icons.check : Icons.error_outline,
                          size: 18,
                          color: _isSuccess ? AppTheme.emeraldAccent : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _isSuccess ? AppTheme.emeraldAccent : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Self-Hosted Server Guide Card
          _PresetTile(
            title: "Host Your Own Server (GitHub & Tailscale)",
            subtitle: "Turn your PC or Raspberry Pi into a cloud hub • Tap for guide",
            icon: Icons.hub,
            onTap: _showSelfHostGuideDialog,
          ),
          const SizedBox(height: 16),

          // Google Apps Script Auth Config Card
          _PresetTile(
            title: "Configure Apps Script Endpoint",
            subtitle: auth.authService.appsScriptUrl.contains("YOUR_SCRIPT_ID")
                ? "Demo Mode Active • Tap to set Script URL"
                : "Active Web App Endpoint",
            icon: Icons.code,
            onTap: _showScriptUrlDialog,
          ),
          const SizedBox(height: 16),

          // Mesh Privacy & Hidden Items
          const Text(
            "MESH PRIVACY & FILTERS",
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Consumer<HypermeshProvider>(
            builder: (context, hypermesh, _) {
              return _PresetTile(
                title: "Restore Hidden Items",
                subtitle: hypermesh.hiddenCount > 0
                    ? "${hypermesh.hiddenCount} peer tracks/videos hidden with 'Remove for Me'"
                    : "No items currently hidden",
                icon: Icons.visibility,
                onTap: hypermesh.hiddenCount > 0
                    ? () async {
                        await hypermesh.restoreHiddenItems();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Restored all hidden peer items!"),
                              backgroundColor: AppTheme.cyanAccent,
                            ),
                          );
                        }
                      }
                    : () {},
              );
            },
          ),
          const SizedBox(height: 16),

          // Quick Presets
          const Text(
            "QUICK CONNECTION PRESETS",
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _PresetTile(
            title: "Localhost (PC / Desktop)",
            subtitle: "http://localhost:8000",
            icon: Icons.computer,
            onTap: () {
              _hostController.text = "http://localhost:8000";
              _applyAndTestHost("http://localhost:8000");
            },
          ),
          const SizedBox(height: 8),
          _PresetTile(
            title: "Android Emulator Gateway",
            subtitle: "http://10.0.2.2:8000",
            icon: Icons.phone_android,
            onTap: () {
              _hostController.text = "http://10.0.2.2:8000";
              _applyAndTestHost("http://10.0.2.2:8000");
            },
          ),
          const SizedBox(height: 8),
          _PresetTile(
            title: "Instant Demo Mesh (Offline)",
            subtitle: "Loads demo hypermesh without server",
            icon: Icons.auto_awesome,
            onTap: () {
              _applyAndTestHost("http://demo.hub");
            },
          ),
          const SizedBox(height: 24),
          const Text(
            "APP UPDATES & VERSION",
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _PresetTile(
            title: "Check for Updates",
            subtitle: "Current: v${AppConfig.appVersion} (Build ${AppConfig.buildNumber})",
            icon: Icons.system_update_alt,
            onTap: _handleCheckUpdates,
          ),
          const SizedBox(height: 24),
          const Text(
            "SERVER ADMIN & CONTENT MODERATION",
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hypermesh.isAdmin ? Colors.redAccent.withOpacity(0.5) : AppTheme.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hypermesh.isAdmin ? Icons.admin_panel_settings : Icons.lock_outline,
                      color: hypermesh.isAdmin ? Colors.redAccent : AppTheme.purpleAccent,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hypermesh.isAdmin ? "Server Admin Active" : "Server Admin Rights",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            hypermesh.isAdmin
                                ? "Full rights to delete unwanted media from the server database & disk for all users."
                                : "Authenticate to permanently remove inappropriate or unwanted media from the central server.",
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (hypermesh.isAdmin)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        await hypermesh.logoutAdmin();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Logged out of Server Admin mode.")),
                          );
                        }
                      },
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text("Exit Admin Mode"),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.purpleAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _showAdminLoginDialog,
                      icon: const Icon(Icons.key, size: 18),
                      label: const Text("Enter Server Admin Password"),
                    ),
                  ),
              ],
            ),
          ),
          if (hypermesh.hiddenCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_off, color: AppTheme.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "${hypermesh.hiddenCount} item(s) hidden from your list",
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await hypermesh.restoreHiddenItems();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("All hidden songs & videos restored to your list!")),
                        );
                      }
                    },
                    child: const Text("Restore All", style: TextStyle(color: AppTheme.cyanAccent)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            "COMMUNITY EXTENSIONS & GITHUB PATCHES",
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Consumer2<ExtensionPatchService, HypermeshProvider>(
            builder: (context, patchService, hypermesh, _) {
              final isPatchActive = patchService.isPatchActive;
              final serverAvailable = hypermesh.serverDownloaderAvailable;
              final isEnabled = isPatchActive || serverAvailable;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isEnabled ? AppTheme.cyanAccent.withOpacity(0.5) : AppTheme.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isEnabled ? Icons.extension : Icons.extension_outlined,
                          color: isEnabled ? AppTheme.cyanAccent : AppTheme.textSecondary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPatchActive
                                    ? (patchService.activePatch?.name ?? "Web Media Importer Patch")
                                    : serverAvailable
                                        ? "Server Web Media Importer"
                                        : "External Feature Patches",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                isPatchActive
                                    ? "Active v${patchService.activePatch?.version} - Server yt-dlp bridge enabled"
                                    : serverAvailable
                                        ? "Detected on connected personal server - yt-dlp bridge ready"
                                        : "Connect to your own MediaPlayer server or load a public GitHub patch URL to enable downloading.",
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (isEnabled) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.cyanAccent,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => ServerDownloaderDialog.show(context),
                              icon: const Icon(Icons.cloud_download, size: 18),
                              label: const Text("Open Downloader"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (isPatchActive)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () async {
                                await patchService.removePatch();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Extension patch removed.")),
                                  );
                                }
                              },
                              child: const Text("Remove"),
                            )
                          else
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.cyanAccent,
                                side: const BorderSide(color: AppTheme.cyanAccent),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => _showLoadPatchDialog(context, patchService),
                              child: const Text("GitHub Patch"),
                            ),
                        ],
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.cyanAccent,
                            side: const BorderSide(color: AppTheme.cyanAccent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _showLoadPatchDialog(context, patchService),
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text("Load Patch from GitHub"),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _PresetTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.cyanAccent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
