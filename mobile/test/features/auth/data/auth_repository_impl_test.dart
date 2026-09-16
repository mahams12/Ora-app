import 'package:firebase_auth/firebase_auth.dart'
    show AdditionalUserInfo, User, UserCredential;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/logging/app_logger.dart';
import 'package:ora/core/logging/log_record.dart';
import 'package:ora/core/network/api_client.dart';
import 'package:ora/core/network/request_context.dart';
import 'package:ora/core/storage/secure_storage.dart';
import 'package:ora/core/storage/storage_keys.dart';
import 'package:ora/features/auth/data/data_sources/auth_remote_data_source.dart';
import 'package:ora/features/auth/data/data_sources/firebase_auth_data_source.dart';
import 'package:ora/features/auth/data/models/user_profile_model.dart';
import 'package:ora/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:ora/features/auth/domain/entities/otp_session.dart';
import 'package:ora/features/auth/domain/entities/phone_verification_result.dart';
import 'package:ora/features/auth/domain/entities/auth_user.dart';

class MockFirebaseAuthDataSource extends Mock
    implements FirebaseAuthDataSource {}

class MockAuthRemoteDataSource extends Mock implements AuthRemoteDataSource {}

class MockApiClient extends Mock implements ApiClient {}

class MockUserCredential extends Mock implements UserCredential {}

class MockFirebaseUser extends Mock implements User {}

class MockAdditionalUserInfo extends Mock implements AdditionalUserInfo {}

class FakeRequestContext extends Fake implements RequestContext {}

/// Captures log output instead of printing it, so tests can assert on it.
class _RecordingLogger extends AppLogger {
  final List<LogRecord> records = [];

  @override
  void log(LogRecord record) => records.add(record);
}

const _session = OtpSession(
  sessionId: 'vid-1',
  phoneE164: '+923001234567',
  otpState: OtpState.otpSent,
);

