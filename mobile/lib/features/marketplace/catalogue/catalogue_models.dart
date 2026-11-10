class MarketplaceCatalogue {
  MarketplaceCatalogue({
    required List<LogisticsCategory> logistics,
    required List<ServiceCategory> services,
    required List<RentalCategory> rental,
  }) : logistics = List.unmodifiable(logistics),
       services = List.unmodifiable(services),
       rental = List.unmodifiable(rental);

  final List<LogisticsCategory> logistics;
  final List<ServiceCategory> services;
  final List<RentalCategory> rental;

  factory MarketplaceCatalogue.fromJson(Map<String, dynamic> json) {
    return MarketplaceCatalogue(
      logistics: (json['logistics'] as List<dynamic>)
          .map(
            (item) => LogisticsCategory.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      services: (json['services'] as List<dynamic>)
          .map((item) => ServiceCategory.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      rental: (json['rental'] as List<dynamic>)
          .map((item) => RentalCategory.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  LogisticsCategory? logisticsCategory(String id) {
    for (final category in logistics) {
      if (category.id == id) return category;
    }
    return null;
  }

  ServiceCategory? serviceCategory(String id) {
    for (final category in services) {
      if (category.id == id) return category;
    }
    return null;
  }

  RentalCategory? rentalCategory(String id) {
    for (final category in rental) {
      if (category.id == id) return category;
    }
    return null;
  }
}

class LogisticsCategory {
  LogisticsCategory({
    required this.id,
    required this.name,
    required this.image,
    required this.blurb,
    required List<LogisticsVehicleType> types,
  }) : types = List.unmodifiable(types);

  final String id;
  final String name;
  final String image;
  final String blurb;
  final List<LogisticsVehicleType> types;

  factory LogisticsCategory.fromJson(Map<String, dynamic> json) {
    return LogisticsCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String,
      blurb: json['blurb'] as String,
      types: (json['types'] as List<dynamic>)
          .map(
            (item) =>
                LogisticsVehicleType.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class LogisticsVehicleType {
  LogisticsVehicleType({
    required this.id,
    required this.name,
    required List<String> keywords,
    this.image,
  }) : keywords = List.unmodifiable(keywords);

  final String id;
  final String name;
  final List<String> keywords;
  final String? image;

  factory LogisticsVehicleType.fromJson(Map<String, dynamic> json) {
    return LogisticsVehicleType(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String?,
      keywords: (json['keywords'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toList(growable: false),
    );
  }
}

class ServiceCategory {
  ServiceCategory({
    required this.id,
    required this.name,
    required this.image,
    required this.blurb,
    required List<ServiceSubcategory> subcategories,
  }) : subcategories = List.unmodifiable(subcategories);

  final String id;
  final String name;
  final String image;
  final String blurb;
  final List<ServiceSubcategory> subcategories;

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String,
      blurb: json['blurb'] as String? ?? '',
      subcategories: (json['subcategories'] as List<dynamic>)
          .map(
            (item) => ServiceSubcategory.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class ServiceSubcategory {
  ServiceSubcategory({
    required this.id,
    required this.name,
    required List<String> keywords,
    String? image,
  }) : image = image ?? 'services/subs/$id.webp',
       keywords = List.unmodifiable(keywords);

  final String id;
  final String name;
  final String image;
  final List<String> keywords;

  factory ServiceSubcategory.fromJson(Map<String, dynamic> json) {
    return ServiceSubcategory(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String?,
      keywords: (json['keywords'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toList(growable: false),
    );
  }
}

class RentalCategory {
  RentalCategory({
    required this.id,
    required this.name,
    required this.image,
    required this.blurb,
    required List<RentalSubcategory> subcategories,
  }) : subcategories = List.unmodifiable(subcategories);

  final String id;
  final String name;
  final String image;
  final String blurb;
  final List<RentalSubcategory> subcategories;

  factory RentalCategory.fromJson(Map<String, dynamic> json) {
    return RentalCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String,
      blurb: json['blurb'] as String? ?? '',
      subcategories: (json['subcategories'] as List<dynamic>)
          .map(
            (item) => RentalSubcategory.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class RentalSubcategory {
  RentalSubcategory({
    required this.id,
    required this.name,
    required List<String> keywords,
    this.image,
  }) : keywords = List.unmodifiable(keywords);

  final String id;
  final String name;
  final List<String> keywords;
  final String? image;

  factory RentalSubcategory.fromJson(Map<String, dynamic> json) {
    return RentalSubcategory(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String?,
      keywords: (json['keywords'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toList(growable: false),
    );
  }
}
