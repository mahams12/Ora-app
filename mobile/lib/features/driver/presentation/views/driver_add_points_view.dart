import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_floaty.dart' show OraTapScale;
import '../../../wallet/partner_wallet.dart';
import 'driver_wallet_view.dart' show WalletHeroTop;

const _quickAmounts = [500, 1000, 2000, 5000];

const _methods = [
  (
    id: 'Easypaisa',
    key: 'easypaisa',
    icon: Icons.account_balance_wallet_rounded,
  ),
  (id: 'JazzCash', key: 'jazzcash', icon: Icons.payments_rounded),
  (
    id: 'Bank Transfer',
    key: 'bank_transfer',
    icon: Icons.account_balance_rounded,
  ),
];

/// Add Points — top up the vendor wallet (1 pt = Rs 1). Amount field,
/// quick chips, payment-method radio list and a live top-up summary,
/// matching the supplied mockup.
class DriverAddPointsView extends ConsumerStatefulWidget {
  const DriverAddPointsView({
    super.key,
    this.walletRoute = AppRoutes.driverWallet,
  });

  /// Fallback route when nothing is on the stack — logistics partners pass
  /// their own shell-scoped wallet path.
  final String walletRoute;

  @override
  ConsumerState<DriverAddPointsView> createState() =>
      _DriverAddPointsViewState();
}

