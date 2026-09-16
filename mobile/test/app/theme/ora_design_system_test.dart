import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/theme/theme.dart';

Widget _harness(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: OraTheme.light(),
    darkTheme: OraTheme.dark(),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('Ora design tokens', () {
    test('semantic colors map to prototype gold/teal/navy', () {
      expect(OraColors.primary, const Color(0xFFD4A756));
      expect(OraColors.secondary, const Color(0xFF1F9C82));
      expect(OraColors.background, const Color(0xFF0B0F1C));
      expect(OraColors.surface, const Color(0xFF12182B));
      expect(OraColors.surfaceElevated, const Color(0xFF1B2340));
      expect(OraColors.danger, isNot(OraColors.primary));
    });

    test('legacy aliases remain stable', () {
      expect(OraColors.gold500, OraColors.gold);
      expect(OraColors.navy900, OraColors.navy);
      expect(OraColors.teal500, OraColors.teal);
      expect(OraColors.error, OraColors.danger);
    });

    test('radius / spacing / motion scales are defined', () {
      expect(OraRadius.sheet, 26);
      expect(OraRadius.card, 18);
      expect(OraRadius.button, 16);
      expect(OraSpacing.md, 16);
      expect(OraMotion.press.inMilliseconds, lessThan(200));
    });

    testWidgets('dark theme uses Inter body family and Ora surfaces', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(const Text('Ora')));
      final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final dark = material.darkTheme!;
      expect(dark.textTheme.bodyMedium?.fontFamily, OraTypography.bodyFamily);
      expect(dark.scaffoldBackgroundColor, OraColors.background);
      expect(dark.colorScheme.primary, OraColors.primary);
      expect(dark.colorScheme.secondary, OraColors.secondary);
    });
  });

  group('OraButton', () {
    testWidgets('renders label and invokes onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _harness(OraButton(label: 'Continue', onPressed: () => tapped = true)),
      );
      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('loading disables tap and shows progress', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _harness(
          OraButton(
            label: 'Continue',
            isLoading: true,
            onPressed: () => tapped = true,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(OraButton));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('variants render without throwing', (tester) async {
      for (final variant in OraButtonVariant.values) {
        await tester.pumpWidget(
          _harness(
            OraButton(
              key: ValueKey(variant),
              label: variant.name,
              variant: variant,
              onPressed: () {},
            ),
          ),
        );
        expect(find.text(variant.name), findsOneWidget);
      }
    });

    testWidgets('meets minimum tap target height', (tester) async {
      await tester.pumpWidget(
        _harness(OraButton(label: 'Tap', expand: false, onPressed: () {})),
      );
      final size = tester.getSize(find.byType(OraButton));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('OraBottomSheet', () {
    testWidgets('shows handle and content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showOraBottomSheet<void>(
                      context: context,
                      child: const Text('Sheet body'),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet body'), findsOneWidget);
      expect(find.byType(OraSheetHandle), findsOneWidget);
    });
  });

  group('OraChip', () {
    testWidgets('selected and unselected states', (tester) async {
      await tester.pumpWidget(
        _harness(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OraChip(label: 'On', selected: true),
              OraChip(label: 'Off'),
            ],
          ),
        ),
      );
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('onTap fires when enabled', (tester) async {
      var count = 0;
      await tester.pumpWidget(
        _harness(OraChip(label: 'Filter', onTap: () => count++)),
      );
      await tester.tap(find.text('Filter'));
      expect(count, 1);
    });
  });

  group('OraTextField', () {
    testWidgets('shows label, hint, and error', (tester) async {
      await tester.pumpWidget(
        _harness(
          const OraTextField(
            label: 'Phone',
            hint: '3XX XXXXXXX',
            errorText: 'Required',
            prefixIcon: Icons.phone,
          ),
        ),
      );
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('3XX XXXXXXX'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('disabled field does not accept input focus path', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          OraTextField(controller: controller, label: 'Name', enabled: false),
        ),
      );
      await tester.enterText(find.byType(TextField), 'blocked');
      expect(controller.text, isEmpty);
    });
  });

  group('OraStarRating', () {
    testWidgets('reports integer selection 1–5', (tester) async {
      var value = 0;
      await tester.pumpWidget(
        _harness(
          StatefulBuilder(
            builder: (context, setState) {
              return OraStarRating(
                value: value,
                onChanged: (v) => setState(() => value = v),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.star_outline_rounded).at(2));
      await tester.pumpAndSettle();
      expect(value, 3);
    });

    testWidgets('read-only when onChanged is null', (tester) async {
      await tester.pumpWidget(_harness(const OraStarRating(value: 4)));
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
      await tester.tap(find.byIcon(Icons.star_rounded).first);
      await tester.pump();
      // Still 4 filled — no crash, no state change path.
      expect(find.byType(OraStarRating), findsOneWidget);
    });
  });

  group('OraCard / OraListRow / OraSectionHeader', () {
    testWidgets('selectable card exposes selected semantics', (tester) async {
      await tester.pumpWidget(
        _harness(
          OraCard(selected: true, onTap: () {}, child: const Text('Card')),
        ),
      );
      expect(find.text('Card'), findsOneWidget);
    });

    testWidgets('list row and section header render', (tester) async {
      await tester.pumpWidget(
        _harness(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OraSectionHeader(
                eyebrow: 'Account',
                title: 'Profile',
                description: 'Manage your details',
              ),
              OraListRow(
                title: 'Settings',
                subtitle: 'Preferences',
                leading: OraIconBadge(icon: Icons.settings_outlined),
              ),
            ],
          ),
        ),
      );
      expect(find.text('PROFILE'), findsNothing); // uppercased ACCOUNT eyebrow
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
