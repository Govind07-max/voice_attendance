import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import '../core/constants.dart';
import '../services/attendance_writer.dart';
import 'auth_gate.dart';

class SmartAttendanceApp extends ConsumerWidget {
  const SmartAttendanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const _SyncBootstrap(child: AuthGate()),
    );
  }
}

/// Starts the offline write queue as soon as the app boots.
///
/// Marks taken without a connection are saved on the device; this replays them
/// the moment the app is opened again, even before the teacher walks into a
/// lecture.
class _SyncBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const _SyncBootstrap({required this.child});

  @override
  ConsumerState<_SyncBootstrap> createState() => _SyncBootstrapState();
}

class _SyncBootstrapState extends ConsumerState<_SyncBootstrap> {
  @override
  void initState() {
    super.initState();
    // Creates the singleton writer, which loads the saved queue and flushes it.
    ref.read(attendanceWriterProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
