import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LogLevel { info, success, warning, error }

enum LogCategory { print, download, network, driver, system }

class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final LogCategory category;
  final String title;
  final String message;
  final String? details;
  final String? jobCode;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.title,
    required this.message,
    this.details,
    this.jobCode,
  });

  String get formattedTime => DateFormat('HH:mm:ss').format(timestamp);
  String get formattedDate => DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.write('[$formattedDate] [${level.name.toUpperCase()}] [${category.name.toUpperCase()}]');
    if (jobCode != null && jobCode!.isNotEmpty) {
      buffer.write(' [Job #$jobCode]');
    }
    buffer.write(' $title: $message');
    if (details != null && details!.trim().isNotEmpty) {
      buffer.write('\n    Details: ${details!.replaceAll('\n', '\n    ')}');
    }
    return buffer.toString();
  }
}

class LoggerService extends ChangeNotifier {
  static final LoggerService instance = LoggerService._internal();

  factory LoggerService() => instance;

  LoggerService._internal() {
    _initFileLogging();
  }

  final List<LogEntry> _entries = [];
  int _unreadErrorCount = 0;
  File? _logFile;

  List<LogEntry> get entries => List.unmodifiable(_entries.reversed);
  int get unreadErrorCount => _unreadErrorCount;
  bool get hasErrors => _entries.any((e) => e.level == LogLevel.error);
  String? get logFilePath => _logFile?.path;

  Future<void> _initFileLogging() async {
    try {
      Directory? appDir;
      try {
        appDir = await getApplicationSupportDirectory();
      } catch (_) {}

      final baseDirPath = appDir?.path ??
          Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          'C:\\HostelPrintAdmin';

      final logDir = Directory(p.join(baseDirPath, 'HostelPrintAdmin', 'logs'));
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      _logFile = File(p.join(logDir.path, 'hostel_print_admin.log'));

      // If log file exceeds 5MB, rotate it
      if (await _logFile!.exists()) {
        final length = await _logFile!.length();
        if (length > 5 * 1024 * 1024) {
          final oldLog = File(p.join(logDir.path, 'hostel_print_admin_prev.log'));
          if (await oldLog.exists()) {
            await oldLog.delete();
          }
          await _logFile!.rename(oldLog.path);
          _logFile = File(p.join(logDir.path, 'hostel_print_admin.log'));
        }
      }

      await _appendToFile(
        '=== Hostel Print Manager Log Initialized [${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}] ===\n',
      );
    } catch (e) {
      debugPrint('⚠️ Could not initialize file logging: $e');
    }
  }

  Future<void> _appendToFile(String text) async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('⚠️ Error writing to log file: $e');
    }
  }

  void log({
    required LogLevel level,
    required LogCategory category,
    required String title,
    required String message,
    String? details,
    String? jobCode,
  }) {
    final entry = LogEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_entries.length}',
      timestamp: DateTime.now(),
      level: level,
      category: category,
      title: title,
      message: message,
      details: details,
      jobCode: jobCode,
    );

    _entries.add(entry);
    if (level == LogLevel.error) {
      _unreadErrorCount++;
    }

    // Keep memory cache within 500 items
    if (_entries.length > 500) {
      _entries.removeRange(0, _entries.length - 500);
    }

    _appendToFile('${entry.toFormattedString()}\n');
    notifyListeners();
  }

  void error(
    String title,
    String message, {
    String? details,
    String? jobCode,
    LogCategory category = LogCategory.system,
  }) {
    log(
      level: LogLevel.error,
      category: category,
      title: title,
      message: message,
      details: details,
      jobCode: jobCode,
    );
  }

  void warning(
    String title,
    String message, {
    String? details,
    String? jobCode,
    LogCategory category = LogCategory.system,
  }) {
    log(
      level: LogLevel.warning,
      category: category,
      title: title,
      message: message,
      details: details,
      jobCode: jobCode,
    );
  }

  void info(
    String title,
    String message, {
    String? details,
    String? jobCode,
    LogCategory category = LogCategory.system,
  }) {
    log(
      level: LogLevel.info,
      category: category,
      title: title,
      message: message,
      details: details,
      jobCode: jobCode,
    );
  }

  void success(
    String title,
    String message, {
    String? details,
    String? jobCode,
    LogCategory category = LogCategory.system,
  }) {
    log(
      level: LogLevel.success,
      category: category,
      title: title,
      message: message,
      details: details,
      jobCode: jobCode,
    );
  }

  void markErrorsAsRead() {
    if (_unreadErrorCount > 0) {
      _unreadErrorCount = 0;
      notifyListeners();
    }
  }

  void clear() {
    _entries.clear();
    _unreadErrorCount = 0;
    _appendToFile(
      '=== Logs Cleared by Admin [${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}] ===\n',
    );
    notifyListeners();
  }

  Future<void> copyLogsToClipboard({LogLevel? filterLevel}) async {
    final filtered = filterLevel == null
        ? _entries
        : _entries.where((e) => e.level == filterLevel);
    final text = filtered.map((e) => e.toFormattedString()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> openLogInNotepad() async {
    if (_logFile != null && await _logFile!.exists()) {
      try {
        await Process.run('notepad.exe', [_logFile!.path]);
      } catch (e) {
        debugPrint('Failed to open notepad: $e');
      }
    }
  }
}
