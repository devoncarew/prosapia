import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'firestore_store.dart' show contentTypes;
import 'images.dart';
import 'index.dart';
import 'render.dart';
import 'store.dart';
import 'tree.dart';

/// A tree loaded from its store, with the index built over it. The server
/// holds one of these in memory and replaces it when the store changes.
class Site {
  Site._(this.store, this.tree, this.index, this._version);

  final TreeStore store;
  Tree tree;
  Index index;
  int _version;
  DateTime _checked = DateTime.now();
  Future<void>? _refreshing;

  static Future<Site> load(TreeStore store) async {
    final version = await store.version();
    final tree = await store.load();
    return Site._(store, tree, Index.build(tree), version);
  }

  /// Reloads the tree if the store has changed. Asks the store at most once
  /// every few seconds, so most requests cost nothing.
  Future<void> refreshIfChanged() {
    if (DateTime.now().difference(_checked) < const Duration(seconds: 5)) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    _checked = DateTime.now();
    final version = await store.version();
    if (version == _version) return;
    final tree = await store.load();
    final old = index;
    this.tree = tree;
    index = Index.build(tree);
    _version = version;
    old.close();
    stdout.writeln('Reloaded the tree at version $version.');
  }
}

/// The site's request handler. Every page is computed from [site]. When
/// [sessions] is given, every page except sign-in requires a member.
Handler siteHandler(Site site, DisplayCopies copies, {Sessions? sessions, String assets = 'web/dist'}) {
  final router = Router();

  Renderer render(Request r) => Renderer(site.tree, site.index, viewer: Sessions.memberOf(r));
  Response html(String body, {int status = 200}) => Response(status,
      body: body, headers: {'content-type': 'text/html; charset=utf-8'});
  Response missing(Request r, String what) => html(render(r).notFound(what), status: 404);

  router.get('/style.css',
      (Request r) => Response.ok(stylesheet, headers: {'content-type': 'text/css'}));
  router.get('/assets/<name>', (Request r, String name) {
    final file = File(p.join(assets, p.basename(name)));
    if (!file.existsSync()) return Response.notFound('no such asset');
    return Response.ok(file.openRead(), headers: {
      'content-type': name.endsWith('.js') ? 'text/javascript' : 'application/octet-stream',
    });
  });
  if (sessions != null) {
    router.get('/sign-in', sessions.signInPage);
    router.post('/session', sessions.create);
    router.post('/sign-out', sessions.signOut);
  }

  router.get('/', (Request r) => html(render(r).home()));
  router.get('/search',
      (Request r) => html(render(r).search(r.url.queryParameters['q'] ?? '')));

  router.get('/people/<id>', (Request r, String id) {
    final person = site.tree.people[id];
    return person == null ? missing(r, 'No person has the id $id.') : html(render(r).person(person));
  });

  router.get('/media', (Request r) => html(render(r).mediaIndex()));
  router.get('/media/<key>', (Request r, String key) {
    final media = site.tree.media[key];
    return media == null ? missing(r, 'No file has the id $key.') : html(render(r).media(media));
  });
  router.get('/media/<key>/display', (Request r, String key) async {
    final media = site.tree.media[key];
    if (media == null || !media.isImage) return Response.notFound('not an image');
    final width = int.tryParse(r.url.queryParameters['w'] ?? '') ?? 960;
    final file = await copies.get(media, await site.store.localFile(media), width);
    if (file == null) return Response.internalServerError(body: 'could not make a display copy');
    return Response.ok(file.openRead(), headers: {
      'content-type': 'image/jpeg',
      // Private: a shared cache must not hand a member's photo to anyone else.
      'cache-control': 'private, max-age=86400',
    });
  });
  router.get('/media/<key>/file', (Request r, String key) async {
    final Media? media = site.tree.media[key];
    if (media == null) return Response.notFound('no such file');
    final file = await site.store.localFile(media);
    return Response.ok(file.openRead(), headers: {
      'content-type': contentTypes[media.extension] ?? 'application/octet-stream',
      'cache-control': 'private, max-age=86400',
    });
  });

  router.all('/<ignored|.*>', (Request r) => missing(r, 'There is no page at /${r.url.path}.'));

  Handler handler = (Request request) async {
    await site.refreshIfChanged();
    return router.call(request);
  };
  if (sessions != null) handler = sessions.middleware(handler);
  return handler;
}
