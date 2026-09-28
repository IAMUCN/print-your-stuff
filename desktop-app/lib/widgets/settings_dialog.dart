import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/storage_service.dart';
import '../services/printer_service.dart';
import '../theme/app_theme.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => const SettingsDialog(),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _backendUrlController = TextEditingController();
  final _printerIpController = TextEditingController();
  final _libreOfficePathController = TextEditingController();

  List<Printer> _installedPrinters = [];
  String? _selectedPrinter;
  bool _askApproval = true;
  int _pollingInterval = 5;
  String _globalQuality = 'NORMAL';
  int _globalDpi = 600;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final backendUrl = await StorageService.getBackendUrl();
    final printerName = await StorageService.getPrinterName();
    final printerIp = await StorageService.getPrinterIp();
    final askApproval = await StorageService.getAskApprovalBeforeConversion();
    final loPath = await StorageService.getLibreOfficePath();
    final interval = await StorageService.getPollingInterval();
    final quality = await StorageService.getGlobalQuality();
    final dpi = await StorageService.getGlobalDpi();

    final printers = await PrinterService.listInstalledPrinters();

    setState(() {
      _backendUrlController.text = backendUrl;
      _printerIpController.text = printerIp;
      _libreOfficePathController.text = loPath;
      _installedPrinters = printers;
      _selectedPrinter = printerName;
      _askApproval = askApproval;
      _pollingInterval = interval;
      _globalQuality = quality;
      _globalDpi = dpi;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    await StorageService.setBackendUrl(_backendUrlController.text);
    if (_selectedPrinter != null) {
      await StorageService.setPrinterName(_selectedPrinter!);
    }
    await StorageService.setPrinterIp(_printerIpController.text);
    await StorageService.setAskApprovalBeforeConversion(_askApproval);
    await StorageService.setLibreOfficePath(_libreOfficePathController.text);
    await StorageService.setPollingInterval(_pollingInterval);
    await StorageService.setGlobalQuality(_globalQuality);
    await StorageService.setGlobalDpi(_globalDpi);

    if (_selectedPrinter != null) {
      // Prime the driver configuration immediately so subsequent prints start instantly with 0ms lag
      unawaited(PrinterService.applyPrinterConfiguration(
        printerName: _selectedPrinter!,
        colorMode: 'BW',
        quality: _globalQuality,
        dpi: _globalDpi,
        force: true,
      ));
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved & printer profile primed!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final printerValue = _installedPrinters.any((p) => p.name == _selectedPrinter)
        ? _selectedPrinter
        : (_installedPrinters.isNotEmpty ? _installedPrinters.first.name : null);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings, size: 22),
          SizedBox(width: 10),
          Text('Workstation Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cloud Backend
              const Text('CLOUD BACKEND', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 6),
              TextField(
                controller: _backendUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend REST API URL',
                  hintText: 'e.g. http://localhost:3000 or https://your-backend.onrender.com',
                ),
              ),
              const SizedBox(height: 20),

              // Printer Configuration
              const Text('PRINTER CONFIGURATION (HP Smart Tank 589)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: printerValue,
                decoration: const InputDecoration(labelText: 'Target Windows Printer Driver'),
                items: _installedPrinters
                    .map((p) => DropdownMenuItem(
                          value: p.name,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => _selectedPrinter = val),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tip: Select "HP Smart Tank 580-590 series" for USB Cable, or "TCS (...)" for Wi-Fi.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _printerIpController,
                decoration: const InputDecoration(
                  labelText: 'Printer Local IP (for live Online status heartbeat)',
                  hintText: 'e.g. 192.168.1.150',
                ),
              ),
              const SizedBox(height: 20),

              // Global Hardware Print Overrides
              const Text(
                'GLOBAL HARDWARE PRINT OVERRIDES (Injected into Driver)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Directly configures the Windows Print Spooler & HP hardware driver before every job, guaranteeing exact color mode and print density.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _globalQuality,
                      decoration: const InputDecoration(labelText: 'Print Quality'),
                      items: const [
                        DropdownMenuItem(value: 'DRAFT', child: Text('Draft (Fast / Eco)')),
                        DropdownMenuItem(value: 'NORMAL', child: Text('Normal (Default)')),
                        DropdownMenuItem(value: 'BEST', child: Text('Best / High Quality')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _globalQuality = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _globalDpi,
                      decoration: const InputDecoration(labelText: 'Hardware Resolution'),
                      items: const [
                        DropdownMenuItem(value: 300, child: Text('300 DPI (Standard)')),
                        DropdownMenuItem(value: 600, child: Text('600 DPI (Recommended)')),
                        DropdownMenuItem(value: 1200, child: Text('1200 DPI (Ultra Fine Detail)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _globalDpi = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Document Conversion
              const Text('DOCUMENT CONVERSION & RESOURCE SAFEGUARDS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ask approval before converting Docs to PDF', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Prompts you before launching LibreOffice to protect laptop performance.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                value: _askApproval,
                onChanged: (val) => setState(() => _askApproval = val),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _libreOfficePathController,
                decoration: const InputDecoration(
                  labelText: 'LibreOffice Executable Path',
                  hintText: r'C:\Program Files\LibreOffice\program\soffice.exe',
                ),
              ),
              const SizedBox(height: 20),

              // Queue Polling
              const Text('QUEUE & REFRESH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: _pollingInterval,
                decoration: const InputDecoration(labelText: 'Background Auto-Polling Interval'),
                items: const [
                  DropdownMenuItem(value: 3, child: Text('Every 3 seconds')),
                  DropdownMenuItem(value: 5, child: Text('Every 5 seconds (Recommended)')),
                  DropdownMenuItem(value: 10, child: Text('Every 10 seconds')),
                  DropdownMenuItem(value: 30, child: Text('Every 30 seconds')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _pollingInterval = val);
                },
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveSettings,
          child: const Text('Save Settings'),
        ),
      ],
    );
  }
}
