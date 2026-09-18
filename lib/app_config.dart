class AppConfig {
  static const _defaultSupabaseUrl =
      'https://qwuyplumilrmtfovgfjp.supabase.co';
  static const _defaultSupabasePublishableKey =
      'sb_publishable_a7lmZ7OdYAAtHFDA2TxMNA_1vgU6dcK';

  static const _configuredSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const _configuredSupabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  // GitHub Actions expands missing repository variables to empty strings.
  // Empty build-time values must not disable the app's production connection.
  static final supabaseUrl = _configuredSupabaseUrl.isEmpty
      ? _defaultSupabaseUrl
      : _configuredSupabaseUrl;
  static final supabasePublishableKey =
      _configuredSupabasePublishableKey.isEmpty
      ? _defaultSupabasePublishableKey
      : _configuredSupabasePublishableKey;

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
