import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalogue_models.dart';

const catalogueAssetPath = 'assets/marketplace/catalogue_v1.json';

final catalogueProvider = FutureProvider<MarketplaceCatalogue>((ref) async {
  final jsonText = await rootBundle.loadString(catalogueAssetPath);
  final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
  return MarketplaceCatalogue.fromJson(decoded);
});
