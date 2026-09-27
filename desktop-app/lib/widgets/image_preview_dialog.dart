import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ImagePreviewDialog extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;
  final VoidCallback? onViewPrintLayout;

  const ImagePreviewDialog({
    super.key,
    required this.imageBytes,
    required this.title,
    this.onViewPrintLayout,
  });

  static Future<void> show(
    BuildContext context,
    Uint8List imageBytes,
    String title, {
    VoidCallback? onViewPrintLayout,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => ImagePreviewDialog(
        imageBytes: imageBytes,
        title: title,
        onViewPrintLayout: onViewPrintLayout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.image, size: 20, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Image Preview: $title',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onViewPrintLayout != null) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('View Print Layout (A4)'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onViewPrintLayout!();
                    },
                  ),
                  const SizedBox(width: 10),
                ],
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close Preview',
                ),
              ],
            ),
          ),
          // Interactive Image Viewer
          Expanded(
            child: Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.broken_image, size: 48, color: Colors.redAccent),
                            const SizedBox(height: 12),
                            Text('Unable to display image: $error'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
