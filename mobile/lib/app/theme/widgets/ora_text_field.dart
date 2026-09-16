import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_radius.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

/// Ora text field with prototype-like label, focus ring, prefix/suffix.
class OraTextField extends StatelessWidget {
  const OraTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.enabled = true,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.minLines,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final int? maxLines;
  final int? minLines;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark
        ? OraColors.textSecondary
        : OraColors.textSecondaryLight;
    final iconColor = isDark
        ? OraColors.textMuted
        : OraColors.textSecondaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: OraTypography.label(labelColor)),
          const SizedBox(height: OraSpacing.xs),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          enabled: enabled,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          autofillHints: autofillHints,
          maxLines: obscureText ? 1 : maxLines,
          minLines: minLines,
          style: OraTypography.body(
            isDark ? OraColors.textPrimary : OraColors.textPrimaryLight,
          ),
          cursorColor: OraColors.primary,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, color: iconColor, size: 18),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: enabled
                ? (isDark ? OraColors.surfaceElevated : Colors.white)
                : OraColors.disabled.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}

/// Compact OTP-style digit box (visual only — no SMS logic).
class OraPinBox extends StatelessWidget {
  const OraPinBox({
    super.key,
    this.value = '',
    this.focused = false,
    this.hasError = false,
  });

  final String value;
  final bool focused;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = hasError
        ? OraColors.danger
        : focused
        ? OraColors.primary
        : OraColors.border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 48,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? OraColors.surfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(OraRadius.input),
        border: Border.all(color: border, width: 1.5),
        boxShadow: focused
            ? const [
                BoxShadow(
                  color: OraColors.primaryMuted,
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: Text(
        value,
        style: OraTypography.title(
          isDark ? OraColors.textPrimary : OraColors.textPrimaryLight,
        ),
      ),
    );
  }
}
