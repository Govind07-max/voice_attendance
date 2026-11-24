import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/profile.dart';

abstract class AuthService {
  User? get currentUser;
  Stream<AuthState> get authStateChanges;
  Future<AuthResponse> signIn({required String email, required String password});
  Future<AuthResponse> signUp({required String email, required String password, required String fullName});
  Future<void> signOut();
  Future<TeacherProfile?> fetchProfile();
  Future<TeacherProfile> ensureProfile({required String fullName, required String email});
  Future<void> updateProfile(TeacherProfile profile);
}

class SupabaseAuthService implements AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  User? get currentUser => _client.auth.currentUser;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Future<AuthResponse> signIn({required String email, required String password}) async {
    return await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<AuthResponse> signUp({
    required String email, 
    required String password, 
    required String fullName,
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<TeacherProfile?> fetchProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await _client
        .from(AppConstants.tableProfiles)
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) return null;
    return TeacherProfile.fromJson(response);
  }

  /// Creates the profile row if the signup trigger did not (e.g. the user
  /// was created before the trigger existed).
  @override
  Future<TeacherProfile> ensureProfile({
    required String fullName,
    required String email,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No signed-in user.');
    }

    final existing = await fetchProfile();
    if (existing != null) return existing;

    final row = {
      'id': user.id,
      'full_name': fullName,
      'email': email,
      'department': 'Electronics & Telecommunication Engineering',
      'default_threshold': 75.0,
    };

    final response = await _client
        .from(AppConstants.tableProfiles)
        .upsert(row, onConflict: 'id')
        .select()
        .single();
    return TeacherProfile.fromJson(response);
  }

  @override
  Future<void> updateProfile(TeacherProfile profile) async {
    await _client
        .from(AppConstants.tableProfiles)
        .update(profile.toJson())
        .eq('id', profile.id);
  }
}
