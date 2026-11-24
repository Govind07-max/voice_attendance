import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Shown when the app has no usable Supabase credentials, so the teacher
/// never sees an empty dashboard and wonders why nothing saves.
class ConfigurationScreen extends StatelessWidget {
  final String reason;
  const ConfigurationScreen({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings_suggest_rounded,
                      size: 48, color: AppColors.primary),
                  const SizedBox(height: 16),
                  const Text('Backend not configured',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    reason,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Fix it in 3 steps:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        SizedBox(height: 10),
                        Text(
                          '1. Copy .env.example to .env\n'
                          '2. Paste your Supabase Project URL and publishable key\n'
                          '3. Run the migration in supabase/migrations/ in the SQL Editor',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
