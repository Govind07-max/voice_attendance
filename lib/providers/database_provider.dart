import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import 'auth_provider.dart';

/// Backend data access.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return SupabaseDatabaseService();
});

/// The signed-in teacher's auth uid — the tenant key for every RLS policy.
final teacherIdProvider = Provider<String?>((ref) {
  final user = ref.watch(currentUserProvider);
  return user?.id;
});
