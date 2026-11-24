import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

/// Backend wiring. `SupabaseAuthService` reads the singleton client, which
/// only exists after `Supabase.initialize()` succeeds in main.dart.
final authServiceProvider = Provider<AuthService>((ref) {
  return SupabaseAuthService();
});

/// Emits on every sign-in / sign-out / token refresh.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.read(authServiceProvider).authStateChanges;
});

/// The signed-in teacher, or null when signed out.
final currentUserProvider = Provider<User?>((ref) {
  return ref.read(authServiceProvider).currentUser;
});
