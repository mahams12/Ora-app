import '../../catalogue/catalogue_models.dart';

class RentalSearchMatch {
  const RentalSearchMatch({
    required this.category,
    required this.score,
    this.subcategory,
  });

  final RentalCategory category;
  final RentalSubcategory? subcategory;
  final int score;

  String get id => subcategory?.id ?? category.id;
  String get name => subcategory?.name ?? category.name;
}

class RentalCatalogueSearch {
  RentalCatalogueSearch._();

  static List<RentalSearchMatch> search(
    List<RentalCategory> categories,
    String query, {
    int limit = 30,
  }) {
    final tokens = _tokens(query);
    if (tokens.isEmpty || limit <= 0) return const [];

    final matches = <RentalSearchMatch>[];
    for (final category in categories) {
      final categoryScore = _score(tokens, category.name, const []);
      if (categoryScore != null) {
        matches.add(
          RentalSearchMatch(category: category, score: categoryScore),
        );
      }
      for (final subcategory in category.subcategories) {
        final score = _score(tokens, subcategory.name, subcategory.keywords);
        if (score != null) {
          matches.add(
            RentalSearchMatch(
              category: category,
              subcategory: subcategory,
              score: score,
            ),
          );
        }
      }
    }
    matches.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      return scoreOrder != 0
          ? scoreOrder
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return List.unmodifiable(matches.take(limit));
  }

  static int? _score(
    List<String> queryTokens,
    String name,
    List<String> keywords,
  ) {
    final nameTokens = _tokens(name);
    final keywordTokens = _tokens(keywords.join(' '));
    var score = 0;
    for (final queryToken in queryTokens) {
      final hit = nameTokens.contains(queryToken)
          ? 40
          : nameTokens.any((token) => token.startsWith(queryToken))
          ? 30
          : keywordTokens.any((token) => token.startsWith(queryToken))
          ? 20
          : 0;
      if (hit == 0) return null;
      score += hit;
    }
    return score;
  }

  static List<String> _tokens(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];
    return normalized.split(RegExp(r'\s+'));
  }
}
