import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LibreOfficeApprovalDialog extends StatelessWidget {
  final String filename;

  const LibreOfficeApprovalDialog({super.key, required this.filename});

  static Future<bool> show(BuildContext context, String filename) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LibreOfficeApprovalDialog(filename: filename),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 22),
          SizedBox(width: 10),
          Text(
            'Convert Document to PDF?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.4),
              children: [
                const TextSpan(text: 'The file '),
                TextSpan(
                  text: '"$filename"',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(
                  text: ' is a Word document and needs to be converted into a PDF for printing.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.memory, size: 18, color: AppTheme.textSecondary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Headless LibreOffice will launch on your laptop. This may temporarily use CPU & RAM. Do you accept launching conversion?',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Approve & Convert'),
        ),
      ],
    );
  }
}
