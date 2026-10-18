/// Asks the user to let the server read their Gmail (read-only), implemented
/// in `data/platform/` with google_sign_in.
abstract interface class GmailAuthorizer {
  /// False when Google sign-in isn't configured in this build (no
  /// `GOOGLE_SERVER_CLIENT_ID`) or the platform can't do it.
  bool get available;

  /// Lets the user pick a Google account and grant
  /// `gmail.readonly` for the server. Returns the one-time server auth code,
  /// or null when the user cancels. Throws an `EmailException` (`signIn`) on
  /// other failures.
  Future<String?> requestServerAuthCode();
}

/// The read-only Gmail scope the server asks for.
const gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';
