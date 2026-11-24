import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'app/configuration_screen.dart';

/// Set to false in release builds to hide the demo-data path entirely.
const bool kDemoMode = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String url = '';
  String publishableKey = '';
  String configError = '';

  try {
    await dotenv.load(fileName: '.env');
    url = dotenv.get('SUPABASE_URL', fallback: '').trim();
    publishableKey =
        dotenv.get('SUPABASE_ANON_KEY', fallback: '').trim();
  } catch (e) {
    configError = 'Could not read the .env file ($e).';
  }

  final bool looksConfigured = url.isNotEmpty &&
      publishableKey.isNotEmpty &&
      !url.contains('your-supabase-project') &&
      !publishableKey.contains('your-supabase-anon-key') &&
      url.startsWith('http');

  if (looksConfigured) {
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: publishableKey,
      );
    } catch (e) {
      configError = 'Supabase could not start ($e).';
    }
  } else if (configError.isEmpty) {
    configError =
        'SUPABASE_URL / SUPABASE_ANON_KEY are missing or still placeholders.';
  }

  runApp(
    ProviderScope(
      child: looksConfigured && configError.isEmpty
          ? const SmartAttendanceApp()
          : ConfigurationScreen(reason: configError),
    ),
  );
}
