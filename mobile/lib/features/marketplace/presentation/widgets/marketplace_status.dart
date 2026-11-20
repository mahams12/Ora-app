import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';

/// Status pill colours/labels shared by vendor listing cards, the vendor
/// inbox and the customer booking history.
(String label, Color bg, Color fg) listingStatusStyle(String status) =>
    switch (status) {
      'published' => (
        'LIVE',
        OraColors.successSurface,
        OraColors.successForeground,
      ),
      'paused' => (
        'PAUSED',
        OraColors.warningSurface,
        OraColors.warningForeground,
      ),
      'draft' => ('DRAFT', OraColors.surfaceElevated, OraColors.textSecondary),
      _ => (
        status.toUpperCase(),
        OraColors.surfaceElevated,
        OraColors.textSecondary,
      ),
    };

(String label, Color bg, Color fg) bookingStatusStyle(String status) =>
    switch (status) {
      'requested' => ('NEW REQUEST', OraColors.infoMuted, OraColors.info),
      'quoted' => (
        'QUOTE SENT',
        OraColors.warningSurface,
        OraColors.warningForeground,
      ),
      'confirmed' => (
        'CONFIRMED',
        OraColors.successSurface,
        OraColors.successForeground,
      ),
      'in_progress' => ('IN PROGRESS', OraColors.infoMuted, OraColors.info),
      'completed' => (
        'COMPLETED',
        OraColors.surfaceElevated,
        OraColors.textSecondary,
      ),
      'rejected' => ('DECLINED', OraColors.errorSurface, OraColors.error),
      'cancelled' => (
        'CANCELLED',
        OraColors.surfaceElevated,
        OraColors.textMuted,
      ),
      _ => (
        status.toUpperCase(),
        OraColors.surfaceElevated,
        OraColors.textSecondary,
      ),
    };

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, this.booking = false, super.key});

  final String status;
  final bool booking;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = booking
        ? bookingStatusStyle(status)
        : listingStatusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(OraRadius.pill),
      ),
      child: Text(
        label,
        style: OraTypography.caption(
          fg,
        ).copyWith(fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}
