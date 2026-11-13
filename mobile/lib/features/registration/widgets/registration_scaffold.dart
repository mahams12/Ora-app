import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/ora_colors.dart';
import '../../../app/theme/ora_elevation.dart';
import '../../../app/theme/ora_radius.dart';
import '../../../app/theme/ora_spacing.dart';
import '../../../app/theme/ora_typography.dart';
import '../../../app/theme/widgets/widgets.dart';

/// Registration-flow scaffolding matching the partner-registration designs:
/// full-bleed module banner (back button + baked ORA branding) with a white
/// rounded sheet under it that hosts the form.
class OraRegistrationScaffold extends StatelessWidget {
  const OraRegistrationScaffold({
    required this.title,
    required this.subtitle,
    required this.heroAsset,
    required this.children,
    super.key,
    this.footer,
  });

  final String title;
  final String subtitle;
  final String heroAsset;
  final List<Widget> children;

  /// Optional widget rendered under the form (banner, submit, support row).
  final Widget? footer;

  /// Banner art is drawn 1024x342 — height tracks the view width so the
  /// whole picture is always visible (never cropped or zoomed).
  static const double _heroAspect = 342 / 1024;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final top = MediaQuery.of(context).padding.top;
              return SizedBox(
                height: top + constraints.maxWidth * _heroAspect,
                child: _RegistrationHeroHeader(
                  title: title,
                  subtitle: subtitle,
                  heroAsset: heroAsset,
                ),
              );
            },
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: OraColors.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x2A8A4A1E),
                    blurRadius: 30,
                    offset: Offset(0, -6),
                    spreadRadius: -10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    OraSpacing.md,
                    OraSpacing.lg,
                    OraSpacing.md,
                    OraSpacing.xl,
                  ),
                  children: [
                    ...children,
                    if (footer != null) footer!,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationHeroHeader extends StatelessWidget {
  const _RegistrationHeroHeader({
    required this.title,
    required this.subtitle,
    required this.heroAsset,
  });

  final String title;
  final String subtitle;
  final String heroAsset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The module banner is shown complete — no scrim, no crop.
        Semantics(
          image: true,
          label: '$title — $subtitle',
          child: Image.asset(heroAsset, fit: BoxFit.fill),
        ),
        const SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              OraSpacing.md,
              OraSpacing.xs,
              OraSpacing.md,
              0,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: _BackBubble(),
            ),
          ),
        ),
      ],
    );
  }
}

class _BackBubble extends StatelessWidget {
  const _BackBubble();

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: Semantics(
        button: true,
        label: 'Back',
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).maybePop();
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: OraColors.primaryForeground,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x332A211D),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: OraColors.textPrimary,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks a gallery photo for upload tiles; returns null when the picker is
/// unavailable (tests / missing plugin) or the user cancels.
Future<XFile?> pickRegPhoto() async {
  try {
    return await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
  } catch (_) {
    return null;
  }
}

/// Numbered section header — orange gradient badge + bold title.
class RegSection extends StatelessWidget {
  const RegSection({required this.title, super.key, this.number, this.icon});

  final String title;
  final int? number;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OraSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFA45E), OraColors.goldDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: OraColors.goldMuted,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                  spreadRadius: -3,
                ),
              ],
            ),
            child: icon != null
                ? Icon(icon, size: 15, color: OraColors.primaryForeground)
                : Text(
                    '${number ?? 0}',
                    style: OraTypography.label(
                      OraColors.primaryForeground,
                    ),
                  ),
          ),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: OraTypography.title(
                OraColors.textPrimary,
              ).copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// White input card matching the design: leading icon in a soft orange disc,
