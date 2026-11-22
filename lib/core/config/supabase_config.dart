// lib/core/config/supabase_config.dart
// Centralized Supabase client configuration for the Eleven11 Flutter app.
// ONLY the publishable (anon) key is stored here. NEVER expose the service‑role
// (secret) key on the client. The secret key must be kept in server‑side
// environment variables (e.g. in supabase/.env.production) and used only by
// Edge Functions or backend services.

class SupabaseConfig {
  // Project URL – replace with your Supabase instance URL.
  static const String url = 'https://olzbsktkvnsincriadvi.supabase.co';

  // Publishable anon key – safe to ship with the mobile app.
  static const String anonKey =
      'sb_publishable_ZqlGY5phLkNgd--QGLr1kg_bmhXs9HV';
}
