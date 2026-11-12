/// Keeps MovieBox/WeFeed as FLIXORA's primary content source while
/// retaining Admin publication as the fallback for Admin-only titles.
class CatalogPriorityPolicy {
  CatalogPriorityPolicy._();

  static T preferMovieBox<T>(T fallback, T? movieBoxMatch) =>
      movieBoxMatch ?? fallback;

  /// An Admin Unpublish must not hide a title that independently exists in
  /// the primary MovieBox catalogue.
  static bool shouldHideUnpublished({
    required bool isMovieBox,
    required bool isUnpublished,
  }) =>
      isUnpublished && !isMovieBox;
}
