import 'package:flutter/material.dart';
import '../services/printer_service.dart';
import '../theme/app_theme.dart';

class PrinterStatusChip extends StatelessWidget {
  final PrinterConnectionStatus status;
  final bool isPrinting;
  final int? currentJobCode;
  final VoidCallback onRefresh;

  const PrinterStatusChip({
    super.key,
    required this.status,
    this.isPrinting = false,
    this.currentJobCode,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    String text;

    if (isPrinting) {
      dotColor = Colors.amberAccent;
      text = currentJobCode != null
          ? 'PRINTING #$currentJobCode...'
          : 'PRINTING...';
    } else {
      switch (status) {
        case PrinterConnectionStatus.online:
          dotColor = Colors.greenAccent;
          text = 'PRINTER: READY';
          break;
        case PrinterConnectionStatus.offline:
          dotColor = Colors.redAccent;
          text = 'PRINTER: OFFLINE';
          break;
        case PrinterConnectionStatus.checking:
          dotColor = AppTheme.textSecondary;
          text = 'CHECKING...';
          break;
      }
    }

    return InkWell(
      onTap: onRefresh,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
