import 'dart:convert';

import '../core/storage/secure_storage.dart';
import '../features/auth/domain/entities/auth_user.dart';
import '../features/auth/domain/entities/user_profile.dart';

/// Local demo-account store — review builds only.
///
/// Persists one demo session (`AuthUser` + canonical [UserProfile]) in
/// secure storage so a cold restart restores the same demo account, exactly
/// like the production session restore. Never written to Firebase or the
/// API — this object is the entire "backend" for the demo build.
///
/// Reached only from `lib/main_demo.dart` provider overrides; unreachable
/// from the production entrypoint and tree-shaken out of release builds.
class DemoSessionStore {
  DemoSessionStore(this._storage);

  static const _key = 'ora_demo_session_v1';

  final SecureStorage _storage;

  UserProfile? _profile;

  UserProfile? get profile => _profile;

  /// Stable demo uid per phone — the same number always signs in to the
  /// same demo account within one install.
  static String uidForPhone(String phoneE164) =>
      'demo_${phoneE164.replaceAll(RegExp(r'\D'), '')}';

  AuthUser? get authUser {
    final p = _profile;
    if (p == null) return null;
    return AuthUser(
      uid: p.uid,
      phoneNumber: p.phoneNumber,
      isEmailVerified: true,
      displayName: p.displayName,
      role: p.role,
      driverStatus: p.driverStatus,
      isProfileComplete: p.profileComplete,
    );
  }

  /// Restores a persisted demo session (app restart). Null when signed out.
  Future<UserProfile?> load() async {
    if (_profile != null) return _profile;
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      _profile = _decode(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _key);
      _profile = null;
    }
    return _profile;
  }

  Future<UserProfile> save(UserProfile profile) async {
    _profile = profile;
    await _storage.write(key: _key, value: jsonEncode(_encode(profile)));
    return profile;
  }

  /// First sign-in for this demo uid — lands on onboarding like a real
  /// brand-new account (profileComplete = false).
  Future<UserProfile> createForPhone(String phoneE164) {
    return save(
      UserProfile(
        uid: uidForPhone(phoneE164),
        phoneNumber: phoneE164,
        role: 'passenger',
        activeMode: 'passenger',
        profileComplete: false,
      ),
    );
  }

  /// DEMO-ONLY auto-approval — the production app keeps real admin review.
  Future<UserProfile> approveVendor(String type) {
    final p = _require();
    return save(
      _copy(
        p,
        vendorApplications: {...p.vendorApplications, type: 'approved'},
      ),
    );
  }

  /// DEMO-ONLY — driver onboarding resolves straight to approved.
  Future<UserProfile> approveDriver({String? displayName}) {
    final p = _require();
    return save(
      _copy(
        p,
        role: 'driver',
        driverStatus: 'approved',
        activeMode: 'driver',
        displayName: displayName ?? p.displayName,
      ),
    );
  }

  Future<UserProfile> setMode(String mode) {
    return save(_copy(_require(), activeMode: mode));
  }

  Future<UserProfile> update({
    String? displayName,
    String? avatarData,
    bool clearAvatar = false,
    bool markComplete = false,
  }) {
    final p = _require();
    return save(
      _copy(
        p,
        displayName: displayName,
        avatarData: avatarData,
        clearAvatar: clearAvatar,
        profileComplete: markComplete ? true : p.profileComplete,
      ),
    );
  }

  Future<void> clear() async {
    _profile = null;
    await _storage.delete(key: _key);
  }

  UserProfile _require() {
    final p = _profile;
    if (p == null) {
      throw StateError('DemoSessionStore: no demo session');
    }
    return p;
  }

  static UserProfile _copy(
    UserProfile p, {
    String? displayName,
    String? role,
    String? driverStatus,
    String? activeMode,
    String? avatarData,
    bool clearAvatar = false,
    bool? profileComplete,
    Map<String, String>? vendorApplications,
  }) => UserProfile(
    uid: p.uid,
    phoneNumber: p.phoneNumber,
    displayName: displayName ?? p.displayName,
    role: role ?? p.role,
    driverStatus: driverStatus ?? p.driverStatus,
    activeMode: activeMode ?? p.activeMode,
    isActive: p.isActive,
    banned: p.banned,
    profileComplete: profileComplete ?? p.profileComplete,
    avatarData: clearAvatar ? null : (avatarData ?? p.avatarData),
    vendorApplications: vendorApplications ?? p.vendorApplications,
  );

  static Map<String, dynamic> _encode(UserProfile p) => {
    'uid': p.uid,
    'phoneNumber': p.phoneNumber,
    'displayName': p.displayName,
    'role': p.role,
    'driverStatus': p.driverStatus,
    'activeMode': p.activeMode,
    'isActive': p.isActive,
    'banned': p.banned,
    'profileComplete': p.profileComplete,
    'avatarData': p.avatarData,
    'vendorApplications': p.vendorApplications,
  };

  static UserProfile _decode(Map<String, dynamic> j) => UserProfile(
    uid: j['uid'] as String,
    phoneNumber: j['phoneNumber'] as String,
    displayName: j['displayName'] as String?,
    role: j['role'] as String?,
    driverStatus: j['driverStatus'] as String?,
    activeMode: j['activeMode'] as String?,
    isActive: j['isActive'] as bool? ?? true,
    banned: j['banned'] as bool? ?? false,
    profileComplete: j['profileComplete'] as bool? ?? false,
    avatarData: j['avatarData'] as String?,
    vendorApplications:
        (j['vendorApplications'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        const {},
  );
}
