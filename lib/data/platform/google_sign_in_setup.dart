import 'package:google_sign_in/google_sign_in.dart';

/// Google sign-in is available only when the OAuth client ids are provided at
/// build time:
///
/// ```
/// flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id used by the server>
///             --dart-define=GOOGLE_CLIENT_ID=<iOS client id>   # iOS only
/// ```
///
/// iOS also needs the reversed client id as a URL scheme in `Info.plist`, and
/// Android needs the app's SHA-1 registered in the Google Cloud console.
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const googleSignInEnabled = googleServerClientId != '';

Future<void>? _init;

/// `GoogleSignIn.instance.initialize` must run exactly once per process;
/// every Google flow (app login, Gmail connect) awaits this first.
Future<void> ensureGoogleSignInInitialized() =>
    _init ??= GoogleSignIn.instance.initialize(
      clientId: googleClientId.isEmpty ? null : googleClientId,
      serverClientId: googleServerClientId,
    );
