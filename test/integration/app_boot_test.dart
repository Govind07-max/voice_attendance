import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voice_attendance/app/app.dart';
import 'package:voice_attendance/app/auth_gate.dart';
import 'package:voice_attendance/features/auth/login_screen.dart';
import 'package:voice_attendance/providers/auth_provider.dart';

/// Smoke test for the app shell.
///
/// NOTE: `testWidgets` installs an HttpOverrides mock that answers 400 to
/// every request, so no real network call can happen in this file. The live
/// sign-in path is covered by test/integration/backend_integration_test.dart.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      publishableKey: dotenv.get('SUPABASE_ANON_KEY'),
    );
  });

  Session _fakeSession() {
    final user = User(
      id: 'test-user-id',
      appMetadata: const {},
      userMetadata: const {'full_name': 'Prof. Govind Suryawanshi'},
      aud: 'authenticated',
      email: 'setup.probe.check@gmail.com',
      createdAt: '2026-01-01T00:00:00.000Z',
    );
    return Session(
      accessToken: 'test-access-token',
      expiresIn: 3600,
      tokenType: 'bearer',
      user: user,
    );
  }

  testWidgets('unauthenticated app shows the login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmartAttendanceApp()));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(AuthGate), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Smart Attendance'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('login form validates the input', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmartAttendanceApp()));
    await tester.pump(const Duration(seconds: 2));

    // Empty submit -> validation errors, no crash.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    // Invalid email / short password are rejected.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), '123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
  });

  testWidgets('a signed-in session opens the dashboard', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
                AuthState(AuthChangeEvent.signedIn, _fakeSession())),
          ),
        ],
        child: const SmartAttendanceApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('SMART ATTEND'), findsOneWidget);
    expect(find.text('Your Classes'), findsOneWidget);
  });
}