class _DriverAddPointsViewState extends ConsumerState<DriverAddPointsView> {
  final _amountController = TextEditingController(text: '2,000');
  int _amount = 2000;
  String _method = 'Easypaisa';

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  static String _fmt(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  void _setAmount(int v) {
    setState(() {
      _amount = v;
      _amountController.text = v > 0 ? _fmt(v) : '';
    });
  }

  void _onAmountChanged(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final v = int.tryParse(digits) ?? 0;
    setState(() {
      _amount = v;
      if (digits.isNotEmpty && raw != _fmt(v)) {
        _amountController.value = TextEditingValue(
          text: _fmt(v),
          selection: TextSelection.collapsed(offset: _fmt(v).length),
        );
      }
    });
  }

  bool _submitting = false;

  /// Creates a PENDING top-up on the server — points credit only after
  /// payment verification, never on this button press.
  Future<void> _submit() async {
    if (_amount <= 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      final methodKey = _methods
          .firstWhere((m) => m.id == _method)
          .key;
      await ref
          .read(partnerWalletActionsProvider)
          .requestTopup(_amount, methodKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Top-up request sent — points credit once payment is verified.',
          ),
        ),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(widget.walletRoute);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not send the top-up request. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBEFE4),
      body: Column(
        children: [
          WalletHeroTop(
            art: 'assets/driver_tiles/add_points_hero.png',
            aspect: 512.0 / 1024.0,
            topStrip: const [Color(0xFFFD6707), Color(0xFFF05804)],
            onBack: () =>
                context.canPop() ? context.pop() : context.go(widget.walletRoute),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                OraSpacing.md,
                OraSpacing.sm,
                OraSpacing.md,
                40,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(OraSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9F3),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: OraElevation.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Enter Amount',
                        style: OraTypography.label(
                          OraColors.textPrimary,
                        ).copyWith(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: OraSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: OraColors.onPhoto,
                          borderRadius: BorderRadius.circular(OraRadius.input),
                          border: Border.all(color: const Color(0xFFEFD9C6)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _amountController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9,]'),
                                  ),
                                ],
                                onChanged: _onAmountChanged,
                                style: OraTypography.title(
                                  OraColors.textPrimary,
                                ).copyWith(fontSize: 20),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 24,
                              color: const Color(0xFFEFD9C6),
                            ),
                            const SizedBox(width: OraSpacing.xs),
                            Text(
                              'Points',
                              style: OraTypography.caption(
                                OraColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OraSpacing.sm),
                      Row(
                        children: [
                          for (final amount in _quickAmounts) ...[
                            Expanded(
                              child: OraTapScale(
                                child: GestureDetector(
                                  onTap: () => _setAmount(amount),
                                  child: AnimatedContainer(
                                    duration: const Duration(
                                      milliseconds: 160,
                                    ),
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _amount == amount
                                          ? OraColors.goldSharp
                                          : OraColors.onPhoto,
                                      borderRadius: BorderRadius.circular(
                                        OraRadius.pill,
                                      ),
                                      border: Border.all(
                                        color: _amount == amount
                                            ? OraColors.goldSharp
                                            : const Color(0xFFEFD9C6),
                                      ),
                                      boxShadow: _amount == amount
                                          ? const [
                                              BoxShadow(
                                                color: Color(0x59FF6A0D),
                                                blurRadius: 12,
                                                offset: Offset(0, 4),
                                                spreadRadius: -4,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Text(
                                      _fmt(amount),
                                      style: OraTypography.caption(
                                        _amount == amount
                                            ? OraColors.primaryForeground
                                            : OraColors.textPrimary,
                                      ).copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (amount != _quickAmounts.last)
                              const SizedBox(width: OraSpacing.xs),
                          ],
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      Text(
                        'Payment Method',
                        style: OraTypography.label(
                          OraColors.textPrimary,
                        ).copyWith(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      Container(
                        decoration: BoxDecoration(
                          color: OraColors.onPhoto,
                          borderRadius: BorderRadius.circular(OraRadius.input),
                          border: Border.all(color: const Color(0xFFEFD9C6)),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < _methods.length; i++) ...[
                              _MethodRow(
                                label: _methods[i].id,
                                icon: _methods[i].icon,
                                selected: _method == _methods[i].id,
                                onTap: () =>
                                    setState(() => _method = _methods[i].id),
                              ),
                              const Divider(
                                height: 1,
                                indent: 52,
                                color: Color(0xFFF3E2D2),
                              ),
                            ],
                            _MethodRow(
                              label: 'Other Methods',
                              icon: Icons.credit_card_rounded,
                              selected: false,
                              chevron: true,
                              onTap: () {},
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OraSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(OraSpacing.md),
                        decoration: BoxDecoration(
                          color: OraColors.onPhoto,
                          borderRadius: BorderRadius.circular(OraRadius.input),
                          border: Border.all(color: const Color(0xFFEFD9C6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.stacked_bar_chart_rounded,
                                  size: 18,
                                  color: OraColors.goldDeep,
                                ),
                                const SizedBox(width: OraSpacing.xs),
                                Text(
                                  'Top-up Summary',
                                  style: OraTypography.label(
                                    OraColors.textPrimary,
                                  ).copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            _summaryRow(
                              'Amount (Points)',
                              _fmt(_amount),
                            ),
                            const SizedBox(height: OraSpacing.xxs),
                            _summaryRow(
                              'Equivalent Value',
                              'Rs ${_fmt(_amount)}',
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: OraSpacing.xs,
                              ),
                              child: Divider(
                                height: 1,
                                color: Color(0xFFF3E2D2),
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Total Payable',
                                    style: OraTypography.label(
                                      OraColors.textPrimary,
                                    ).copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  'Rs ${_fmt(_amount)}',
                                  style: OraTypography.title(
                                    OraColors.goldSharp,
                                  ).copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OraSpacing.lg),
                OraTapScale(
                  child: GestureDetector(
                    onTap: _amount > 0 && !_submitting ? _submit : null,
                    child: Opacity(
                      opacity: _amount > 0 && !_submitting ? 1 : 0.55,
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(OraRadius.pill),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFA45E), OraColors.goldSharp],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x59FF6A0D),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Add ${_fmt(_amount)} Points',
                              style: OraTypography.label(
                                OraColors.primaryForeground,
                              ).copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: OraSpacing.xs),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: OraColors.primaryForeground,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: OraTypography.caption(OraColors.textMuted),
        ),
      ),
      Text(value, style: OraTypography.body(OraColors.textPrimary)),
    ],
  );
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.chevron = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OraSpacing.sm,
            vertical: OraSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: OraColors.textPrimary),
              const SizedBox(width: OraSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: OraTypography.body(
                    OraColors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (chevron)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: OraColors.textMuted,
                )
              else
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? OraColors.goldSharp : OraColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