/// small muted label above the editable value, optional verified tick.
class RegFieldTile extends StatelessWidget {
  const RegFieldTile({
    required this.icon,
    required this.label,
    required this.controller,
    super.key,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.verified = false,
    this.errorText,
    this.fieldKey,
    this.onChanged,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool verified;
  final String? errorText;
  final Key? fieldKey;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: OraSpacing.sm,
            vertical: OraSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: OraColors.surface,
            borderRadius: BorderRadius.circular(OraRadius.input),
            border: errorText != null
                ? Border.all(color: OraColors.danger.withValues(alpha: 0.6))
                : null,
            boxShadow: OraElevation.cardShadow,
          ),
          child: Row(
            children: [
              _TileIcon(icon),
              const SizedBox(width: OraSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                    TextField(
                      key: fieldKey,
                      controller: controller,
                      keyboardType: keyboardType,
                      maxLines: maxLines,
                      textCapitalization: textCapitalization,
                      inputFormatters: inputFormatters,
                      onChanged: onChanged,
                      style: OraTypography.bodyEmphasis(
                        OraColors.textPrimary,
                      ),
                      cursorColor: OraColors.primary,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: hint,
                        hintStyle: OraTypography.body(
                          OraColors.textMuted.withValues(alpha: 0.7),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.only(top: 2),
                      ),
                    ),
                  ],
                ),
              ),
              if (verified)
                const Icon(
                  Icons.check_circle_rounded,
                  color: OraColors.success,
                  size: 18,
                ),
            ],
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(
              top: OraSpacing.xxs,
              left: OraSpacing.xs,
            ),
            child: Text(
              errorText!,
              style: OraTypography.caption(OraColors.danger),
            ),
          ),
      ],
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: OraColors.primaryMuted.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: OraColors.goldDeep),
    );
  }
}

/// White select card — same shell as [RegFieldTile] but tappable; shows the
/// current value and a dropdown chevron.
class RegDropdownTile extends StatelessWidget {
  const RegDropdownTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
    this.placeholder = 'Select',
    this.errorText,
    this.tileKey,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final String? errorText;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OraTapScale(
          child: GestureDetector(
            key: tileKey,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: OraSpacing.sm,
                vertical: OraSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: OraColors.surface,
                borderRadius: BorderRadius.circular(OraRadius.input),
                border: errorText != null
                    ? Border.all(
                        color: OraColors.danger.withValues(alpha: 0.6),
                      )
                    : null,
                boxShadow: OraElevation.cardShadow,
              ),
              child: Row(
                children: [
                  _TileIcon(icon),
                  const SizedBox(width: OraSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                        Text(
                          hasValue ? value! : placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: hasValue
                              ? OraTypography.bodyEmphasis(
                                  OraColors.textPrimary,
                                )
                              : OraTypography.body(
                                  OraColors.textMuted.withValues(alpha: 0.7),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: OraColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(
              top: OraSpacing.xxs,
              left: OraSpacing.xs,
            ),
            child: Text(
              errorText!,
              style: OraTypography.caption(OraColors.danger),
            ),
          ),
      ],
    );
  }
}

/// One selectable option inside [showRegOptions].
class RegOption {
  const RegOption(this.label, {this.icon, this.imageAsset, this.key});

  final String label;
  final IconData? icon;
  final String? imageAsset;
  final Key? key;
}

/// Styled bottom-sheet picker used by every [RegDropdownTile].
Future<String?> showRegOptions(
  BuildContext context, {
  required String title,
  required List<RegOption> options,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: OraColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OraSpacing.md,
          OraSpacing.sm,
          OraSpacing.md,
          OraSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: OraColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: OraSpacing.md),
            Text(title, style: OraTypography.title(OraColors.textPrimary)),
            const SizedBox(height: OraSpacing.sm),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option.label == selected;
                  return ListTile(
                    key: option.key,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: OraSpacing.sm,
                    ),
                    leading: option.imageAsset != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              option.imageAsset!,
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                            ),
                          )
                        : option.icon != null
                        ? _TileIcon(option.icon!)
                        : null,
                    title: Text(
                      option.label,
                      style: isSelected
                          ? OraTypography.bodyEmphasis(OraColors.goldDeep)
                          : OraTypography.body(OraColors.textPrimary),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: OraColors.gold,
                            size: 20,
                          )
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(OraRadius.input),
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(option.label),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Circular avatar upload — "Upload Photo (Clear Face)" per the designs.
class RegAvatarUpload extends StatelessWidget {
  const RegAvatarUpload({
    required this.photo,
    required this.onPick,
    super.key,
  });

  final XFile? photo;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OraTapScale(
          child: GestureDetector(
            onTap: onPick,
            child: SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: OraColors.primaryMuted.withValues(alpha: 0.4),
                      border: Border.all(
                        color: OraColors.border.withValues(alpha: 0.9),
                        width: 1.5,
                      ),
                      image: photo != null
                          ? DecorationImage(
                              image: FileImage(File(photo!.path)),
                              fit: BoxFit.cover,
                            )
                          : null,
                      boxShadow: OraElevation.cardShadow,
                    ),
                    child: photo == null
                        ? const Icon(
                            Icons.person_rounded,
                            size: 44,
                            color: OraColors.goldSoft,
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFA45E), OraColors.goldDeep],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: OraColors.goldMuted,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        size: 14,
                        color: OraColors.primaryForeground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: OraSpacing.xxs),
        Text(
          'Upload Photo',
          style: OraTypography.caption(OraColors.textPrimary),
        ),
        Text(
          '(Clear Face)',
          style: OraTypography.caption(OraColors.textMuted),
        ),
      ],
    );
  }
}

