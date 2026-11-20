import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/di/providers.dart';
import '../../core/network/api_client.dart';
import '../../core/network/request_context.dart';

/// Shared ORA partner wallet — one points balance per UID, shared by every
/// approved partner role (driver / cargo / rental / service). 1 point = Rs 1.
///
/// Backend contract (auth-service `/v1/wallet`):
///   GET  /wallet               → { account, points, config, roles,
///                                  lowBalance, acceptBlocked }
///   GET  /wallet/transactions  → { entries: [WalletLedgerEntry] }
///   GET  /wallet/topups        → { topups: [WalletTopup] }
///   POST /wallet/topups        → { topup } — creates a PENDING request;
///                                points only credit after server-side
///                                payment verification (internal resolver).
enum PartnerWalletTxnKind { topUp, commission, withdrawal }

/// One ledger row — points are signed (+ top-up, − deduction).
class PartnerWalletTxn {
  const PartnerWalletTxn({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.points,
  });

  final String id;
  final PartnerWalletTxnKind kind;
  final String title;
  final String subtitle;
  final String timeLabel;
  final int points;

  factory PartnerWalletTxn.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final kind = switch (type) {
      'TOPUP_CREDIT' => PartnerWalletTxnKind.topUp,
      'WITHDRAWAL_DEBIT' => PartnerWalletTxnKind.withdrawal,
      'COMMISSION_DEBIT' => PartnerWalletTxnKind.commission,
      _ => (json['pointsDelta'] as num? ?? 0) >= 0
          ? PartnerWalletTxnKind.topUp
          : PartnerWalletTxnKind.withdrawal,
    };
    final role = json['role'] as String?;
    final sourceId = json['sourceId'] as String?;
    final title = switch (kind) {
      PartnerWalletTxnKind.topUp => 'Points Added',
      PartnerWalletTxnKind.commission => 'Commission Deducted',
      PartnerWalletTxnKind.withdrawal => 'Withdrawal',
    };
    final subtitle = switch (kind) {
      PartnerWalletTxnKind.topUp =>
        'via ${_methodLabel(json['paymentMethod'] as String?)} • Top-up',
      PartnerWalletTxnKind.commission =>
        '${_roleLabel(role)}${sourceId != null ? ' • #${_shortId(sourceId)}' : ''}',
      PartnerWalletTxnKind.withdrawal =>
        'via ${_methodLabel(json['paymentMethod'] as String?)}',
    };
    return PartnerWalletTxn(
      id: json['entryId'] as String? ?? '',
      kind: kind,
      title: title,
      subtitle: subtitle,
      timeLabel: _timeLabel(json['createdAt'] as String?),
      points: (json['pointsDelta'] as num? ?? 0).toInt(),
    );
  }

  static String _shortId(String id) =>
      id.length > 8 ? id.substring(id.length - 6).toUpperCase() : id;

  static String _roleLabel(String? role) => switch (role) {
    'driver' => 'Ride',
    'cargo' => 'Delivery',
    'rental' => 'Rental',
    'service' => 'Service',
    _ => 'Job',
  };

  static String _methodLabel(String? method) => switch (method) {
    'easypaisa' => 'Easypaisa',
    'jazzcash' => 'JazzCash',
    'bank_transfer' => 'Bank Transfer',
    _ => 'Wallet',
  };

  static String _timeLabel(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final now = DateTime.now();
    final day = switch (DateTime(t.year, t.month, t.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays) {
      0 => 'Today',
      -1 => 'Yesterday',
      _ => '${t.day}/${t.month}/${t.year}',
    };
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$day, $h:$m $ap';
  }
}

/// A top-up / withdrawal request — PENDING until the server verifies payment.
class WalletTopup {
  const WalletTopup({
    required this.topupId,
    required this.kind,
    required this.points,
    required this.method,
    required this.status,
    required this.createdAt,
  });

  final String topupId;
  final String kind; // 'credit' | 'debit'
  final int points;
  final String method;
  final String status; // PENDING | CREDITED | PAID | REJECTED
  final String createdAt;

  bool get isPending => status == 'PENDING';

  factory WalletTopup.fromJson(Map<String, dynamic> json) => WalletTopup(
    topupId: json['topupId'] as String? ?? '',
    kind: json['kind'] as String? ?? 'credit',
    points: (json['points'] as num? ?? 0).toInt(),
    method: json['method'] as String? ?? '',
    status: json['status'] as String? ?? 'PENDING',
    createdAt: json['createdAt'] as String? ?? '',
  );
}

