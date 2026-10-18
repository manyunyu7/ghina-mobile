import 'package:google_sign_in/google_sign_in.dart';

import '../../../../data/platform/google_sign_in_setup.dart';

export '../../../../data/platform/google_sign_in_setup.dart'
    show googleClientId, googleServerClientId, googleSignInEnabled;

/// Runs the native Google flow and returns the ID token for the server,
/// or null when the user cancels. Throws on other failures.
Future<String?> obtainGoogleIdToken() async {
  final gsi = GoogleSignIn.instance;
  await ensureGoogleSignInInitialized();
  try {
    final account = await gsi.authenticate();
    return account.authentication.idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }
}