void main() {
  late MockFirebaseAuthDataSource firebase;
  late MockAuthRemoteDataSource remote;
  late MockApiClient apiClient;
  late InMemorySecureStorage storage;
  late _RecordingLogger logger;
  late AuthRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(FakeRequestContext());
  });

  /// Builds a signed-in Firebase user + credential pair.
  MockUserCredential credentialFor({required bool isNewUser}) {
    final user = MockFirebaseUser();
    when(() => user.uid).thenReturn('uid-1');
    when(() => user.phoneNumber).thenReturn('+923001234567');
    when(() => user.emailVerified).thenReturn(false);
    when(() => user.displayName).thenReturn(null);

    final info = MockAdditionalUserInfo();
    when(() => info.isNewUser).thenReturn(isNewUser);

    final credential = MockUserCredential();
    when(() => credential.user).thenReturn(user);
    when(() => credential.additionalUserInfo).thenReturn(info);
    return credential;
  }

  setUp(() {
    firebase = MockFirebaseAuthDataSource();
    remote = MockAuthRemoteDataSource();
    apiClient = MockApiClient();
    storage = InMemorySecureStorage();
    logger = _RecordingLogger();

    repository = AuthRepositoryImpl(
      firebaseDataSource: firebase,
      remoteDataSource: remote,
      secureStorage: storage,
      apiClient: apiClient,
      logger: logger,
    );

    // Both call shapes used by the repository.
    when(() => apiClient.newContext(operationId: any(named: 'operationId')))
        .thenReturn(const RequestContext(requestId: 'req-1'));
    when(() => apiClient.newContext(
          operationId: any(named: 'operationId'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenReturn(const RequestContext(requestId: 'req-2'));

    // Default: register is idempotent and non-fatal when mocked as success.
    when(() => remote.registerUser(
          uid: any(named: 'uid'),
          context: any(named: 'context'),
        )).thenAnswer((_) async {});
  });

  group('requestOtp', () {
    test('persists the OTP handshake so it survives an app kill', () async {
      when(() => firebase.startPhoneVerification(
          phoneE164: any(named: 'phoneE164'))).thenAnswer(
        (_) async => const PhoneCodeSent(_session),
      );

      final result = await repository.requestOtp(phoneE164: '+923001234567');

      expect(result, isA<PhoneCodeSent>());
      expect((result as PhoneCodeSent).session.sessionId, 'vid-1');
      expect(await storage.read(key: StorageKeys.otpSessionId), 'vid-1');
      expect(
        await storage.read(key: StorageKeys.otpPhoneE164),
        '+923001234567',
      );
    });

    test('auto-sign-in does not persist a fabricated OTP session', () async {
      const user = AuthUser(
        uid: 'uid-1',
        phoneNumber: '+923001234567',
        isEmailVerified: false,
      );
      await storage.write(key: StorageKeys.otpSessionId, value: 'stale');
      when(() => firebase.startPhoneVerification(
          phoneE164: any(named: 'phoneE164'))).thenAnswer(
        (_) async => const PhoneAutoSignedIn(user),
      );

      final result = await repository.requestOtp(phoneE164: '+923001234567');

      expect(result, isA<PhoneAutoSignedIn>());
      expect(await storage.read(key: StorageKeys.otpSessionId), isNull);
      expect(await storage.read(key: StorageKeys.otpPhoneE164), isNull);
    });
  });

  group('verifyOtp', () {
    test('returns the signed-in user on success', () async {
      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => credentialFor(isNewUser: false));

      final user =
          await repository.verifyOtp(session: _session, otpCode: '123456');

      expect(user.uid, 'uid-1');
      expect(user.phoneNumber, '+923001234567');
    });

    test('clears the stored OTP handshake once verified', () async {
      await storage.write(key: StorageKeys.otpSessionId, value: 'vid-1');
      await storage.write(
          key: StorageKeys.otpPhoneE164, value: '+923001234567');

      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => credentialFor(isNewUser: false));

      await repository.verifyOtp(session: _session, otpCode: '123456');

      expect(await storage.read(key: StorageKeys.otpSessionId), isNull);
      expect(await storage.read(key: StorageKeys.otpPhoneE164), isNull);
    });

    test('does not mirror the Firebase identity into secure storage',
        () async {
      // Firebase Auth owns session persistence; a second copy could go stale.
      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => credentialFor(isNewUser: false));

      await repository.verifyOtp(session: _session, otpCode: '123456');

      expect(await storage.read(key: 'auth_uid'), isNull);
    });

    test('does not register during OTP verify (bootstrap owns register)',
        () async {
      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => credentialFor(isNewUser: true));

      await repository.verifyOtp(session: _session, otpCode: '123456');

      verifyNever(() => remote.registerUser(
            uid: any(named: 'uid'),
            context: any(named: 'context'),
          ));
    });

    test('a backend registration is not invoked from verifyOtp', () async {
      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => credentialFor(isNewUser: false));

      await repository.verifyOtp(session: _session, otpCode: '123456');

      verifyNever(() => remote.registerUser(
            uid: any(named: 'uid'),
            context: any(named: 'context'),
          ));
    });

    test('throws SessionExpiredFailure when the credential carries no user',
        () async {
      final credential = MockUserCredential();
      when(() => credential.user).thenReturn(null);
      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => credential);

      expect(
        () => repository.verifyOtp(session: _session, otpCode: '123456'),
        throwsA(isA<SessionExpiredFailure>()),
      );
    });

    test('propagates an invalid-code failure from the data source', () async {
      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenThrow(const AppFailure.invalidOtp());

      expect(
        () => repository.verifyOtp(session: _session, otpCode: '000000'),
        throwsA(isA<InvalidOtpFailure>()),
      );
    });
  });

  group('restoreSession', () {
    test('returns null when Firebase holds no session', () async {
      when(() => firebase.currentFirebaseUser).thenReturn(null);

      expect(await repository.restoreSession(), isNull);
    });

    test('returns the user when the token still refreshes', () async {
      final user = MockFirebaseUser();
      when(() => user.uid).thenReturn('uid-1');
      when(() => user.phoneNumber).thenReturn('+923001234567');
      when(() => user.emailVerified).thenReturn(false);
      when(() => user.displayName).thenReturn(null);
      when(() => user.getIdToken(any())).thenAnswer((_) async => 'token');
      when(() => firebase.currentFirebaseUser).thenReturn(user);

      final restored = await repository.restoreSession();

      expect(restored?.uid, 'uid-1');
    });

    test('clears the session when the token cannot be refreshed', () async {
      final user = MockFirebaseUser();
      when(() => user.getIdToken(any()))
          .thenThrow(const AppFailure.sessionExpired());
      when(() => firebase.currentFirebaseUser).thenReturn(user);
      when(() => firebase.signOut()).thenAnswer((_) async {});
      await storage.write(key: StorageKeys.otpSessionId, value: 'stale');

      final restored = await repository.restoreSession();

      expect(restored, isNull);
      verify(() => firebase.signOut()).called(1);
      expect(await storage.read(key: StorageKeys.otpSessionId), isNull);
    });
  });

  group('registerUser', () {
    test('propagates backend failures', () async {
      when(() => remote.registerUser(
            uid: any(named: 'uid'),
            context: any(named: 'context'),
          )).thenThrow(const AppFailure.network(message: 'no backend'));

      expect(
        () => repository.registerUser(uid: 'uid-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('updateDisplayName', () {
    test('returns the server profile and does not send uid', () async {
      const model = UserProfileModel(
        uid: 'uid-1',
        phoneNumber: '+923001234567',
        displayName: 'Ada',
        profileComplete: true,
      );
      when(() => remote.updateProfile(
            displayName: any(named: 'displayName'),
            context: any(named: 'context'),
          )).thenAnswer((_) async => model);

      final profile =
          await repository.updateDisplayName(displayName: 'Ada');

      expect(profile.displayName, 'Ada');
      expect(profile.profileComplete, isTrue);
      verify(() => remote.updateProfile(
            displayName: 'Ada',
            context: any(named: 'context'),
          )).called(1);
    });
  });

  group('logout', () {
    test('signs out of Firebase and wipes secure storage', () async {
      when(() => firebase.signOut()).thenAnswer((_) async {});
      await storage.write(key: StorageKeys.otpSessionId, value: 'vid-1');
      await storage.write(key: StorageKeys.otpPhoneE164, value: '+92300');

      await repository.logout();

      verify(() => firebase.signOut()).called(1);
      expect(await storage.read(key: StorageKeys.otpSessionId), isNull);
      expect(await storage.read(key: StorageKeys.otpPhoneE164), isNull);
    });
  });

  group('refreshToken', () {
    test('returns the refreshed token', () async {
      when(() => firebase.getIdToken(forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => 'fresh-token');

      expect(await repository.refreshToken(), 'fresh-token');
    });

    test('throws SessionExpiredFailure when no token comes back', () async {
      when(() => firebase.getIdToken(forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => null);

      expect(
        repository.refreshToken(),
        throwsA(isA<SessionExpiredFailure>()),
      );
    });
  });

  group('secure storage contents', () {
    test('never holds an ID token or refresh token', () async {
      when(() => firebase.startPhoneVerification(
          phoneE164: any(named: 'phoneE164'))).thenAnswer(
        (_) async => const PhoneCodeSent(_session),
      );
      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => credentialFor(isNewUser: false));

      await repository.requestOtp(phoneE164: '+923001234567');
      await repository.verifyOtp(session: _session, otpCode: '123456');

      for (final key in ['id_token', 'access_token', 'refresh_token']) {
        expect(await storage.read(key: key), isNull);
      }
    });

    test('the OTP code and phone number never reach the logs', () async {
      when(() => firebase.startPhoneVerification(
          phoneE164: any(named: 'phoneE164'))).thenAnswer(
        (_) async => const PhoneCodeSent(_session),
      );
      when(() => firebase.verifyOtpCode(
            verificationId: any(named: 'verificationId'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => credentialFor(isNewUser: false));

      await repository.requestOtp(phoneE164: '+923001234567');
      await repository.verifyOtp(session: _session, otpCode: '123456');

      final emitted = logger.records
          .map((r) => '${r.message} ${r.metadata ?? ''}')
          .join('\n');

      expect(emitted, isNotEmpty, reason: 'expected auth telemetry to exist');
      expect(emitted, isNot(contains('123456')));
      expect(emitted, isNot(contains('+923001234567')));
    });
  });
}
