import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final clientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
final authProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(clientProvider).auth.onAuthStateChange,
);
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(authProvider);
  final client = ref.watch(clientProvider);
  final id = client.auth.currentUser?.id;
  return id == null
      ? null
      : await client.from('profiles').select().eq('id', id).maybeSingle();
});
