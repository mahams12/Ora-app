import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_model.dart';

/// Participant row — only renders real fields; omits missing photo/rating/count.
class RideCardParticipantRow extends StatelessWidget {
  const RideCardParticipantRow({
    required this.participant,
    super.key,
  });

  final RideCardParticipant participant;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Avatar(participant: participant),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                participant.resolvedName,
                style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (participant.hasStats) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (participant.rating != null) ...[
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: OraColors.info,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        participant.rating!.toStringAsFixed(1),
                        style: OraTypography.caption(OraColors.textSecondary),
                      ),
                    ],
                    if (participant.rating != null &&
                        participant.tripCount != null)
                      Text(
                        '  ·  ',
                        style: OraTypography.caption(OraColors.textMuted),
                      ),
                    if (participant.tripCount != null)
                      Text(
                        '${participant.tripCount} '
                        '${participant.tripCount == 1 ? 'ride' : 'rides'}',
                        style: OraTypography.caption(OraColors.textMuted),
                      ),
                  ],
                ),
              ] else if (participant.hasIdentity) ...[
                // Only show role caption when a real display name is present.
                const SizedBox(height: 2),
                Text(
                  participant.roleLabel,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.participant});

  final RideCardParticipant participant;

  @override
  Widget build(BuildContext context) {
    final url = participant.photoUrl?.trim();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF243056), Color(0xFF152040)],
        ),
        border: Border.all(
          color: OraColors.info.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: OraColors.info.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _Initials(participant.initials),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return _Initials(participant.initials);
              },
            )
          : _Initials(participant.initials),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: OraTypography.label(OraColors.info),
      ),
    );
  }
}
