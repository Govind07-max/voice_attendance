import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
    final String url = dotenv.get('SUPABASE_URL', fallback: '');
    final String key = dotenv.get('SUPABASE_ANON_KEY', fallback: '');

    if (url.isNotEmpty && key.isNotEmpty && !url.contains('your-supabase-project')) {
      await Supabase.initialize(
        url: url,
        anonKey: key,
      );
    }
  } catch (e) {
    debugPrint('Supabase/Dotenv initialization skipped or placeholder: $e');
  }

  runApp(
    const ProviderScope(
      child: SmartAttendanceApp(),
    ),
  );
}
