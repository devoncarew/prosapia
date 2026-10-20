import 'dart:convert';
import 'dart:io';

import 'package:firebase_admin_sdk/auth.dart';
import 'package:shelf/shelf.dart';

import 'render.dart';
import 'store.dart';

/// Sign-in for a tree. Google, through Firebase Authentication, confirms who
/// someone is; the tree's member list decides whether they get in.
///
/// The browser signs in and posts its ID token to `/session`. The server
/// checks it, checks membership, and sets a session cookie; every later
/// request carries that cookie.
class Sessions {
  Sessions(
    this.auth,
    this.store, {
    required this.webConfig,
    required this.secureCookies,
  });

  final Auth auth;
  final TreeStore store;

  /// Firebase's public settings for the browser-side sign-in code.
  final Map<String, Object?> webConfig;

  /// False only against the local emulators, which run over plain HTTP.
  final bool secureCookies;

  /// Firebase Hosting forwards only the cookie with this name to the server.
  static const cookieName = '__session';
  static const _lifetime = Duration(days: 14);
  static const _open = {
    'sign-in',
    'session',
    'sign-out',
    'style.css',
    'favicon.svg',
    'favicon.ico',
    'apple-touch-icon.png',
  };

  final _members = <String, ({Member? member, DateTime at})>{};

  /// The member for this request; present on every request the middleware
  /// lets through to a protected page.
  /// Forgets what is known about [email]'s membership, after it changes,
  /// so their next page reads it again.
  void forget(String email) => _members.remove(email);

  static Member? memberOf(Request request) =>
      request.context['member'] as Member?;

  Middleware get middleware =>
      (inner) => (request) async {
        final path = request.url.path;
        if (_open.contains(path) || path.startsWith('assets/')) {
          return inner(request);
        }
        final member = await _memberFor(request);
        if (member == null) {
          return Response.found(
            '/sign-in?next=${Uri.encodeQueryComponent('/${request.url}')}',
          );
        }
        return inner(request.change(context: {'member': member}));
      };

  Future<Member?> _memberFor(Request request) async {
    final cookie = _cookie(request);
    if (cookie == null) return null;
    final String? email;
    try {
      email = (await auth.verifySessionCookie(cookie)).email;
    } catch (_) {
      return null; // expired, revoked or forged
    }
    return email == null ? null : _member(email);
  }

  /// Membership, remembered for a minute so that most requests cost no
  /// database read. Removing someone takes effect within that minute.
  Future<Member?> _member(String email) async {
    final cached = _members[email];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 1)) {
      return cached.member;
    }
    final member = await store.member(email);
    _members[email] = (member: member, at: DateTime.now());
    return member;
  }

  static String? _cookie(Request request) {
    for (final part in (request.headers['cookie'] ?? '').split(';')) {
      final i = part.indexOf('=');
      if (i > 0 && part.substring(0, i).trim() == cookieName) {
        return part.substring(i + 1).trim();
      }
    }
    return null;
  }

  String _setCookie(String value, Duration maxAge) =>
      '$cookieName=$value; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge.inSeconds}${secureCookies ? '; Secure' : ''}';

  Response signInPage(Request request) => Response.ok(
    Renderer.signIn(webConfig),
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
    },
  );

  /// `POST /session` with `{"idToken": "..."}` from the browser.
  Future<Response> create(Request request) async {
    Response refuse(int status, String message) => Response(
      status,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );

    final String idToken;
    try {
      idToken =
          (jsonDecode(await request.readAsString()) as Map)['idToken']
              as String;
    } catch (_) {
      return refuse(
        HttpStatus.badRequest,
        'The sign-in request was not understood.',
      );
    }
    final DecodedIdToken token;
    try {
      token = await auth.verifyIdToken(idToken);
    } catch (_) {
      return refuse(
        HttpStatus.unauthorized,
        'Google sign-in could not be verified. Please try again.',
      );
    }
    final email = token.email;
    if (email == null || token.emailVerified != true) {
      return refuse(
        HttpStatus.forbidden,
        'That Google account has no verified email address.',
      );
    }
    _members.remove(email);
    final member = await _member(email);
    if (member == null) {
      return refuse(
        HttpStatus.forbidden,
        '$email has not been invited to this tree. Ask the tree\'s owner to add that address.',
      );
    }
    // Keep the name Google gives, so histories read "Ann Hughes", not an address.
    final name = token.claims['name'];
    if (name is String && name.isNotEmpty && name != member.name) {
      await store.rememberName(member, name);
      _members.remove(email);
    }
    final cookie = await auth.createSessionCookie(
      idToken,
      SessionCookieOptions(expiresIn: _lifetime.inMilliseconds),
    );
    return Response.ok(
      jsonEncode({'ok': true}),
      headers: {
        'content-type': 'application/json',
        'set-cookie': _setCookie(cookie, _lifetime),
      },
    );
  }

  Response signOut(Request request) => Response.found(
    '/sign-in',
    headers: {'set-cookie': _setCookie('', Duration.zero)},
  );
}
