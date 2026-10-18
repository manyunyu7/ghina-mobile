import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/entities/email.dart';
import '../../domain/services/gmail_authorizer.dart';
import 'google_sign_in_setup.dart';

/// [GmailAuthorizer] on google_sign_in v7: the account picker, then the
/// `gmail.readonly` consent for the server (`authorizeServer` →
/// `serverAuthCode`, exchanged by the server with the web client secret).
final class GoogleGmailAuthorizer implements GmailAuthorizer {
  const GoogleGmailAuthorizer();

  @override
  bool get available => googleSignInEnabled;

  @override
  Future<String?> requestServerAuthCode() async {
    final gsi = GoogleSignIn.instance;
    try {
      await ensureGoogleSignInInitialized();
      // One Google account per connect: forget the last one so the picker
      // shows and the user can add another address.
      await gsi.signOut();
      await gsi.authenticate();
      final auth = await gsi.authorizationClient.authorizeServer(const [
        gmailReadonlyScope,
      ]);
      return auth?.serverAuthCode;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw EmailException(
        EmailErrorKind.signIn,
        'Login Google gagal (${e.code.name}). Coba lagi, ya.',
      );
    }
  }
}

/// Builds without Google sign-in, other platforms and `flutter test`.
final class NoopGmailAuthorizer implements GmailAuthorizer {
  const NoopGmailAuthorizer();

  @override
  bool get available => false;

  @override
  Future<String?> requestServerAuthCode() async => null;
}
