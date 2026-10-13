import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_assets.dart';
import 'ride_card_avatar.dart';
import 'ride_card_model.dart';

/// Participant row — always keeps epic layout slots.
///
/// Missing photo/name/rating → empty avatar asset + reserved blank space.
/// Never invents names, ratings, or trip counts.
class RideCardParticipantRow extends StatelessWidget {
  const RideCardParticipantRow({
    super.key,
    this.participant,
    this.trailing,
    this.compact = false,
    this.showRatingSlot = true,
    this.showPhoneSlot = false,
    this.showChatSlot = false,
    this.onCall,
    this.onChat,
  });

  final RideCardParticipant? participant;
  final Widget? trailing;
  final bool compact;
  final bool showRatingSlot;
  final bool showPhoneSlot;
  final bool showChatSlot;
  final VoidCallback? onCall;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final avatarSize = compact ? 40.0 : 48.0;
    final hasName = p != null &&
        p.displayName != null &&
        p.displayName!.trim().isNotEmpty;

    return Row(
      children: [
        _Avatar(
          participant: p,
          size: avatarSize,
          showVerified: p?.verified == true,
        ),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: compact ? 18 : 20,
                child: hasName
                    ? Text(
                        p.displayName!.trim(),
                        style:
                            OraTypography.bodyEmphasis(OraColors.textPrimary)
                                .copyWith(fontSize: compact ? 14 : 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const SizedBox.shrink(),
              ),
              if (showRatingSlot) ...[
                const SizedBox(height: 2),
                _RatingSlot(participant: p),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (showPhoneSlot || showChatSlot) ...[
          if (showPhoneSlot)
            RideCardIconButton(
              assetPath: RideCardAssets.phone,
              semanticLabel: 'Call',
              onPressed: onCall,
            ),
          if (showChatSlot) ...[
            const SizedBox(width: OraSpacing.xs),
            RideCardIconButton(
              icon: Icons.chat_bubble_outline_rounded,
              semanticLabel: 'Chat',
              onPressed: onChat,
            ),
          ],
        ],
      ],
    );
  }
}

class _RatingSlot extends StatelessWidget {
  const _RatingSlot({this.participant});

  final RideCardParticipant? participant;

  @override
  Widget build(BuildContext context) {
    final rating = participant?.rating;
    final trips = participant?.tripCount;

    return SizedBox(
      height: 16,
      child: Row(
        children: [
          // No bundled star PNG (asset was a parcel). Flutter gold star.
          Opacity(
            opacity: rating == null ? 0.35 : 1,
            child: const Icon(
              Icons.star_rounded,
              size: 14,
              color: OraColors.gold,
            ),
          ),
          const SizedBox(width: 2),
          if (rating != null)
            Text(
              rating.toStringAsFixed(1),
              style: OraTypography.caption(OraColors.textSecondary),
            ),
          if (rating != null && trips != null)
            Text(
              ' ($trips ${trips == 1 ? 'ride' : 'rides'})',
              style: OraTypography.caption(OraColors.textMuted),
            )
          else if (trips != null)
            Text(
              '($trips ${trips == 1 ? 'ride' : 'rides'})',
              style: OraTypography.caption(OraColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class RideCardIconButton extends StatelessWidget {
  const RideCardIconButton({
    super.key,
    this.icon,
    this.assetPath,
    this.onPressed,
    this.semanticLabel,
  }) : assert(icon != null || assetPath != null);

  final IconData? icon;
  final String? assetPath;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onPressed != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(OraRadius.pill),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF151C2E),
              border: Border.all(color: OraColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
              child: Opacity(
              opacity: onPressed == null ? 0.45 : 1,
              child: assetPath != null
                  ? RideCardAssetImage(
                      assetPath: assetPath!,
                      width: 20,
                      height: 20,
                    )
                  : Icon(icon, size: 18, color: OraColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.size,
    required this.showVerified,
    this.participant,
  });

  final RideCardParticipant? participant;
  final double size;
  final bool showVerified;

  @override
  Widget build(BuildContext context) {
    final url = participant?.photoUrl?.trim();
    final hasPhoto = url != null && url.isNotEmpty;

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: OraColors.info.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: OraColors.info.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _EmptyAvatar(size: size),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return _EmptyAvatar(size: size);
              },
            )
          : _EmptyAvatar(size: size),
    );

    if (!showVerified) return avatar;

    return SizedBox(
      width: size + 2,
      height: size + 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          const Positioned(
            right: -2,
            bottom: -2,
            child: RideCardAssetImage(
              assetPath: RideCardAssets.shieldCheck,
              width: 18,
              height: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAvatar extends StatelessWidget {
  const _EmptyAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return RideCardAvatarPlaceholder(size: size);
  }
}
