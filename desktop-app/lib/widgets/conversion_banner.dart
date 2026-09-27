import 'package:flutter/material.dart';
import '../services/libreoffice_service.dart';
import '../theme/app_theme.dart';

class ConversionBanner extends StatelessWidget {
  const ConversionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LibreOfficeService.isConverting,
      builder: (context, isConverting, child) {
        if (!isConverting) return const SizedBox.shrink();

        return ValueListenableBuilder<String?>(
          valueListenable: LibreOfficeService.currentConvertingFile,
          builder: (context, filename, child) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF22272B),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF388BFF), width: 1.5),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '⚙️ LibreOffice is converting "${filename ?? 'document'}" to PDF in the background... Please wait.',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
