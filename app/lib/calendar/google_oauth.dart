import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:http/http.dart' as http;

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class GoogleOAuthStore {
  static const clientId =
      '513653056808-uc9dlni08dodepmp6tb25tldodl0iejl.apps.googleusercontent.com';

  static const scopes = [CalendarApi.calendarEventsScope];

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: scopes,
  );

  static Future<GoogleSignInAccount?> currentUser() async {
    return _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
  }

  static Future<bool> isSignedIn() async {
    try {
      final user = await currentUser();
      return user != null;
    } catch (_) {
      return false;
    }
  }

  static Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (e) {
      debugPrint('GoogleOAuthStore.signIn error: $e');
      rethrow;
    }
  }

  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('GoogleOAuthStore.signOut error: $e');
    }
  }

  static Future<http.Client?> getCalendarClient() async {
    try {
      var account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      account ??= await _googleSignIn.signIn();
      if (account == null) {
        return null;
      }
      final headers = await account.authHeaders;
      return _GoogleAuthClient(headers);
    } catch (e) {
      debugPrint('GoogleOAuthStore.getCalendarClient error: $e');
      return null;
    }
  }
}