/// Everything the shared wallet screen renders — balance, ledger, recharge
/// history, low-balance flags and the commission rates for the caller's
/// approved roles.
class PartnerWalletState {
  const PartnerWalletState({
    required this.balancePoints,
    required this.transactions,
    required this.topups,
    required this.roles,
    required this.commissionBps,
    required this.lowBalance,
    required this.acceptBlocked,
  });

  /// 1 point = Rs 1 (inDrive-style prepaid wallet).
  final int balancePoints;
  final List<PartnerWalletTxn> transactions;

  /// Recharge / withdrawal history, newest first.
  final List<WalletTopup> topups;

  /// Approved partner roles sharing this wallet — 'driver', 'cargo', …
  final List<String> roles;

  /// Commission basis points per role (1000 = 10%).
  final Map<String, int> commissionBps;

  /// Balance below the warn threshold (but not negative).
  final bool lowBalance;

  /// Negative balance — server blocks new accepts until recharged.
  final bool acceptBlocked;
}

/// Remote data source for `/v1/wallet`.
class PartnerWalletApi {
  const PartnerWalletApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> wallet({
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/wallet',
      context: context,
    );
    return response.data!;
  }

  Future<List<PartnerWalletTxn>> transactions({
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/wallet/transactions',
      queryParameters: {'limit': '50'},
      context: context,
    );
    return [
      for (final item
          in (response.data!['entries'] as List<dynamic>? ?? const []))
        PartnerWalletTxn.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<List<WalletTopup>> topups({required RequestContext context}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/wallet/topups',
      queryParameters: {'limit': '50'},
      context: context,
    );
    return [
      for (final item
          in (response.data!['topups'] as List<dynamic>? ?? const []))
        WalletTopup.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Creates a PENDING top-up (credit) or withdrawal (debit) request. Points
  /// move only after server-side verification — never on this call.
  Future<WalletTopup> createTopup({
    required int points,
    required String method,
    String kind = 'credit',
    String? reference,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/wallet/topups',
      data: {
        'kind': kind,
        'points': points,
        'method': method,
        if (reference != null && reference.isNotEmpty) 'reference': reference,
      },
      context: context,
      idempotent: true,
    );
    return WalletTopup.fromJson(response.data!['topup'] as Map<String, dynamic>);
  }
}

final partnerWalletApiProvider = Provider<PartnerWalletApi>(
  (ref) => PartnerWalletApi(ref.watch(apiClientProvider)),
);

String _newRequestId() => 'wk-${const Uuid().v4()}';

/// The signed-in partner's shared wallet — same balance across every
/// dashboard. autoDispose keeps balances fresh on each visit.
final partnerWalletProvider = FutureProvider.autoDispose<PartnerWalletState>((
  ref,
) async {
  final api = ref.watch(partnerWalletApiProvider);
  final client = ref.watch(apiClientProvider);
  final ctx = client.newContext();

  final wallet = await api.wallet(context: ctx);
  final transactions = await api.transactions(context: ctx);
  final topups = await api.topups(context: ctx);

  final config = (wallet['config'] as Map<String, dynamic>?) ?? const {};
  final bpsRaw = (config['commissionBps'] as Map<String, dynamic>?) ?? const {};
  return PartnerWalletState(
    balancePoints: (wallet['points'] as num? ?? 0).toInt(),
    transactions: transactions,
    topups: topups,
    roles: [
      for (final r in (wallet['roles'] as List<dynamic>? ?? const []))
        r.toString(),
    ],
    commissionBps: {
      for (final e in bpsRaw.entries) e.key: (e.value as num).toInt(),
    },
    lowBalance: wallet['lowBalance'] == true,
    acceptBlocked: wallet['acceptBlocked'] == true,
  );
});

/// Wallet mutations — every write goes through the server; the UI never
/// credits points locally.
final partnerWalletActionsProvider = Provider((ref) {
  final api = ref.watch(partnerWalletApiProvider);
  final client = ref.watch(apiClientProvider);

  Future<WalletTopup> requestTopup(int points, String method) async {
    final topup = await api.createTopup(
      points: points,
      method: method,
      context: client.newContext(idempotencyKey: _newRequestId()),
    );
    ref.invalidate(partnerWalletProvider);
    return topup;
  }

  Future<WalletTopup> requestWithdrawal(int points, String method) async {
    final topup = await api.createTopup(
      points: points,
      method: method,
      kind: 'debit',
      context: client.newContext(idempotencyKey: _newRequestId()),
    );
    ref.invalidate(partnerWalletProvider);
    return topup;
  }

  return (requestTopup: requestTopup, requestWithdrawal: requestWithdrawal);
});
