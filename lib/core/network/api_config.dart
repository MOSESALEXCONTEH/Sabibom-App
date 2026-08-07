/// Public Vercel API base URL. Not a secret.
///
/// Override at build/run time:
/// `--dart-define=SABIBOM_API_BASE_URL=https://your-project.vercel.app`
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'SABIBOM_API_BASE_URL',
    defaultValue: 'https://vercel-api-moses-alex-conteh-s-projects.vercel.app',
  );

  static Uri uri(String path) {
    final normalizedBase = baseUrl.replaceAll(RegExp(r'/$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }
}
