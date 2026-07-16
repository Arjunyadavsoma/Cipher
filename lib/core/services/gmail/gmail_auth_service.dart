import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;

/// Custom http.Client that injects Google OAuth headers into every
/// request. Replaces the extension_google_sign_in_as_googleapis_auth
/// package, whose authenticatedClient() extension method placement has
/// shifted across versions and caused undefined_method errors. This
/// approach only depends on GoogleSignInAccount.authHeaders, which is
/// stable across google_sign_in versions and refreshes the token
/// automatically when needed.
class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._account);

  final GoogleSignInAccount _account;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await _account.authHeaders;
    request.headers.addAll(headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Handles the user's Gmail connection. Uses their own Google account via
/// OAuth (google_sign_in) - the app sends/reads mail AS the user, not
/// through a shared service account. Nothing is sent anywhere until the
/// user explicitly connects.
class GmailAuthService {
  GmailAuthService._internal();

  static final GmailAuthService instance = GmailAuthService._internal();

  static const _scopes = [
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/gmail.readonly',
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  GoogleSignInAccount? _currentAccount;

  bool get isConnected => _currentAccount != null;

  String? get connectedEmail => _currentAccount?.email;

  /// Triggers the Google sign-in UI. Call this from a "Connect Gmail"
  /// button - it cannot be triggered silently from inside an agent.
  Future<GoogleSignInAccount?> connect() async {
    try {
      _currentAccount = await _googleSignIn.signIn();
      // ignore: avoid_print
      print('Gmail connect() -> account: ${_currentAccount?.email}');
      return _currentAccount;
    } catch (e) {
      // ignore: avoid_print
      print('Gmail connect() FAILED -> $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _googleSignIn.signOut();
    _currentAccount = null;
  }

  /// Attempts silent sign-in first (if the user connected previously and
  /// the session is still valid), otherwise returns null - callers should
  /// prompt the user to connect rather than popping the sign-in UI
  /// unexpectedly mid-conversation.
  Future<http.Client?> getClient() async {
    try {
      _currentAccount ??= await _googleSignIn.signInSilently();
    } catch (e) {
      // ignore: avoid_print
      print('Gmail signInSilently() FAILED -> $e');
      return null;
    }

    if (_currentAccount == null) {
      // ignore: avoid_print
      print('Gmail getClient() -> no account connected');
      return null;
    }

    return _GoogleAuthClient(_currentAccount!);
  }

  /// Direct connectivity check - bypasses the entire chat/agent pipeline.
  /// Calls Gmail's getProfile endpoint, which only succeeds if:
  ///   1. Sign-in actually completed
  ///   2. The OAuth scopes were granted
  ///   3. Gmail API is enabled on your Google Cloud project
  ///   4. The access token is valid and not expired/revoked
  /// Returns a human-readable result string - never throws, so it's safe
  /// to call from a debug button and just display the result directly.
  Future<String> testConnection() async {
    try {
      final client = await getClient();
      if (client == null) {
        return "NOT CONNECTED - no Gmail account signed in. "
            "Call connect() first.";
      }

      final api = gmail.GmailApi(client);
      final profile = await api.users.getProfile('me');

      return "CONNECTED ✓\n"
          "Email: ${profile.emailAddress}\n"
          "Total messages: ${profile.messagesTotal}\n"
          "History ID: ${profile.historyId}";
    } catch (e) {
      return "CONNECTION FAILED ✗\nError: $e";
    }
  }
}

/// Thrown by EmailTool when a Gmail-dependent operation is attempted but
/// no account is connected. EmailAgent catches this specifically to give
/// the user a clear "connect your Gmail" response instead of a generic
/// error.
class GmailNotConnectedException implements Exception {
  @override
  String toString() => 'Gmail is not connected';
}