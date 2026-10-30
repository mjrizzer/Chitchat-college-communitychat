import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract final class Environment {
  static String url = const String.fromEnvironment('SUPABASE_URL');
  static String key = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const redirect = 'com.communityconnect.app://auth/callback';
  static bool get configured =>
      Uri.tryParse(url)?.hasAuthority == true && key.isNotEmpty;
  static bool isPublicKey(String value) {
    if (value.startsWith('sb_publishable_')) {
      return value.length > 20;
    }
    try {
      final parts = value.split('.');
      if (parts.length != 3) {
        return false;
      }
      return jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          )['role'] ==
          'anon';
    } catch (_) {
      return false;
    }
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (url.isEmpty) {
      url = prefs.getString('supabase_url') ?? '';
      key = prefs.getString('supabase_public_key') ?? '';
    }
  }

  static Future<void> save(String nextUrl, String nextKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('supabase_url', nextUrl);
    await prefs.setString('supabase_public_key', nextKey);
    url = nextUrl;
    key = nextKey;
  }
}
