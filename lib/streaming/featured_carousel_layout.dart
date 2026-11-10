/// Shared geometry for the Home hero slider's synchronized poster row.
class FeaturedCarouselLayout {
  FeaturedCarouselLayout._();

  static const double cardWidth = 238.0;
  static const double cardMargin = 5.0;
  static const double horizontalPadding = 12.0;
  static const double cardExtent = cardWidth + cardMargin * 2;
  static const double leadingInset = horizontalPadding + cardMargin;

  static double targetScrollOffset({
    required int index,
    required double viewportWidth,
    required double maxScrollExtent,
  }) {
    if (index <= 0 || viewportWidth <= 0 || maxScrollExtent <= 0) return 0;
    final target = leadingInset + index * cardExtent +
        cardWidth / 2 - viewportWidth / 2;
    return target.clamp(0.0, maxScrollExtent).toDouble();
  }

  static int indexForScrollOffset({
    required double pixels,
    required double viewportWidth,
    required int itemCount,
  }) {
    if (itemCount <= 1 || viewportWidth <= 0) return 0;
    final selected = ((pixels + viewportWidth / 2 -
            leadingInset - cardWidth / 2) / cardExtent).round();
    return selected.clamp(0, itemCount - 1).toInt();
  }
}
