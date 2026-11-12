/// Shared source-priority and Admin-visibility rules for the FLIXORA catalogue.
class CatalogSourcePolicy {
  CatalogSourcePolicy._();

  /// MovieBox is canonical. A published Admin row is used only when no
  /// matching MovieBox title exists.
  static T? preferMovieBox<T>({
    required T? movieBoxMatch,
    required T? publishedAdminFallback,
  }) {
    return movieBoxMatch ?? publishedAdminFallback;
  }

  /// Keep MovieBox records before duplicate Admin/TMDB records so all
  /// first-match catalogue deduplication paths preserve the primary source.
  static List<T> movieBoxFirst<T>(
    Iterable<T> items, {
    required bool Function(T item) isMovieBox,
  }) {
    final values = items.toList(growable: false);
    return <T>[
      ...values.where(isMovieBox),
      ...values.where((item) => !isMovieBox(item)),
    ];
  }

  /// Admin publication status must never be applied to MovieBox or TMDB rows.
  static List<T> adminCandidates<T>(
    Iterable<T> items, {
    required bool Function(T item) isAdmin,
  }) {
    return items.where(isAdmin).toList(growable: false);
  }

  /// Scope publication state to one Admin database row, not a shared TMDB ID
  /// or title/year key that could also identify a MovieBox catalogue item.
  static String? adminVisibilityKey({
    required bool isAdmin,
    required int sourceId,
  }) {
    if (!isAdmin || sourceId <= 0) return null;
    return 'admin:id:$sourceId';
  }

  static bool isAdminBlocked({
    required bool isAdmin,
    required String? visibilityKey,
    required Set<String> blockedKeys,
  }) {
    return isAdmin &&
        visibilityKey != null &&
        visibilityKey.isNotEmpty &&
        blockedKeys.contains(visibilityKey);
  }
}
