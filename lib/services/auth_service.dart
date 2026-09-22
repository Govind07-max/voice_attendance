import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/profile.dart';

abstract class AuthService {
  User? get currentUser;
  Future<AuthResponse> signIn({required String email, required String password});
  Future<AuthResponse> signUp({required String email, required String password, required String fullName});
  Future<void> signOut();
  Future<TeacherProfile?> fetchProfile();
  Future<void> updateProfile(TeacherProfile profile);
}

class SupabaseAuthService implements AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  User? get currentUser => _client.auth.currentUser;

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

  @override
  Future<void> updateProfile(TeacherProfile profile) async {
    await _client
        .from(AppConstants.tableProfiles)
        .update(profile.toJson())
        .eq('id', profile.id);
  }
}
