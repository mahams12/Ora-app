import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../domain/entities/passenger_places.dart';
import '../../domain/passenger_places_policy.dart';

/// Saved-places rows for one location field (pickup or destination).
/// Each row applies instantly — zero network calls.
class SavedPlacesSection extends StatelessWidget {
  const SavedPlacesSection({
    required this.places,
    required this.onSelect,
    required this.onManage,
    super.key,
  });

  final List<SavedPlace> places;
  final ValueChanged<SavedPlace> onSelect;

  /// Opens the manage sheet for a place (rename/remove).
  final ValueChanged<SavedPlace> onManage;

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final place in places)
          OraListRow(
            title: place.name,
            subtitle: place.secondaryLabel,
            leading: Icon(
              place.id == kHomePlaceId
                  ? Icons.home_outlined
                  : place.id == kWorkPlaceId
                      ? Icons.work_outline
                      : Icons.star_outline,
              color: OraColors.primary,
              size: 20,
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: OraColors.textMuted,
              ),
              tooltip: 'Edit ${place.name}',
              onPressed: () => onManage(place),
            ),
            onTap: () => onSelect(place),
            showDivider: true,
          ),
      ],
    );
  }
}

/// Recent-destination rows — confirmed destinations only, most recent first.
class RecentDestinationsSection extends StatelessWidget {
  const RecentDestinationsSection({
    required this.recents,
    required this.onSelect,
    super.key,
  });

  final List<RecentDestination> recents;
  final ValueChanged<RecentDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    if (recents.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rec in recents)
          OraListRow(
            title: rec.displayLabel,
            leading: const Icon(
              Icons.history,
              color: OraColors.textMuted,
              size: 20,
            ),
            onTap: () => onSelect(rec),
            showDivider: true,
          ),
      ],
    );
  }
}

/// Bottom-sheet to save the current proposal/confirmed point as a place.
/// Returns `({String name, String? slotId})` — Home/Work fill the reserved
/// slots; anything else becomes a custom favorite.
typedef SavePlaceRequest = ({String name, String? slotId});

Future<SavePlaceRequest?> showSavePlaceSheet(BuildContext context) {
  return showOraBottomSheet<SavePlaceRequest>(
    context: context,
    child: const _SavePlaceSheet(),
  );
}

class _SavePlaceSheet extends StatefulWidget {
  const _SavePlaceSheet();

  @override
  State<_SavePlaceSheet> createState() => _SavePlaceSheetState();
}

class _SavePlaceSheetState extends State<_SavePlaceSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String name, [String? slotId]) {
    if (name.trim().isEmpty) return;
    Navigator.of(context).pop((name: name.trim(), slotId: slotId));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OraSectionHeader(
          eyebrow: 'Saved places',
          title: 'Save this place',
          description:
              'Save the selected point so you can reuse it next time.',
        ),
        const SizedBox(height: OraSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.home_outlined, size: 18),
                label: const Text('Home'),
                onPressed: () => _submit('Home', kHomePlaceId),
              ),
            ),
            const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.work_outline, size: 18),
                label: const Text('Work'),
                onPressed: () => _submit('Work', kWorkPlaceId),
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        OraTextField(
          controller: _controller,
          label: 'Custom name',
          hint: 'e.g. Gym, Ami\'s place',
          textCapitalization: TextCapitalization.words,
          onSubmitted: _submit,
        ),
        const SizedBox(height: OraSpacing.md),
        OraButton(
          label: 'Save place',
          onPressed: () => _submit(_controller.text),
        ),
      ],
    );
  }
}

/// Bottom-sheet to rename or remove an existing saved place.
/// Returns `('rename', newName)` or `('remove', '')`, else null.
typedef ManagePlaceRequest = ({String action, String name});

Future<ManagePlaceRequest?> showManagePlaceSheet(
  BuildContext context, {
  required SavedPlace place,
}) {
  return showOraBottomSheet<ManagePlaceRequest>(
    context: context,
    child: _ManagePlaceSheet(place: place),
  );
}

class _ManagePlaceSheet extends StatefulWidget {
  const _ManagePlaceSheet({required this.place});

  final SavedPlace place;

  @override
  State<_ManagePlaceSheet> createState() => _ManagePlaceSheetState();
}

class _ManagePlaceSheetState extends State<_ManagePlaceSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.place.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReserved = widget.place.id == kHomePlaceId ||
        widget.place.id == kWorkPlaceId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OraSectionHeader(
          eyebrow: 'Saved places',
          title: 'Edit ${widget.place.name}',
          description: isReserved
              ? 'Rename this slot — its saved point stays the same.'
              : 'Rename or remove this saved place.',
        ),
        const SizedBox(height: OraSpacing.md),
        OraTextField(
          controller: _controller,
          label: 'Name',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: OraSpacing.md),
        OraButton(
          label: 'Rename',
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context)
                .pop((action: 'rename', name: name));
          },
        ),
        const SizedBox(height: OraSpacing.sm),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline, color: OraColors.danger),
          label: const Text(
            'Remove place',
            style: TextStyle(color: OraColors.danger),
          ),
          onPressed: () =>
              Navigator.of(context).pop((action: 'remove', name: '')),
        ),
      ],
    );
  }
}
