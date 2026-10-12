import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'images.dart';
import 'index.dart';
import 'render.dart';
import 'tree.dart';

/// The read-only site: every response is computed from [tree] and [index].
Handler siteHandler(Tree tree, Index index, DisplayCopies copies) {
  final render = Renderer(tree, index);
  final router = Router();

  Response html(String body, {int status = 200}) => Response(status,
      body: body, headers: {'content-type': 'text/html; charset=utf-8'});
  Response missing(String what) => html(render.notFound(what), status: 404);

  router.get('/', (Request r) => html(render.home()));
  router.get('/style.css',
      (Request r) => Response.ok(stylesheet, headers: {'content-type': 'text/css'}));
  router.get('/search',
      (Request r) => html(render.search(r.url.queryParameters['q'] ?? '')));

  router.get('/people/<id>', (Request r, String id) {
    final person = tree.people[id];
    return person == null ? missing('No person has the id $id.') : html(render.person(person));
  });

  router.get('/media', (Request r) => html(render.mediaIndex()));
  router.get('/media/<key>', (Request r, String key) {
    final media = tree.media[key];
    return media == null ? missing('No file has the id $key.') : html(render.media(media));
  });
  router.get('/media/<key>/display', (Request r, String key) async {
    final media = tree.media[key];
    if (media == null || !media.isImage) return Response.notFound('not an image');
    final width = int.tryParse(r.url.queryParameters['w'] ?? '') ?? 960;
    final file = await copies.get(media, width);
    if (file == null) return Response.internalServerError(body: 'could not make a display copy');
    return Response.ok(file.openRead(), headers: {
      'content-type': 'image/jpeg',
      'cache-control': 'max-age=86400',
    });
  });
  router.get('/media/<key>/file', (Request r, String key) {
    final media = tree.media[key];
    if (media == null) return Response.notFound('no such file');
    const types = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'heic': 'image/heic', 'pdf': 'application/pdf', 'wmv': 'video/x-ms-wmv', //
    };
    return Response.ok(File(media.path).openRead(), headers: {
      'content-type': types[media.extension] ?? 'application/octet-stream',
    });
  });

  router.all('/<ignored|.*>', (Request r) => missing('There is no page at /${r.url.path}.'));
  return router.call;
}
