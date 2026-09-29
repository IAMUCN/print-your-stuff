import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 750),
    minimumSize: Size(960, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'Hostel Print Manager',
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setResizable(true);
    await windowManager.show();
    await windowManager.focus();
  });

  final token = await StorageService.getToken();

  runApp(HostelPrintAdminApp(hasToken: token != null && token.isNotEmpty));
}

class HostelPrintAdminApp extends StatelessWidget {
  final bool hasToken;

  const HostelPrintAdminApp({super.key, required this.hasToken});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hostel Print Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: hasToken ? const DashboardScreen() : const LoginScreen(),
    );
  }
}
