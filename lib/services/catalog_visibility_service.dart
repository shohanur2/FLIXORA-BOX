import 'package:supabase_flutter/supabase_flutter.dart';

/// Checks catalogue candidates against the latest FLIXORA Admin publication
/// state without exposing unpublished rows or any video/source URLs.
class CatalogVisibilityService {
  static Future<Set<String>> blockedKeys({
    required SupabaseClient client,
    required List<Map<String, dynamic>> candidates,
  }) async {
    if (candidates.isEmpty) return <String>{};

    final response = await client.functions.invoke(
      'catalog-visibility',
      body: {'candidates': candidates},
    );

    final data = response.data;
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Admin publication lookup failed (${response.status}).');
    }
    if (data is! Map) {
      throw const FormatException('Invalid Admin publication response.');
    }

    final rawKeys = data['blockedKeys'];
    if (rawKeys is! List) {
      throw const FormatException('Admin publication response has no blockedKeys list.');
    }

    return rawKeys
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}
