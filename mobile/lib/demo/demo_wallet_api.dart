import '../core/network/request_context.dart';
import '../features/wallet/partner_wallet.dart';
import 'demo_session_store.dart';

/// DEMO/REVIEW BUILD ONLY — in-memory shared partner wallet.
///
/// Serves a simulated balance, ledger and recharge history for every
/// partner dashboard. Top-ups/withdrawals stay PENDING exactly like
/// production (never credited client-side) so the screens show the real
/// pending-verification UX. The DEMO banner marks all values as simulated.
class DemoPartnerWalletApi extends PartnerWalletApi {
  DemoPartnerWalletApi(super.apiClient, this._session);

  final DemoSessionStore _session;
  var _seeded = false;
  var _counter = 0;

  final int _points = 4800;
  final List<PartnerWalletTxn> _txns = [];
  final List<WalletTopup> _topups = [];

  String _ago(int h) =>
      DateTime.now().subtract(Duration(hours: h)).toUtc().toIso8601String();

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    _txns.addAll([
      PartnerWalletTxn.fromJson({
        'entryId': 'demo-txn-1',
        'type': 'TOPUP_CREDIT',
        'pointsDelta': 5000,
        'paymentMethod': 'easypaisa',
        'createdAt': _ago(6),
      }),
      PartnerWalletTxn.fromJson({
        'entryId': 'demo-txn-2',
        'type': 'COMMISSION_DEBIT',
        'pointsDelta': -120,
        'role': 'driver',
        'sourceId': 'ride-a1b2c3',
        'createdAt': _ago(4),
      }),
      PartnerWalletTxn.fromJson({
        'entryId': 'demo-txn-3',
        'type': 'COMMISSION_DEBIT',
        'pointsDelta': -80,
        'role': 'cargo',
        'sourceId': 'ride-d4e5f6',
        'createdAt': _ago(2),
      }),
    ]);
    _topups.add(
      WalletTopup.fromJson({
        'topupId': 'demo-top-1',
        'kind': 'credit',
        'points': 5000,
        'method': 'easypaisa',
        'status': 'CREDITED',
        'createdAt': _ago(6),
      }),
    );
  }

  List<String> get _roles {
    final p = _session.profile;
    if (p == null) return const ['driver'];
    return [
      if (p.isApprovedDriver) 'driver',
      for (final t in const ['cargo', 'rental', 'service'])
        if (p.isApprovedVendor(t)) t,
    ];
  }

  @override
  Future<Map<String, dynamic>> wallet({
    required RequestContext context,
  }) async {
    _seed();
    return {
      'points': _points,
      'roles': _roles.isEmpty ? const ['driver'] : _roles,
      'lowBalance': _points < 1000,
      'acceptBlocked': _points < 0,
      'config': {
        'commissionBps': {
          'driver': 1000,
          'cargo': 1000,
          'rental': 1000,
          'service': 1000,
        },
      },
    };
  }

  @override
  Future<List<PartnerWalletTxn>> transactions({
    required RequestContext context,
  }) async {
    _seed();
    return List.of(_txns);
  }

  @override
  Future<List<WalletTopup>> topups({
    required RequestContext context,
  }) async {
    _seed();
    return List.of(_topups);
  }

  /// Same contract as production: the request lands PENDING and points do
  /// NOT move — the screen shows "credits once payment is verified".
  @override
  Future<WalletTopup> createTopup({
    required int points,
    required String method,
    String kind = 'credit',
    String? reference,
    required RequestContext context,
  }) async {
    _seed();
    final topup = WalletTopup(
      topupId: 'demo-top-${++_counter}',
      kind: kind,
      points: points,
      method: method,
      status: 'PENDING',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    _topups.insert(0, topup);
    return topup;
  }
}
