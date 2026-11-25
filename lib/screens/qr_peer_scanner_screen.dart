import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';

class QrPeerScannerScreen extends StatefulWidget {
  const QrPeerScannerScreen({super.key});

  @override
  State<QrPeerScannerScreen> createState() => _QrPeerScannerScreenState();
}

class _QrPeerScannerScreenState extends State<QrPeerScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _manualController = TextEditingController();
  bool _isConnecting = false;
  bool _handledScan = false;
  String? _errorText;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _connectAddress(String raw) async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _errorText = null;
    });

    final hypermesh = context.read<HypermeshProvider>();
    final res = await hypermesh.connectPeerByQrOrUrl(raw);
    if (!mounted) return;

    setState(() => _isConnecting = false);

    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: AppTheme.emeraldAccent,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorText = res.message;
        _handledScan = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          "SCAN PEER QR",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, letterSpacing: 1.2),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    if (_handledScan || _isConnecting) return;
                    for (final barcode in capture.barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.trim().isNotEmpty) {
                        _handledScan = true;
                        _connectAddress(raw);
                        break;
                      }
                    }
                  },
                ),
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.cyanAccent, width: 2.5),
                  ),
                ),
                if (_isConnecting)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanAccent),
                        ),
                        SizedBox(width: 12),
                        Text("Connecting to peer...", style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Or enter peer address manually (same Wi-Fi or Hotspot):",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppTheme.surfaceLight,
                            hintText: "http://192.168.1.X:8080",
                            hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isConnecting ? null : () => _connectAddress(_manualController.text),
                        child: const Text("Connect", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(_errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
