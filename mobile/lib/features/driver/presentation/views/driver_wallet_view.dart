import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../wallet/partner_wallet.dart';

/// Partner Wallet — inDrive-style points wallet shared by every approved
/// role (driver, cargo, rental, service). Partners top up points
/// (1 pt = Rs 1) and commissions deduct on verified completion only.
class DriverWalletView extends ConsumerStatefulWidget {
  const DriverWalletView({
    super.key,
    this.homeRoute = AppRoutes.driverHome,
    this.addPointsRoute = AppRoutes.driverWalletAddPoints,
  });

  /// Routes — every partner shell reuses this shared wallet under its own
  /// scoped paths.
  final String homeRoute;
  final String addPointsRoute;

  @override
  ConsumerState<DriverWalletView> createState() => _DriverWalletViewState();
}

class _DriverWalletViewState extends ConsumerState<DriverWalletView> {
  bool _balanceVisible = true;

  static String _fmt(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return v < 0 ? '-$b' : b.toString();
  }

  Future<void> _requestWithdrawal(int amount) async {
    try {
      await ref
          .read(partnerWalletActionsProvider)
          .requestWithdrawal(amount, 'easypaisa');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Withdrawal request sent — paid out after review.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send the withdrawal request.'),
        ),
      );
    }
  }

  Future<void> _showWithdrawSheet() async {
    final wallet = ref.read(partnerWalletProvider).valueOrNull;
    if (wallet == null) return;
    final controller = TextEditingController();
    int amount = 0;
    await showOraBottomSheet<void>(
      context: context,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OraSectionHeader(
                eyebrow: 'Vendor Wallet',
                title: 'Withdraw points',
                description: 'Move points back to your Easypaisa account.',
              ),
              const SizedBox(height: OraSpacing.md),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                onChanged: (v) => setSheetState(
                  () => amount = int.tryParse(v.replaceAll(',', '')) ?? 0,
                ),
                decoration: InputDecoration(
                  hintText: 'Amount in points',
                  filled: true,
                  fillColor: OraColors.onPhoto,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(OraRadius.input),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: OraSpacing.xs),
              Text(
                'Available: ${_fmt(wallet.balancePoints)} points '
                '(≈ Rs ${_fmt(wallet.balancePoints)})',
                style: OraTypography.caption(OraColors.textMuted),
              ),
              const SizedBox(height: OraSpacing.lg),
              OraButton(
                label: 'Withdraw',
                onPressed: amount > 0 && amount <= wallet.balancePoints
                    ? () {
                        Navigator.of(context).pop();
                        _requestWithdrawal(amount);
                      }
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  static String _pct(int? bps) {
    if (bps == null) return '—';
    final v = bps / 100;
    return '${v == v.roundToDouble() ? v.toInt() : v}%';
  }

  static const _roleLabels = {
    'driver': 'Ride commission',
    'cargo': 'Delivery & cargo',
    'rental': 'Rental commission',
    'service': 'Service commission',
  };

  Future<void> _showCommissionSheet(PartnerWalletState wallet) {
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: OraSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: OraTypography.body(OraColors.textSecondary)),
          ),
          Text(
            value,
            style: OraTypography.bodyEmphasis(OraColors.textPrimary),
          ),
        ],
      ),
    );
    return showOraBottomSheet<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OraSectionHeader(
            eyebrow: 'Partner Wallet',
            title: 'Commission overview',
            description:
                'ORA deducts its commission in points each time a job '
                'completes — the deduction shows in Recent Transactions.',
          ),
          const SizedBox(height: OraSpacing.md),
          for (final role in wallet.roles)
            row(
              _roleLabels[role] ?? 'Commission',
              _pct(wallet.commissionBps[role]),
            ),
          if (wallet.roles.isEmpty)
            row('Commission', _pct(wallet.commissionBps['service'])),
          row('Deduction', 'Per completed job, in points'),
          const SizedBox(height: OraSpacing.lg),
          OraButton(
            label: 'Got it',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(partnerWalletProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFFBEFE4),
      body: Column(
        children: [
          WalletHeroTop(
            art: 'assets/driver_tiles/wallet_hero.png',
            onBack: () =>
                context.canPop() ? context.pop() : context.go(widget.homeRoute),
          ),
          Expanded(
            child: walletAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: OraColors.gold),
              ),
              error: (_, __) => _WalletErrorCard(
                onRetry: () => ref.invalidate(partnerWalletProvider),
              ),
              data: (wallet) => _buildBody(context, wallet),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, PartnerWalletState wallet) {
    return RefreshIndicator(
      color: OraColors.gold,
      onRefresh: () async => ref.invalidate(partnerWalletProvider),
      child: ListView(
              padding: const EdgeInsets.fromLTRB(
                OraSpacing.md,
                OraSpacing.sm,
                OraSpacing.md,
                40,
              ),
              children: [
                if (wallet.acceptBlocked)
                  const _BalanceWarningCard.blocked()
                else if (wallet.lowBalance)
                  const _BalanceWarningCard.low(),
                Container(
                  padding: const EdgeInsets.all(OraSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9F3),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: OraElevation.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFE3BF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.stacked_bar_chart_rounded,
                              size: 22,
                              color: OraColors.goldDeep,
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Available Balance (Points)',
                                  style: OraTypography.caption(
                                    OraColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _balanceVisible
                                      ? '${_fmt(wallet.balancePoints)} Points'
                                      : '•••• Points',
                                  style: OraTypography.headline(
                                    OraColors.textPrimary,
                                  ).copyWith(fontSize: 22),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '≈ Rs ${_fmt(wallet.balancePoints)}',
                                  style: OraTypography.caption(
                                    OraColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OraTapScale(
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _balanceVisible = !_balanceVisible,
                              ),
                              child: Icon(
                                _balanceVisible
                                    ? Icons.remove_red_eye_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                                color: OraColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: OraTapScale(
                              child: GestureDetector(
                                onTap: () => context.push(
                                  widget.addPointsRoute,
                                ),
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      OraRadius.pill,
                                    ),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFFA45E),
                                        OraColors.goldSharp,
                                      ],
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x59FF6A0D),
                                        blurRadius: 14,
                                        offset: Offset(0, 5),
                                        spreadRadius: -4,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.add_rounded,
                                        size: 18,
                                        color: OraColors.primaryForeground,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Add Points',
                                        style: OraTypography.label(
                                          OraColors.primaryForeground,
                                        ).copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: OraTapScale(
                              child: GestureDetector(
                                onTap: _showWithdrawSheet,
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: OraColors.onPhoto,
                                    borderRadius: BorderRadius.circular(
                                      OraRadius.pill,
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFEFD9C6),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.account_balance_rounded,
                                        size: 16,
                                        color: OraColors.gold,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Withdraw',
                                        style: OraTypography.label(
                                          OraColors.goldDeep,
                                        ).copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OraSpacing.md),
                OraTapScale(
                  child: GestureDetector(
                    onTap: () => _showCommissionSheet(wallet),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OraSpacing.md,
                        vertical: OraSpacing.sm + 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9F3),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: OraElevation.cardShadow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFE3BF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.percent_rounded,
                              size: 18,
                              color: OraColors.goldDeep,
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Commission Overview',
                                  style: OraTypography.label(
                                    OraColors.textPrimary,
                                  ).copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  'Set commission, view deductions and rates',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: OraTypography.caption(
                                    OraColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: OraColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: OraSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent Transactions',
                        style: OraTypography.label(
                          OraColors.textPrimary,
                        ).copyWith(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                    OraTapScale(
                      child: GestureDetector(
                        onTap: () {},
                        child: Text(
                          'View All',
                          style: OraTypography.caption(
                            OraColors.goldDeep,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OraSpacing.xs),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9F3),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: OraElevation.cardShadow,
                  ),
                  child: wallet.transactions.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(OraSpacing.lg),
                          child: Text(
                            'No transactions yet',
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0;
                                i < wallet.transactions.length;
                                i++) ...[
                              _TxnRow(
                                txn: wallet.transactions[i],
                                fmt: _fmt,
                              ),
                              if (i != wallet.transactions.length - 1)
                                const Divider(
                                  height: 1,
                                  indent: 60,
                                  color: Color(0xFFF3E2D2),
                                ),
                            ],
                          ],
                        ),
                ),
                if (wallet.topups.isNotEmpty) ...[
                  const SizedBox(height: OraSpacing.md),
                  Text(
                    'Recharge History',
                    style: OraTypography.label(
                      OraColors.textPrimary,
                    ).copyWith(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9F3),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: OraElevation.cardShadow,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < wallet.topups.length; i++) ...[
                          _TopupRow(topup: wallet.topups[i], fmt: _fmt),
                          if (i != wallet.topups.length - 1)
                            const Divider(
                              height: 1,
                              indent: 60,
                              color: Color(0xFFF3E2D2),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.txn, required this.fmt});

  final PartnerWalletTxn txn;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    final positive = txn.points > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.md,
        vertical: OraSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: positive
                  ? const Color(0xFFDFF3E4)
                  : const Color(0xFFFFE3BF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              switch (txn.kind) {
                PartnerWalletTxnKind.topUp => Icons.add_rounded,
                PartnerWalletTxnKind.commission => Icons.percent_rounded,
                PartnerWalletTxnKind.withdrawal =>
                  Icons.account_balance_rounded,
              },
              size: 18,
              color:
                  positive ? OraColors.success : OraColors.goldDeep,
            ),
          ),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.label(
                    OraColors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  txn.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${positive ? '+' : ''}${fmt(txn.points)}',
                style: OraTypography.label(
                  positive ? OraColors.success : OraColors.goldDeep,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                txn.timeLabel,
                style: OraTypography.caption(
                  OraColors.textMuted,
                ).copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared full-bleed hero for the wallet screens — the supplied banner
/// artwork rendered edge-to-edge (title, subtitle and ORA mark are part
/// of the art) below a status-bar strip in the art's own top-edge colours,
/// with the bottom fading into the page like the vendor heroes.
class WalletHeroTop extends StatelessWidget {
  const WalletHeroTop({
    required this.art,
    this.aspect = 394.0 / 1024.0,
    this.topStrip = const [Color(0xFFD04004), Color(0xFFE7580A)],
    this.onBack,
    super.key,
  });

  final String art;
  final double aspect;

  /// Colour(s) continuing the artwork's top edge across the status-bar
  /// strip so the art reads as one continuous surface.
  final List<Color> topStrip;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).padding.top;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = w * aspect;
        return SizedBox(
          height: h + inset,
          width: w,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: inset,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: topStrip.length == 1
                          ? [topStrip.first, topStrip.first]
                          : topStrip,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: inset,
                left: 0,
                right: 0,
                height: h,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.88, 1.0],
                  ).createShader(rect),
                  child: Image.asset(
                    art,
                    fit: BoxFit.fitWidth,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              Positioned(
                top: inset + OraSpacing.xs,
                left: OraSpacing.sm,
                child: OraTapScale(
                  child: GestureDetector(
                    onTap: onBack,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


/// Low-balance / blocked banner — matches the server's policy: a negative
/// balance blocks new accepts until the partner tops up.
class _BalanceWarningCard extends StatelessWidget {
  const _BalanceWarningCard.blocked()
    : _blocked = true;

  const _BalanceWarningCard.low() : _blocked = false;

  final bool _blocked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OraSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: OraSpacing.md,
          vertical: OraSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: _blocked
              ? const Color(0xFFFFE9E4)
              : const Color(0xFFFFF3D9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _blocked
                ? const Color(0xFFF5B8A8)
                : const Color(0xFFF3D9A8),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _blocked
                  ? Icons.error_outline_rounded
                  : Icons.warning_amber_rounded,
              size: 20,
              color: _blocked
                  ? const Color(0xFFC6402A)
                  : OraColors.goldDeep,
            ),
            const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: Text(
                _blocked
                    ? 'Balance is negative — you cannot accept new jobs '
                        'until you top up.'
                    : 'Low balance — top up soon to keep accepting jobs.',
                style: OraTypography.caption(
                  _blocked
                      ? const Color(0xFFC6402A)
                      : OraColors.textPrimary,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletErrorCard extends StatelessWidget {
  const _WalletErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OraSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: OraColors.gold,
            ),
            const SizedBox(height: OraSpacing.sm),
            Text(
              'Could not load your wallet',
              style: OraTypography.bodyEmphasis(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.sm),
            OraButton(label: 'Retry', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// One recharge / withdrawal request row with a status pill
/// (PENDING / CREDITED / PAID / REJECTED).
class _TopupRow extends StatelessWidget {
  const _TopupRow({required this.topup, required this.fmt});

  final WalletTopup topup;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    final credit = topup.kind == 'credit';
    final statusColor = switch (topup.status) {
      'CREDITED' || 'PAID' => OraColors.success,
      'REJECTED' => const Color(0xFFC6402A),
      _ => OraColors.goldDeep,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.md,
        vertical: OraSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFFFE3BF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              credit ? Icons.add_rounded : Icons.account_balance_rounded,
              size: 18,
              color: OraColors.goldDeep,
            ),
          ),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credit ? 'Top-up request' : 'Withdrawal request',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.label(
                    OraColors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${fmt(topup.points)} pts • ${topup.method}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(OraRadius.pill),
            ),
            child: Text(
              topup.status,
              style: OraTypography.caption(
                statusColor,
              ).copyWith(fontWeight: FontWeight.w800, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
