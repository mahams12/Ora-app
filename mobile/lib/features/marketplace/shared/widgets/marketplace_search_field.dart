import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';

const marketplaceSearchDebounce = Duration(milliseconds: 250);

class MarketplaceSearchField extends StatefulWidget {
  const MarketplaceSearchField({
    required this.onChanged,
    super.key,
    this.onSubmitted,
    this.hintText = 'Search services',
    this.initialValue = '',
    this.autofocus = false,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hintText;
  final String initialValue;
  final bool autofocus;

  @override
  State<MarketplaceSearchField> createState() => _MarketplaceSearchFieldState();
}

class _MarketplaceSearchFieldState extends State<MarketplaceSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  Timer? _debounce;

  void _scheduleChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(marketplaceSearchDebounce, () {
      if (mounted) widget.onChanged(value);
    });
  }

  void _submit(String value) {
    _debounce?.cancel();
    widget.onChanged(value);
    widget.onSubmitted?.call(value);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.hintText,
      textField: true,
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: _scheduleChanged,
        onSubmitted: _submit,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: OraColors.textPrimary),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: OraColors.textMuted),
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: OraColors.navyElevated,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: OraSpacing.md,
            vertical: OraSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OraRadius.input),
            borderSide: const BorderSide(color: OraColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OraRadius.input),
            borderSide: const BorderSide(color: OraColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OraRadius.input),
            borderSide: const BorderSide(color: OraColors.primary),
          ),
        ),
      ),
    );
  }
}
