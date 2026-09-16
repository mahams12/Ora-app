import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_profile.dart';

/// Cached server `GET /v1/auth/me` profile for UI/router gates (role/driverStatus).
///
/// Updated only from [AuthStateNotifier] after authoritative profile loads.
/// Cleared on sign-out. The client cannot write role or driverStatus here.
class SessionUserProfileNotifier extends Notifier<UserProfile?> {
  @override
  UserProfile? build() => null;

  void setProfile(UserProfile? profile) => state = profile;

  void clear() => state = null;
}

final sessionUserProfileProvider =
    NotifierProvider<SessionUserProfileNotifier, UserProfile?>(
  SessionUserProfileNotifier.new,
);
