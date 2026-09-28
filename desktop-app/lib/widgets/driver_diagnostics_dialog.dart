import 'package:flutter/material.dart';
import '../services/printer_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class DriverDiagnosticsDialog extends StatefulWidget {
  const DriverDiagnosticsDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => const DriverDiagnosticsDialog(),
    );
  }

  @override
  State<DriverDiagnosticsDialog> createState() => _DriverDiagnosticsDialogState();
}

class _DriverDiagnosticsDialogState extends State<DriverDiagnosticsDialog> {
  PrinterDiagnostics? _diagnostics;
  String _printerName = '';
  String _globalQuality = '';
  int _globalDpi = 300;
  bool _loading = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() => _loading = true);
    final printerName = await StorageService.getPrinterName();
    final quality = await StorageService.getGlobalQuality();
    final dpi = await StorageService.getGlobalDpi();

    final diag = await PrinterService.getDriverDiagnostics(printerName);

    if (mounted) {
      setState(() {
        _printerName = printerName;
        _globalQuality = quality;
        _globalDpi = dpi;
        _diagnostics = diag;
        _loading = false;
      });
    }
  }

  Future<void> _forceApplyDraft() async {
    setState(() => _applying = true);
    try {
      await StorageService.setGlobalQuality('DRAFT');
      await StorageService.setGlobalDpi(300);
      await PrinterService.applyPrinterConfiguration(
        printerName: _printerName,
        colorMode: 'BW',
        quality: 'DRAFT',
        dpi: 300,
        force: true,
      );
      await _loadDiagnostics();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Successfully applied 300 DPI Draft & Monochrome configuration!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error configuring driver: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.speed, size: 20, color: AppTheme.accent),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Printer Driver Diagnostics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _loading ? null : _loadDiagnostics,
            tooltip: 'Refresh Diagnostics',
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: _loading
            ? const SizedBox(
                height: 160,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(strokeWidth: 2),
                      SizedBox(height: 12),
                      Text('Querying Windows GDI Device Capabilities...'),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Target Printer Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.print, size: 22, color: AppTheme.accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Target Printer', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                                Text(_printerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(
                                  'Global Policy: $_globalQuality · $_globalDpi DPI',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Live Diagnostics Grid
                    if (_diagnostics != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              title: 'Active Hardware DPI',
                              value: '${_diagnostics!.dpiX} x ${_diagnostics!.dpiY} DPI',
                              subtitle: _diagnostics!.dpiX <= 300
                                  ? '✅ 300 DPI (Draft / Fast Eco)'
                                  : '⚠️ ${_diagnostics!.dpiX} DPI (High Density)',
                              isGood: _diagnostics!.dpiX <= 300,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(
                              title: 'Configured Quality',
                              value: _diagnostics!.quality,
                              subtitle: _diagnostics!.isDraft
                                  ? '✅ Draft Mode (Min Ink)'
                                  : 'Normal Quality',
                              isGood: _diagnostics!.isDraft,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              title: 'Printable Area Grid',
                              value: '${_diagnostics!.horzRes} x ${_diagnostics!.vertRes} px',
                              subtitle: 'Effective physical printable canvas',
                              isGood: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(
                              title: 'Paper Sheet Grid',
                              value: '${_diagnostics!.physWidth} x ${_diagnostics!.physHeight} px',
                              subtitle: 'A4 Paper (margins: ${_diagnostics!.offsetX}px)',
                              isGood: true,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Auto-Fit Status Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.fit_screen, size: 20, color: Colors.greenAccent),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Proportional Auto-Fit Scaler: ACTIVE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Any oversized or non-standard scanned PDF (e.g. 1500x2047 pt) will automatically be scaled to fit within the printable A4 margins with zero cutoffs.',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      actions: [
        OutlinedButton.icon(
          icon: _applying
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.flash_on, size: 16),
          label: const Text('Force 300 DPI Draft Config'),
          onPressed: _applying ? null : _forceApplyDraft,
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required bool isGood,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isGood ? Colors.green.withValues(alpha: 0.3) : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isGood ? Colors.greenAccent : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
