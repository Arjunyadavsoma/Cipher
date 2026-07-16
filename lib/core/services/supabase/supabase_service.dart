import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: dotenv.env['YOUR_SUPABASE_URL']!,
      anonKey: dotenv.env['YOUR_SUPABASE_ANON_KEY']!,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
