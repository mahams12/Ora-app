import 'catalogue_models.dart';

class LogisticsSearchMatch {
  const LogisticsSearchMatch({
    required this.category,
    required this.score,
    this.type,
  });

  final LogisticsCategory category;
  final LogisticsVehicleType? type;
  final int score;

  String get id => type?.id ?? category.id;
  String get name => type?.name ?? category.name;
}

class ServiceSearchMatch {
  const ServiceSearchMatch({
    required this.category,
    required this.score,
    this.subcategory,
  });

  final ServiceCategory category;
  final ServiceSubcategory? subcategory;
  final int score;

  String get id => subcategory?.id ?? category.id;
  String get name => subcategory?.name ?? category.name;
}

class CatalogueSearchResults {
  CatalogueSearchResults({
    required List<LogisticsSearchMatch> logistics,
    required List<ServiceSearchMatch> services,
  }) : logistics = List.unmodifiable(logistics),
       services = List.unmodifiable(services);

  final List<LogisticsSearchMatch> logistics;
  final List<ServiceSearchMatch> services;

  int get length => logistics.length + services.length;
  bool get isEmpty => logistics.isEmpty && services.isEmpty;
}

class CatalogueSearch {
  CatalogueSearch._();

  static CatalogueSearchResults search(
    MarketplaceCatalogue catalogue,
    String query, {
    int limit = 30,
  }) {
    final queryTokens = _tokens(query);
    if (queryTokens.isEmpty || limit <= 0) {
      return CatalogueSearchResults(logistics: const [], services: const []);
    }

    final candidates = <_RankedMatch>[];
    for (final category in catalogue.logistics) {
      final categoryScore = _score(queryTokens, category.name, const [], null);
      if (categoryScore != null) {
        candidates.add(
          _RankedMatch.logistics(
            LogisticsSearchMatch(category: category, score: categoryScore),
          ),
        );
      }
      for (final type in category.types) {
        final score = _score(
          queryTokens,
          type.name,
          type.keywords,
          category.name,
        );
        if (score != null) {
          candidates.add(
            _RankedMatch.logistics(
              LogisticsSearchMatch(
                category: category,
                type: type,
                score: score,
              ),
            ),
          );
        }
      }
    }

    for (final category in catalogue.services) {
      final categoryScore = _score(queryTokens, category.name, const [], null);
      if (categoryScore != null) {
        candidates.add(
          _RankedMatch.services(
            ServiceSearchMatch(category: category, score: categoryScore),
          ),
        );
      }
      for (final subcategory in category.subcategories) {
        final score = _score(
          queryTokens,
          subcategory.name,
          subcategory.keywords,
          category.name,
        );
        if (score != null) {
          candidates.add(
            _RankedMatch.services(
              ServiceSearchMatch(
                category: category,
                subcategory: subcategory,
                score: score,
              ),
            ),
          );
        }
      }
    }

    candidates.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      return scoreOrder != 0
          ? scoreOrder
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final logistics = <LogisticsSearchMatch>[];
    final services = <ServiceSearchMatch>[];
    for (final candidate in candidates.take(limit)) {
      if (candidate.logistics != null) {
        logistics.add(candidate.logistics!);
      } else {
        services.add(candidate.services!);
      }
    }
    return CatalogueSearchResults(logistics: logistics, services: services);
  }

  static int? _score(
    List<String> queryTokens,
    String name,
    List<String> keywords,
    String? categoryName,
  ) {
    final nameTokens = _tokens(name);
    final keywordTokens = _tokens(keywords.join(' '));
    final categoryTokens = _tokens(categoryName ?? '');
    var score = 0;
    for (final queryToken in queryTokens) {
      final hit = nameTokens.contains(queryToken)
          ? 40
          : nameTokens.any((token) => token.startsWith(queryToken))
          ? 30
          : keywordTokens.any((token) => token.startsWith(queryToken))
          ? 20
          : categoryTokens.any((token) => token.startsWith(queryToken))
          ? 10
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

class _RankedMatch {
  const _RankedMatch._({
    required this.score,
    required this.name,
    this.logistics,
    this.services,
  });

  factory _RankedMatch.logistics(LogisticsSearchMatch match) =>
      _RankedMatch._(score: match.score, name: match.name, logistics: match);

  factory _RankedMatch.services(ServiceSearchMatch match) =>
      _RankedMatch._(score: match.score, name: match.name, services: match);

  final int score;
  final String name;
  final LogisticsSearchMatch? logistics;
  final ServiceSearchMatch? services;
}
