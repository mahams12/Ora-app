import 'package:flutter/material.dart';

import '../../../../app/theme/widgets/ora_empty_state.dart';

class MarketplaceEmptyState extends StatelessWidget {
  const MarketplaceEmptyState({
    required this.title,
    super.key,
    this.message,
    this.icon = Icons.search_off_rounded,
  });

  final String title;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return OraEmptyState(title: title, message: message, icon: icon);
  }
}
