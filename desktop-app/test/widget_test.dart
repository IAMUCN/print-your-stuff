import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_print_admin/main.dart';
import 'package:hostel_print_admin/screens/login_screen.dart';

void main() {
  testWidgets('App loads login screen by default when unauthenticated', (WidgetTester tester) async {
    await tester.pumpWidget(const HostelPrintAdminApp(hasToken: false));
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
