import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyToken = 'auth_token';
  static const String _keyBackendUrl = 'backend_url';
  static const String _keyPrinterName = 'printer_name';
  static const String _keyPrinterIp = 'printer_ip';
  static const String _keyAskApproval = 'ask_approval_before_conversion';
  static const String _keyLibreOfficePath = 'libreoffice_path';
  static const String _keyPollingInterval = 'polling_interval';
  static const String _keyGlobalQuality = 'global_quality';
  static const String _keyGlobalDpi = 'global_dpi';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_keyToken);
    } else {
      await prefs.setString(_keyToken, token);
    }
  }

  static Future<String> getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBackendUrl) ?? 'https://hostel-print-backend-7w74.onrender.com';
  }

  static Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackendUrl, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  static Future<String> getPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPrinterName) ?? 'HP Smart Tank 580-590 series';
  }

  static Future<void> setPrinterName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPrinterName, name);
  }

  static Future<String> getPrinterIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPrinterIp) ?? '192.168.1.2';
  }

  static Future<void> setPrinterIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPrinterIp, ip.trim());
  }

  static Future<bool> getAskApprovalBeforeConversion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAskApproval) ?? true;
  }

  static Future<void> setAskApprovalBeforeConversion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAskApproval, value);
  }

  static Future<String> getLibreOfficePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLibreOfficePath) ??
        r'C:\Program Files\LibreOffice\program\soffice.exe';
  }

  static Future<void> setLibreOfficePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLibreOfficePath, path.trim());
  }

  static Future<int> getPollingInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPollingInterval) ?? 5;
  }

  static Future<void> setPollingInterval(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPollingInterval, seconds);
  }

  // --- Global Print Overrides ---

  static Future<String> getGlobalQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGlobalQuality) ?? 'NORMAL';
  }

  static Future<void> setGlobalQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGlobalQuality, quality);
  }

  static Future<int> getGlobalDpi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyGlobalDpi) ?? 600;
  }

  static Future<void> setGlobalDpi(int dpi) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyGlobalDpi, dpi);
  }
}
