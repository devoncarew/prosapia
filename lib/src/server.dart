import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'firestore_store.dart' show contentTypes;
import 'images.dart';
import 'index.dart';
import 'page_source.dart';
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

  /// Reloads now. Called after this server saves, so the person who saved
  /// sees their change at once.
  Future<void> reload() => _refresh(force: true);

  Future<void> _refresh({bool force = false}) async {
    _checked = DateTime.now();
    final version = await store.version();
    if (version == _version && !force) return;
    final tree = await store.load();
    final old = index;
    this.tree = tree;
    index = Index.build(tree);
    _version = version;
    old.close();
  }
}

/// The site's request handler. Every page is computed from [site]. When
/// [sessions] is given, every page except sign-in requires a member.
Handler siteHandler(Site site, DisplayCopies copies, {Sessions? sessions, String assets = 'web/dist'}) {
  final router = Router();

  Renderer render(Request r) => Renderer(site.tree, site.index,
      viewer: Sessions.memberOf(r), editable: site.store.editable);
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

  // ---------------------------------------------------------------- editing

  Response seeOther(String location) => Response.seeOther(location);
  Future<Map<String, String>> form(Request r) async => Uri.splitQueryString(await r.readAsString());

  /// Runs [action] for a member who may edit [id]; otherwise answers for it.
  Future<Response> editing(Request r, String id, Future<Response> Function(Person, Member) action) async {
    final person = site.tree.people[id];
    if (person == null) return missing(r, 'No person has the id $id.');
    final member = Sessions.memberOf(r);
    if (!site.store.editable || member == null || !member.role.canEdit) {
      return html(render(r).forbidden('You can read this tree but not change it. Ask its owner if you would like to edit.'), status: 403);
    }
    return action(person, member);
  }

  router.get('/people/<id>/edit', (Request r, String id) => editing(r, id, (person, member) async =>
      html(render(r).editPerson(person, source: personSource(person), basedOn: person.revision))));

  router.post('/people/<id>/preview', (Request r, String id) => editing(r, id, (person, member) async {
        try {
          final draft = parsePersonSource(await r.readAsString(), id: id, directory: person.directory);
          return html(render(r).personArticle(draft, withMedia: false));
        } on FormatException catch (e) {
          return html('<p class="message">${Renderer.esc(e.message)}</p>', status: 422);
        }
      }));

  router.post('/people/<id>/edit', (Request r, String id) => editing(r, id, (person, member) async {
        final fields = await form(r);
        final source = (fields['source'] ?? '').replaceAll('\r\n', '\n');
        final summary = (fields['summary'] ?? '').trim();
        final basedOn = int.tryParse(fields['based_on'] ?? '') ?? person.revision;
        Response again(String error) => html(
            render(r).editPerson(person, source: source, basedOn: basedOn, summary: summary, error: error),
            status: 422);

        final Person draft;
        try {
          draft = parsePersonSource(source, id: id, directory: person.directory);
        } on FormatException catch (e) {
          return again(e.message);
        }
        if (summary.isEmpty) return again('Add a few words on what you changed.');
        if (basedOn == person.revision && personSource(draft) == personSource(person)) {
          return seeOther('/people/$id'); // nothing changed
        }

        final result = await site.store.savePerson(draft, basedOn: basedOn, author: member, summary: summary);
        if (result.saved) {
          await site.reload();
          return seeOther('/people/$id');
        }
        // Someone else saved first. Show their change and keep this text.
        final theirs = await site.store.revision(id, result.conflictWith!);
        final base = await site.store.revision(id, basedOn);
        return html(
            render(r).editPerson(person,
                source: source,
                basedOn: result.conflictWith!,
                summary: summary,
                conflict: theirs == null ? null : render(r).conflictNotice(theirs, base?.source ?? '')),
            status: 409);
      }));

  router.get('/people/<id>/memory', (Request r, String id) =>
      editing(r, id, (person, member) async => html(render(r).memoryForm(person))));

  router.post('/people/<id>/memory', (Request r, String id) => editing(r, id, (person, member) async {
        final fields = await form(r);
        final title = (fields['title'] ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        final date = (fields['date'] ?? '').trim();
        final text = (fields['text'] ?? '').replaceAll('\r\n', '\n').trim();
        if (title.isEmpty || text.isEmpty) {
          return html(
              render(r).memoryForm(person, title: title, date: date, text: text, error: 'A memory needs a title and some text.'),
              status: 422);
        }
        final section = '## ${date.isEmpty ? '' : '$date: '}$title\n\n$text';
        // Appending is safe to repeat: if someone else saved meanwhile, add
        // the memory to their version instead.
        for (var attempt = 0; attempt < 4; attempt++) {
          final current = site.tree.people[id]!;
          final draft = parsePersonSource(personSource(current), id: id, directory: current.directory)
            ..body = current.body.isEmpty ? section : '${current.body}\n\n$section';
          final result = await site.store.savePerson(draft,
              basedOn: current.revision, author: member, summary: 'Add a memory: $title');
          await site.reload();
          if (result.saved) return seeOther('/people/$id');
        }
        return html(
            render(r).memoryForm(person, title: title, date: date, text: text, error: 'The page is being edited by several people at once. Please try again.'),
            status: 409);
      }));

  router.get('/people/<id>/history', (Request r, String id) async {
    final person = site.tree.people[id];
    if (person == null) return missing(r, 'No person has the id $id.');
    return html(render(r).history(person, await site.store.history(id)));
  });

  router.get('/people/<id>/revisions/<number|[0-9]+>', (Request r, String id, String number) async {
    final person = site.tree.people[id];
    final revision = person == null ? null : await site.store.revision(id, int.parse(number));
    if (person == null || revision == null) return missing(r, 'There is no such version.');
    return html(render(r).revision(person, revision, isCurrent: revision.number == person.revision));
  });

  router.get('/people/<id>/compare', (Request r, String id) async {
    final person = site.tree.people[id];
    final from = int.tryParse(r.url.queryParameters['from'] ?? '');
    final to = int.tryParse(r.url.queryParameters['to'] ?? '');
    if (person == null || from == null || to == null) return missing(r, 'Pick two versions to compare.');
    final a = await site.store.revision(id, from < to ? from : to);
    final b = await site.store.revision(id, from < to ? to : from);
    if (b == null) return missing(r, 'There is no such version.');
    // Comparing the first version with "before it" shows the whole page as new.
    final before = a ?? Revision(0, '', author: '', summary: '', at: b.at);
    return html(render(r).compare(person, before, b));
  });

  router.post('/people/<id>/restore', (Request r, String id) => editing(r, id, (person, member) async {
        final number = int.tryParse((await form(r))['number'] ?? '');
        final old = number == null ? null : await site.store.revision(id, number);
        if (old == null) return missing(r, 'There is no such version.');
        final draft = parsePersonSource(old.source, id: id, directory: person.directory);
        // Restoring is itself a new version, so nothing is ever lost.
        final result = await site.store.savePerson(draft,
            basedOn: person.revision, author: member, summary: 'Restore version $number');
        await site.reload();
        return seeOther(result.saved ? '/people/$id' : '/people/$id/history');
      }));

  router.get('/changes', (Request r) async => html(render(r).changes(await site.store.recentChanges())));

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