/// Document/photo upload card — thumbnail (or icon placeholder), title,
/// subtitle, and an orange gradient "Upload" pill.
class RegUploadTile extends StatelessWidget {
  const RegUploadTile({
    required this.title,
    required this.subtitle,
    required this.file,
    required this.onPick,
    super.key,
    this.icon = Icons.upload_file_rounded,
  });

  final String title;
  final String subtitle;
  final XFile? file;
  final VoidCallback onPick;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final picked = file != null;
    return Container(
      padding: const EdgeInsets.all(OraSpacing.sm),
      decoration: BoxDecoration(
        color: OraColors.surface,
        borderRadius: BorderRadius.circular(OraRadius.card),
        border: picked
            ? Border.all(color: OraColors.success.withValues(alpha: 0.5))
            : null,
        boxShadow: OraElevation.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(OraRadius.input),
            child: Container(
              height: 74,
              color: OraColors.primaryMuted.withValues(alpha: 0.3),
              child: picked
                  ? Image.file(File(file!.path), fit: BoxFit.cover)
                  : Icon(icon, size: 30, color: OraColors.goldSoft),
            ),
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OraTypography.label(OraColors.textPrimary),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.xs),
          OraTapScale(
            child: GestureDetector(
              onTap: onPick,
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFA45E), OraColors.goldDeep],
                  ),
                  borderRadius: BorderRadius.circular(OraRadius.pill),
                  boxShadow: OraElevation.primaryButtonShadow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      picked
                          ? Icons.check_circle_rounded
                          : Icons.photo_camera_rounded,
                      size: 15,
                      color: OraColors.primaryForeground,
                    ),
                    const SizedBox(width: OraSpacing.xxs),
                    Text(
                      picked ? 'Change' : 'Upload',
                      style: OraTypography.button(
                        OraColors.primaryForeground,
                      ).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable category chip card (Services "Service Categories" grid).
class RegCategoryChip extends StatelessWidget {
  const RegCategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(OraSpacing.xxs),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFFFA45E), OraColors.goldDeep],
                  )
                : null,
            color: selected ? null : OraColors.surface,
            borderRadius: BorderRadius.circular(OraRadius.input),
            border: Border.all(
              color: selected
                  ? OraColors.gold
                  : OraColors.border.withValues(alpha: 0.8),
            ),
            boxShadow: selected
                ? OraElevation.primaryButtonShadow
                : OraElevation.cardShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? OraColors.primaryForeground
                    : OraColors.goldDeep,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: OraTypography.caption(
                  selected
                      ? OraColors.primaryForeground
                      : OraColors.textPrimary,
                ).copyWith(fontWeight: FontWeight.w600, fontSize: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Peach trust banner — "Your information is safe and secure with ORA".
class RegInfoBanner extends StatelessWidget {
  const RegInfoBanner({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.md,
        vertical: OraSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: OraColors.primaryMuted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(OraRadius.pill),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.verified_user_rounded,
            size: 18,
            color: OraColors.goldDeep,
          ),
          const SizedBox(width: OraSpacing.xs),
          Flexible(
            child: Text(
              text ?? 'Your information is safe and secure with ORA',
              textAlign: TextAlign.center,
              style: OraTypography.caption(
                OraColors.textPrimary,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Need Help? Contact Support" footer row.
class RegSupportFooter extends StatelessWidget {
  const RegSupportFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.support_agent_rounded,
          size: 18,
          color: OraColors.goldDeep,
        ),
        const SizedBox(width: OraSpacing.xs),
        Text.rich(
          TextSpan(
            text: 'Need Help? ',
            style: OraTypography.body(OraColors.textMuted),
            children: [
              TextSpan(
                text: 'Contact Support',
                style: OraTypography.bodyEmphasis(OraColors.goldDeep),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two-up responsive row — fields sit side by side on wide layouts and
/// stack on narrow ones.
class RegRow extends StatelessWidget {
  const RegRow({required this.children, super.key, this.gap = OraSpacing.sm});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360 || children.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: children[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}
