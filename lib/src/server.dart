import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'assist.dart';
import 'auth.dart';
import 'claude.dart';
import 'completion.dart';
import 'file_store.dart' show idFromDirectory;
import 'firestore_store.dart' show contentTypes;
import 'images.dart';
import 'index.dart';
import 'page_edits.dart';
import 'page_format.dart';
import 'photo_metadata.dart';
import 'render.dart';
import 'staging.dart';
import 'store.dart';
import 'tree.dart';

/// A tree loaded from its store, with the index built over it. The server
/// holds one of these in memory and replaces it when the store changes.
class Site {
  Site._(this.store, this.tree, this.index, this._version);

  final TreeStore store;
  Tree tree;
  Index index;
  late Completion completion = Completion(tree, index);
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
    if (DateTime.now().difference(_checked) < const Duration(seconds: 5)) {
      return Future.value();
    }
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
    completion = Completion(tree, index);
    _version = version;
    old.close();
  }
}

/// The site's request handler. Every page is computed from [site]. When
/// [sessions] is given, every page except sign-in requires a member.
Handler siteHandler(
  Site site,
  DisplayCopies copies, {
  Sessions? sessions,
  Assistant? assistant,
  Staging? staging,
  String assets = 'web/dist',
}) {
  final router = Router();
  final uploads =
      staging ?? Staging(p.join(p.dirname(copies.cacheDir), 'staging'));

  Renderer render(Request r) => Renderer(
    site.tree,
    site.index,
    viewer: Sessions.memberOf(r),
    editable: site.store.editable,
  );

  /// Why members cannot ask the model for help now, or null if they can.
  Future<String?> helpUnavailable() async {
    if (assistant == null || !site.store.editable) {
      return 'Help from Claude is not set up on this server.';
    }
    final settings = await site.store.helpSettings();
    if (!settings.enabled) {
      return 'An owner has not switched on help from Claude for this tree.';
    }
    if (await site.store.spentThisMonth() >= settings.monthlyLimit) {
      return "This month's limit for help from Claude has been reached.";
    }
    return null;
  }

  /// Runs a call to the model, recording its cost.
  Future<Reply> spend(Future<Reply> call) async {
    final reply = await call;
    await site.store.recordCost(reply.cost, model: reply.model.id);
    return reply;
  }

  /// A one-line summary of an edit, written by the fast model and named
  /// in [by]. If the model is not available, is slow or fails, the summary
  /// is "Change" and a short hash of the new text, such as `Change
  /// a867eb56`, and [by] is null.
  Future<({String text, String? by})> summaryOf(
    List<({String name, String before, String after})> pages,
  ) async {
    if (await helpUnavailable() == null) {
      try {
        final reply = await spend(
          assistant!.summarize(pages),
        ).timeout(const Duration(seconds: 8));
        final line = reply.text.split('\n').first.trim();
        if (!reply.refused && line.isNotEmpty && line.length <= 120) {
          return (text: line, by: reply.model.id);
        }
      } on Exception catch (e) {
        stderr.writeln('Summary not written: $e');
      }
    }
    return (text: 'Change ${changeHash(pages)}', by: null);
  }

  Response html(String body, {int status = 200}) => Response(
    status,
    body: body,
    headers: {'content-type': 'text/html; charset=utf-8'},
  );
  Response missing(Request r, String what) =>
      html(render(r).notFound(what), status: 404);

  router.get(
    '/style.css',
    (Request r) =>
        Response.ok(stylesheet, headers: {'content-type': 'text/css'}),
  );
  router.get('/assets/<name>', (Request r, String name) {
    final file = File(p.join(assets, p.basename(name)));
    if (!file.existsSync()) return Response.notFound('no such asset');
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': name.endsWith('.js')
            ? 'text/javascript'
            : 'application/octet-stream',
      },
    );
  });
  if (sessions != null) {
    router.get('/sign-in', sessions.signInPage);
    router.post('/session', sessions.create);
    router.post('/sign-out', sessions.signOut);
  }

  // Members who have not seen the welcome page are shown it first.
  final welcomed = <String>{};
  router.get('/', (Request r) async {
    final member = Sessions.memberOf(r);
    if (member != null &&
        !member.welcomed &&
        !welcomed.contains(member.email)) {
      welcomed.add(member.email);
      await site.store.markWelcomed(member);
      return html(render(r).welcome());
    }
    return html(render(r).home());
  });
  router.get('/welcome', (Request r) => html(render(r).welcome()));
  router.get(
    '/search',
    (Request r) => html(render(r).search(r.url.queryParameters['q'] ?? '')),
  );

  router.get('/people/<id>', (Request r, String id) async {
    final person = site.tree.people[id];
    if (person != null) {
      final member = Sessions.memberOf(r);
      final canEdit =
          site.store.editable && member != null && member.role.canEdit;
      // `?edit` opens the page with the editor in place of its story.
      if (canEdit && r.url.queryParameters.containsKey('edit')) {
        final off = await helpUnavailable();
        return html(
          render(r).editPerson(
            person,
            source: person.source,
            basedOn: person.revision,
            help: off == null,
            helpOff: off,
          ),
        );
      }
      return html(render(r).person(person));
    }
    final deleted = site.tree.deleted[id];
    if (deleted != null) return html(render(r).deletedPerson(deleted));
    return missing(r, 'No person has the id $id.');
  });

  /// A page in the tree, or one that was deleted, for its history.
  Person? anyPerson(String id) => site.tree.people[id] ?? site.tree.deleted[id];

  // ---------------------------------------------------------------- editing

  Response seeOther(String location) => Response.seeOther(location);
  Future<Map<String, String>> form(Request r) async =>
      Uri.splitQueryString(await r.readAsString());

  /// A form whose fields may repeat, such as a list of checkboxes.
  Future<Map<String, List<String>>> formAll(Request r) async =>
      Uri(query: await r.readAsString()).queryParametersAll;

  /// The member making a change, or null if they may not.
  Member? editor(Request r) {
    final member = Sessions.memberOf(r);
    return site.store.editable && member != null && member.role.canEdit
        ? member
        : null;
  }

  Response notAllowed(Request r) => html(
    render(r).forbidden(
      'You can read this tree but not change it. Ask its owner if you would like to edit.',
    ),
    status: 403,
  );

  /// Runs [action] for a member who may edit [id]; otherwise answers for it.
  /// A deleted page can be acted on only when [deleted] is true.
  Future<Response> editing(
    Request r,
    String id,
    Future<Response> Function(Person, Member) action, {
    bool deleted = false,
  }) async {
    final person = deleted ? anyPerson(id) : site.tree.people[id];
    if (person == null) return missing(r, 'No person has the id $id.');
    final member = editor(r);
    if (member == null) return notAllowed(r);
    return action(person, member);
  }

  /// Answers a change of several pages that could not be saved because one
  /// of them had changed meanwhile.
  Response changedMeanwhile(Request r, SaveResult result) {
    final page = anyPerson(result.conflictPage ?? '');
    return html(
      render(r).message(
        'Not saved',
        '${page == null ? 'A page' : "${page.name}'s page"} was changed by someone else at the same time, so nothing was saved. Look at it again and retry.',
      ),
      status: 409,
    );
  }

  // The editor alone, for the person's page to open in place; otherwise,
  // the person's page with the editor open.
  router.get(
    '/people/<id>/edit',
    (Request r, String id) => editing(r, id, (person, member) async {
      if (!r.url.queryParameters.containsKey('fragment')) {
        return seeOther('/people/${person.directory}?edit');
      }
      final off = await helpUnavailable();
      return html(
        render(r).editorForm(
          person,
          source: person.source,
          basedOn: person.revision,
          help: off == null,
          helpOff: off,
          inPlace: true,
        ),
      );
    }),
  );

  router.post(
    '/people/<id>/preview',
    (Request r, String id) => editing(r, id, (person, member) async {
      // Reading a page never fails; what cannot be read shows as such.
      final draft = Person.fromSource(
        id,
        person.directory,
        (await r.readAsString()).replaceAll('\r\n', '\n'),
      );
      return html(render(r).personArticle(draft, preview: true));
    }),
  );

  router.post(
    '/people/<id>/edit',
    (Request r, String id) => editing(r, id, (person, member) async {
      final fields = await form(r);
      final typed = (fields['source'] ?? '').replaceAll('\r\n', '\n');
      final helpedBy = Model.byId(fields['helped_by'])?.id;
      final basedOn = int.tryParse(fields['based_on'] ?? '') ?? person.revision;

      // Saved in its normal form; a page only reformatted is not a change.
      final source = formatPage(typed);
      final draft = Person.fromSource(id, person.directory, source);
      if (basedOn == person.revision &&
          (typed.trim() == person.source.trim() ||
              source == formatPage(person.source))) {
        return seeOther('/people/$id'); // nothing changed
      }
      final summary = await summaryOf([
        (name: person.name, before: formatPage(person.source), after: source),
      ]);
      final result = await site.store.savePerson(
        draft,
        basedOn: basedOn,
        author: member,
        summary: summary.text,
        helpedBy: helpedBy,
        summaryBy: summary.by,
      );
      if (result.saved) {
        await site.reload();
        return seeOther('/people/$id');
      }
      // Someone else saved first. Show their change and keep this text.
      final theirs = await site.store.revision(id, result.conflictWith!);
      final base = await site.store.revision(id, basedOn);
      return html(
        render(r).editPerson(
          person,
          source: source,
          basedOn: result.conflictWith!,
          help: await helpUnavailable() == null,
          helpedBy: helpedBy,
          conflict: theirs == null
              ? null
              : render(r).conflictNotice(theirs, base?.source ?? ''),
        ),
        status: 409,
      );
    }),
  );

  router.get(
    '/people/<id>/memory',
    (Request r, String id) => editing(
      r,
      id,
      (person, member) async => html(
        render(r).memoryForm(person, help: await helpUnavailable() == null),
      ),
    ),
  );

  router.post(
    '/people/<id>/memory',
    (Request r, String id) => editing(r, id, (person, member) async {
      final fields = await form(r);
      final title = (fields['title'] ?? '').trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      final date = (fields['date'] ?? '').trim();
      final text = (fields['text'] ?? '').replaceAll('\r\n', '\n').trim();
      final helpedBy = Model.byId(fields['helped_by'])?.id;
      if (title.isEmpty || text.isEmpty) {
        return html(
          render(r).memoryForm(
            person,
            title: title,
            date: date,
            text: text,
            help: await helpUnavailable() == null,
            error: 'A memory needs a title and some text.',
          ),
          status: 422,
        );
      }
      final section = '## ${date.isEmpty ? '' : '$date: '}$title\n\n$text';
      // Appending is safe to repeat: if someone else saved meanwhile, add
      // the memory to their version instead.
      for (var attempt = 0; attempt < 4; attempt++) {
        final current = site.tree.people[id]!;
        final draft = Person.fromSource(
          id,
          current.directory,
          formatPage('${current.source.trimRight()}\n\n$section\n'),
        );
        final result = await site.store.savePerson(
          draft,
          basedOn: current.revision,
          author: member,
          summary: 'Add a memory: $title',
          helpedBy: helpedBy,
        );
        await site.reload();
        if (result.saved) return seeOther('/people/$id');
      }
      return html(
        render(r).memoryForm(
          person,
          title: title,
          date: date,
          text: text,
          help: await helpUnavailable() == null,
          error:
              'The page is being edited by several people at once. Please try again.',
        ),
        status: 409,
      );
    }),
  );

  router.get('/people/<id>/history', (Request r, String id) async {
    final person = anyPerson(id);
    if (person == null) return missing(r, 'No person has the id $id.');
    return html(render(r).history(person, await site.store.history(id)));
  });

  router.get('/people/<id>/revisions/<number|[0-9]+>', (
    Request r,
    String id,
    String number,
  ) async {
    final person = anyPerson(id);
    final revision = person == null
        ? null
        : await site.store.revision(id, int.parse(number));
    if (person == null || revision == null) {
      return missing(r, 'There is no such version.');
    }
    final previous = revision.number > 1
        ? await site.store.revision(id, revision.number - 1)
        : null;
    return html(
      render(r).revision(
        person,
        revision,
        previous: previous,
        isCurrent: revision.number == person.revision,
      ),
    );
  });

  // Older links compared two versions; each version now shows its own
  // change.
  router.get('/people/<id>/compare', (Request r, String id) {
    final to = int.tryParse(r.url.queryParameters['to'] ?? '');
    return seeOther(
      to == null ? '/people/$id/history' : '/people/$id/revisions/$to',
    );
  });

  // ------------------------------------------------------ help from Claude

  Response jsonError(String message, {int status = 409}) => Response(
    status,
    body: jsonEncode({'error': message}),
    headers: {'content-type': 'application/json'},
  );
  Response jsonReply(Reply reply) => reply.refused
      ? jsonError('Claude declined to write this.', status: 422)
      : Response.ok(
          jsonEncode({
            'text': reply.text,
            'model': reply.model.id,
            'modelName': reply.model.name,
          }),
          headers: {
            'content-type': 'application/json',
            'cache-control': 'no-store',
          },
        );

  /// Runs a request for help, answering with JSON for the editor.
  Future<Response> helping(Future<Reply> Function() call) async {
    final unavailable = await helpUnavailable();
    if (unavailable != null) return jsonError(unavailable);
    try {
      return jsonReply(await spend(call()));
    } on ClaudeException catch (e) {
      stderr.writeln('Claude: $e');
      return jsonError(
        'Claude could not be reached just now. Please try again.',
        status: 502,
      );
    }
  }

  router.post(
    '/people/<id>/help',
    (Request r, String id) => editing(r, id, (person, member) async {
      final body = (jsonDecode(await r.readAsString()) as Map)
          .cast<String, Object?>();
      final request = HelpRequest.byName(body['request'] as String?);
      final source = ((body['source'] as String?) ?? '').replaceAll(
        '\r\n',
        '\n',
      );
      final from = (body['from'] as num?)?.toInt() ?? 0;
      final to = (body['to'] as num?)?.toInt() ?? 0;
      if (request == null ||
          (request == HelpRequest.selection &&
              (from < 0 || to <= from || to > source.length))) {
        return jsonError('Nothing to help with.', status: 400);
      }
      return helping(
        () => assistant!.help(
          request,
          person: person,
          source: source,
          tree: site.tree,
          index: site.index,
          from: from,
          to: to,
          guidance: (body['guidance'] as String?) ?? '',
        ),
      );
    }),
  );

  router.post(
    '/people/<id>/memory/tidy',
    (Request r, String id) => editing(r, id, (person, member) async {
      final body = (jsonDecode(await r.readAsString()) as Map)
          .cast<String, Object?>();
      final text = (body['text'] as String?) ?? '';
      if (text.trim().isEmpty) {
        return jsonError('There is nothing to tidy yet.', status: 400);
      }
      return helping(
        () => assistant!.tidyMemory(
          person,
          (body['title'] as String?) ?? '',
          text,
        ),
      );
    }),
  );

  /// The member, if they own the tree.
  Member? owner(Request r) {
    final member = editor(r);
    return member?.role == Role.owner ? member : null;
  }

  Future<Response> settingsPage(Request r, {String? error}) async => html(
    render(r).settings(
      await site.store.helpSettings(),
      spent: await site.store.spentThisMonth(),
      available: assistant != null,
      members: await site.store.members(),
      error: error,
    ),
    status: error == null ? 200 : 422,
  );

  router.get('/settings', (Request r) async {
    if (owner(r) == null) return notAllowed(r);
    return settingsPage(r);
  });

  router.post('/settings/members', (Request r) async {
    final me = owner(r);
    if (me == null) return notAllowed(r);
    final fields = await form(r);
    final email = (fields['email'] ?? '').trim().toLowerCase();
    final action = fields['action'] ?? 'set';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return settingsPage(r, error: 'That is not an email address.');
    }
    // An owner cannot lock themselves out.
    if (email == me.email) {
      return settingsPage(r, error: 'You cannot change your own membership.');
    }
    if (action == 'remove') {
      await site.store.removeMember(email);
    } else {
      final role = Role.values
          .where((role) => role.name == fields['role'])
          .firstOrNull;
      if (role == null) return settingsPage(r, error: 'Choose a role.');
      final person = site.tree.people[fields['person'] ?? ''];
      await site.store.setMember(email, role, person: person?.id);
      // A new member gets an invitation to send.
      if (fields['action'] == 'invite') {
        return seeOther(
          '/settings/invitation?email=${Uri.encodeQueryComponent(email)}',
        );
      }
    }
    return seeOther('/settings#members');
  });

  /// The site's own address, as the visitor sees it: through Firebase
  /// Hosting, the request reaches the server under another name.
  String siteAddress(Request r) {
    final host = r.headers['x-forwarded-host'] ?? r.requestedUri.authority;
    final local = host.startsWith('localhost') || host.startsWith('127.');
    return '${local ? 'http' : 'https'}://$host/';
  }

  router.get('/settings/invitation', (Request r) async {
    final me = owner(r);
    if (me == null) return notAllowed(r);
    final email = r.url.queryParameters['email'] ?? '';
    final member = (await site.store.members())
        .where((m) => m.email == email)
        .firstOrNull;
    if (member == null) return missing(r, 'No member has that address.');
    return html(
      render(r).invitation(member, from: me, address: siteAddress(r)),
    );
  });

  router.post('/settings', (Request r) async {
    if (owner(r) == null) return notAllowed(r);
    final fields = await form(r);
    final limit = double.tryParse(fields['monthly_limit'] ?? '');
    await site.store.setHelpSettings(
      HelpSettings(
        enabled: fields['help'] == 'on',
        monthlyLimit: limit == null || limit < 0 ? 10 : limit,
      ),
    );
    return seeOther('/settings');
  });

  router.post(
    '/people/<id>/restore',
    (Request r, String id) => editing(r, id, (person, member) async {
      final number = int.tryParse((await form(r))['number'] ?? '');
      final old = number == null ? null : await site.store.revision(id, number);
      if (old == null || old.deleted) {
        return missing(r, 'There is no such version.');
      }
      if (old.source.startsWith('---')) {
        return html(
          render(r).forbidden(
            'Version $number is in the page format Prosapia used before, and '
            'cannot be restored directly. Copy what you need from it instead.',
          ),
          status: 409,
        );
      }
      final draft = Person.fromSource(id, person.directory, old.source);
      // Restoring is itself a new version, so nothing is ever lost.
      final result = await site.store.savePerson(
        draft,
        basedOn: person.revision,
        author: member,
        summary: 'Restore version $number',
      );
      await site.reload();
      return seeOther(result.saved ? '/people/$id' : '/people/$id/history');
    }, deleted: true),
  );

  // ----------------------------------------------------------- page actions

  /// Who the new page for a name in [from]'s [kind] line starts with: for
  /// a child, its parents; for a sibling, the shared parents; for a parent,
  /// the other parent as their partner.
  ({String field, List<Person> fixed, List<(Person, bool)> optional})
  startingRelatives(Person from, String kind) {
    List<Person> people(List<String> ids) => [
      for (final id in ids) site.tree.people[id]!,
    ];
    switch (kind) {
      case 'children':
        final partners = people(site.index.partnersOf(from.id));
        return (
          field: 'parents',
          fixed: [from],
          optional: [for (final p in partners) (p, partners.length == 1)],
        );
      case 'siblings':
        return (
          field: 'parents',
          fixed: const [],
          optional: [
            for (final p in people(site.index.parentsOf(from.id))) (p, true),
          ],
        );
      case 'parents':
        final parents = people(site.index.parentsOf(from.id));
        return (
          field: 'partners',
          fixed: const [],
          optional: [for (final p in parents) (p, parents.length == 1)],
        );
      default:
        return (field: 'parents', fixed: const [], optional: const []);
    }
  }

  Response addForm(
    Request r,
    Person from,
    String kind,
    String name, {
    String born = '',
    String? error,
    int status = 200,
  }) {
    final context = startingRelatives(from, kind);
    return html(
      render(r).addPerson(
        from,
        kind: kind,
        name: name,
        similar: site.completion.similar(name),
        completion: site.completion,
        field: context.field,
        fixed: context.fixed,
        optional: context.optional,
        born: born,
        error: error,
      ),
      status: status,
    );
  }

  /// Whether [from]'s page still names [name] in a [kind] line.
  bool stillNamed(Person from, String kind, String name) =>
      nameToReference(from.source, kind, name, '@x') != null;

  router.get(
    '/people/<id>/add',
    (Request r, String id) => editing(r, id, (from, member) async {
      final kind = r.url.queryParameters['kind'] ?? '';
      final name = r.url.queryParameters['name'] ?? '';
      if (!stillNamed(from, kind, name)) {
        return missing(r, "${from.name}'s page does not name $name.");
      }
      return addForm(r, from, kind, name);
    }),
  );

  router.post(
    '/people/<id>/add',
    (Request r, String id) => editing(r, id, (from, member) async {
      final fields = await formAll(r);
      String field(String name) => (fields[name]?.firstOrNull ?? '').trim();
      final kind = field('kind'), name = field('name');
      final newName = field('new_name').replaceAll(RegExp(r'\s+'), ' ');
      final born = field('born');
      final basedOn = int.tryParse(field('based_on')) ?? from.revision;
      if (newName.isEmpty) {
        return addForm(
          r,
          from,
          kind,
          name,
          born: born,
          error: 'The new page needs a name.',
          status: 422,
        );
      }

      final newId = newPersonId(site.tree);
      final directory = directoryFor(newName, newId);
      final reference = '@$directory';
      final origin = nameToReference(from.source, kind, name, reference);
      if (origin == null) {
        return missing(r, "${from.name}'s page no longer names $name.");
      }
      final context = startingRelatives(from, kind);
      final chosen = [
        for (final id in fields[context.field] ?? const <String>[])
          ?site.tree.people[id],
      ];
      final source = newPage(
        name: newName,
        born: born,
        parents: [
          if (context.field == 'parents')
            for (final p in chosen) p.reference,
        ],
        partners: [
          if (context.field == 'partners')
            for (final p in chosen) p.reference,
        ],
      );
      final writes = [
        PageWrite(Person.fromSource(newId, directory, source), basedOn: 0),
        PageWrite(
          Person.fromSource(from.id, from.directory, origin),
          basedOn: basedOn,
        ),
      ];
      // A relative chosen for the new page may name them by the same plain
      // name: both parents may list the child. Link that too.
      for (final relative in chosen) {
        if (relative.id == from.id) continue;
        final linked = nameToReference(
          relative.source,
          context.field == 'parents' ? 'children' : 'partner',
          name,
          reference,
        );
        if (linked == null) continue;
        writes.add(
          PageWrite(
            Person.fromSource(relative.id, relative.directory, linked),
            basedOn: relative.revision,
          ),
        );
      }
      final result = await site.store.saveChange(
        writes,
        author: member,
        summary: 'Add a page for $newName',
      );
      await site.reload();
      if (!result.saved) return changedMeanwhile(r, result);
      return seeOther('/people/$newId');
    }),
  );

  router.post(
    '/people/<id>/link',
    (Request r, String id) => editing(r, id, (from, member) async {
      final fields = await form(r);
      final kind = fields['kind'] ?? '', name = fields['name'] ?? '';
      final target = site.tree.people[fields['target'] ?? ''];
      if (target == null) return missing(r, 'There is no such person.');
      final linked = nameToReference(from.source, kind, name, target.reference);
      if (linked == null) {
        return missing(r, "${from.name}'s page no longer names $name.");
      }
      final result = await site.store.savePerson(
        Person.fromSource(from.id, from.directory, linked),
        basedOn: int.tryParse(fields['based_on'] ?? '') ?? from.revision,
        author: member,
        summary: 'Link $name to ${target.name}\'s page',
      );
      await site.reload();
      if (!result.saved) return changedMeanwhile(r, result);
      return seeOther('/people/${from.id}');
    }),
  );

  /// The pages, other than [p]'s, that refer to [p].
  List<Person> mentioning(Person p) => [
    for (final other in site.tree.people.values)
      if (other.id != p.id && mentions(other.source, p.id)) other,
  ]..sort((a, b) => a.name.compareTo(b.name));

  router.get(
    '/people/<id>/delete',
    (Request r, String id) => editing(
      r,
      id,
      (person, member) async =>
          html(render(r).deletePerson(person, mentioning(person))),
    ),
  );

  router.post(
    '/people/<id>/delete',
    (Request r, String id) => editing(r, id, (person, member) async {
      final fields = await form(r);
      final result = await site.store.saveChange(
        [
          PageWrite.delete(
            person,
            basedOn: int.tryParse(fields['based_on'] ?? '') ?? person.revision,
          ),
          // Other pages keep what they said, with the plain name.
          for (final other in mentioning(person))
            PageWrite(
              Person.fromSource(
                other.id,
                other.directory,
                referencesToName(other.source, person.id, person.name),
              ),
              basedOn: other.revision,
            ),
        ],
        author: member,
        summary: "Delete ${person.name}'s page",
      );
      await site.reload();
      if (!result.saved) return changedMeanwhile(r, result);
      return seeOther('/people/$id');
    }),
  );

  router.post(
    '/people/<id>/resolve',
    (Request r, String id) => editing(r, id, (person, member) async {
      final fields = await form(r);
      final page = site.tree.people[fields['page'] ?? ''];
      final kind = fields['kind'] ?? '';
      final other = fields['other'] ?? '';
      final changed = page == null
          ? null
          : removeRelation(page.source, kind, other);
      if (page == null || changed == null) return seeOther('/people/$id');
      final otherName = site.tree.people[other]?.name ?? other;
      final result = await site.store.savePerson(
        Person.fromSource(page.id, page.directory, changed),
        basedOn: int.tryParse(fields['based_on'] ?? '') ?? page.revision,
        author: member,
        summary:
            'Remove $otherName from the ${kind[0].toUpperCase()}${kind.substring(1)} line',
      );
      await site.reload();
      if (!result.saved) return changedMeanwhile(r, result);
      return seeOther('/people/$id');
    }),
  );

  router.post('/changes/<id>/undo', (Request r, String id) async {
    final member = editor(r);
    if (member == null) return notAllowed(r);
    final change = await site.store.change(id);
    if (change == null) return missing(r, 'There is no such change.');
    Response refuse(String why) =>
        html(render(r).message('Not undone', why), status: 409);

    // Each page goes back to the version before the change, provided no
    // one has changed it since.
    final writes = <PageWrite>[];
    for (final MapEntry(key: page, value: number) in change.pages.entries) {
      final current = anyPerson(page);
      if (current == null || current.revision != number) {
        return refuse(
          '${current?.name ?? 'A page'} has been changed again since, so this '
          'change cannot be undone in one step. Edit the page by hand, or '
          'undo the later changes first.',
        );
      }
      final before = number <= 1
          ? null
          : await site.store.revision(page, number - 1);
      if (before == null || before.deleted) {
        writes.add(PageWrite.delete(current, basedOn: number));
      } else if (before.source.startsWith('---')) {
        return refuse(
          "The version of ${current.name}'s page before this change is in "
          'the page format Prosapia used before, and cannot be restored.',
        );
      } else {
        writes.add(
          PageWrite(
            Person.fromSource(page, current.directory, before.source),
            basedOn: number,
          ),
        );
      }
    }
    final result = await site.store.saveChange(
      writes,
      author: member,
      summary: 'Undo “${change.summary}”',
    );
    await site.reload();
    if (!result.saved) return changedMeanwhile(r, result);
    return seeOther('/changes');
  });

  // Completion for the editor and the search box.
  Response json(Object value) => Response.ok(
    jsonEncode(value),
    headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
  );
  router.get(
    '/api/people',
    (Request r) =>
        json(site.completion.people(r.url.queryParameters['q'] ?? '')),
  );
  router.get(
    '/api/places',
    (Request r) =>
        json(site.completion.places(r.url.queryParameters['q'] ?? '')),
  );

  router.get(
    '/changes',
    (Request r) async =>
        html(render(r).changes(await site.store.recentChanges())),
  );

  // ------------------------------------------------------------- photos

  router.get('/media/add', (Request r) async {
    if (editor(r) == null) return notAllowed(r);
    final person = site.tree.people[r.url.queryParameters['person'] ?? ''];
    return html(
      render(r).addPhotos(person, help: await helpUnavailable() == null),
    );
  });

  // The browser sends each chosen file here as it is chosen, so the photos
  // can be previewed, and their backs read, before they are added.
  router.post('/media/staging', (Request r) async {
    if (editor(r) == null) return notAllowed(r);
    final saved = await uploads.save(r.read());
    if (saved == null) {
      return jsonError(
        'That is not a photo Prosapia can store (JPEG, HEIC, PNG or TIFF, '
        'up to 32 MB).',
        status: 400,
      );
    }
    return Response.ok(
      jsonEncode({'token': saved.token, 'kind': saved.kind}),
      headers: {'content-type': 'application/json'},
    );
  });

  router.get('/media/staging/<token>/preview', (Request r, String token) async {
    if (editor(r) == null) return notAllowed(r);
    final file = uploads.file(token);
    if (file == null) return Response.notFound('no such upload');
    return Response.ok(
      await uploads.preview(file, 480),
      headers: {'content-type': 'image/jpeg', 'cache-control': 'private'},
    );
  });

  router.post('/media/transcribe', (Request r) async {
    if (editor(r) == null) return notAllowed(r);
    final body = (jsonDecode(await r.readAsString()) as Map)
        .cast<String, Object?>();
    // A back not yet added, by its upload token, or one already stored.
    List<int>? jpeg;
    final staged = uploads.file('${body['token']}');
    if (staged != null) {
      jpeg = await uploads.preview(staged, 1568);
    } else if (site.tree.media['${body['key']}'] case final media?) {
      jpeg = (await copies.get(
        media,
        await site.store.localFile(media),
        1920,
      ))?.readAsBytesSync();
    }
    if (jpeg == null) return jsonError('There is no such photo.', status: 404);
    return helping(() => assistant!.transcribeBack(jpeg!));
  });

  /// The people with these ids, by id and name.
  List<({String id, String name})> shown(Iterable<String> ids) => [
    for (final id in ids)
      if (site.tree.people[id] case final p?) (id: p.id, name: p.name),
  ];

  /// A photo's file, with [details] written into it, ready to store.
  Future<MediaWrite> prepare(
    File source,
    Media media,
    PhotoDetails details,
  ) async {
    final work = Directory.systemTemp.createTempSync('prosapia_photo');
    final file = source.copySync(p.join(work.path, media.fileName));
    await writeMetadata(file, media.key, details);
    media
      ..title = details.title
      ..date = details.date
      ..place = details.place
      ..description = details.back
      ..set = details.set
      ..setIndex = details.setIndex;
    media.people
      ..clear()
      ..addAll([if (!media.isBack) ...details.people.map((p) => p.id)]);
    return MediaWrite(media, file);
  }

  String? text(Object? value) {
    final s = value is String ? value.trim() : '';
    return s.isEmpty ? null : s;
  }

  router.post('/media/add', (Request r) async {
    final member = editor(r);
    if (member == null) return notAllowed(r);
    final body = (jsonDecode(await r.readAsString()) as Map)
        .cast<String, Object?>();
    final photos = ((body['photos'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    if (photos.isEmpty) return jsonError('Choose a photo first.', status: 400);
    final taken = {for (final m in site.tree.media.values) m.id};
    final set = photos.length > 1 ? newId('s', (id) => false) : null;
    final writes = <MediaWrite>[];
    for (final (i, photo) in photos.indexed) {
      final front = uploads.file('${photo['front']}');
      if (front == null) {
        return jsonError('A photo was not uploaded. Please choose it again.');
      }
      final back = photo['back'] == null
          ? null
          : uploads.file('${photo['back']}');
      final id = newId('m', taken.contains);
      taken.add(id);
      final details = PhotoDetails(
        title: text(photo['title']),
        date: text(photo['date']),
        place: text(photo['place']),
        back: back == null ? null : text(photo['backText']),
        people: shown(((photo['people'] as List?) ?? const []).cast<String>()),
        set: set,
        setIndex: set == null ? null : i + 1,
      );
      for (final (file, isBack) in [
        (front, false),
        if (back != null) (back, true),
      ]) {
        final archival = await uploads.archival(file);
        writes.add(
          await prepare(
            archival,
            Media(
              id,
              isBack: isBack,
              extension: p.extension(archival.path).substring(1) == 'heic'
                  ? 'heic'
                  : 'jpg',
              location: '',
            ),
            details,
          ),
        );
      }
    }
    final first = writes.first.media;
    await site.store.saveMedia(
      writes,
      author: member,
      summary: photos.length == 1
          ? 'Add a photo${first.title == null ? '' : ': ${first.title}'}'
          : 'Add ${photos.length} photos',
    );
    await site.reload();
    final person = site.tree.people['${body['person']}'];
    return Response.ok(
      jsonEncode({
        'location': person != null
            ? '/people/${person.id}'
            : '/media/${first.key}',
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  router.get('/media/<key>/edit', (Request r, String key) async {
    if (editor(r) == null) return notAllowed(r);
    final media = site.tree.media[key];
    if (media == null || media.isBack) {
      return missing(r, 'No photo has the id $key.');
    }
    return html(
      render(r).editPhoto(media, help: await helpUnavailable() == null),
    );
  });

  router.post('/media/<key>/edit', (Request r, String key) async {
    final member = editor(r);
    if (member == null) return notAllowed(r);
    final media = site.tree.media[key];
    if (media == null || media.isBack) {
      return missing(r, 'No photo has the id $key.');
    }
    final fields = await formAll(r);
    String? field(String name) => text(fields[name]?.firstOrNull);
    final back = site.tree.media['${media.id}-back'];
    final details = PhotoDetails(
      title: field('title'),
      date: field('date'),
      place: field('place'),
      back: back == null ? null : field('back'),
      people: shown(fields['people'] ?? const []),
      set: media.set,
      setIndex: media.setIndex,
    );
    final writes = [
      for (final m in [media, ?back])
        await prepare(
          await site.store.localFile(m),
          Media(
            m.id,
            isBack: m.isBack,
            extension: m.extension,
            location: m.location,
          ),
          details,
        ),
    ];
    await site.store.saveMedia(
      writes,
      author: member,
      summary: 'Change the details of ${media.title ?? 'a photo'}',
    );
    await site.reload();
    return seeOther('/media/$key');
  });

  router.post('/media/<key>/main', (Request r, String key) async {
    final member = editor(r);
    if (member == null) return notAllowed(r);
    final media = site.tree.media[key];
    final person = site.tree.people[(await form(r))['person'] ?? ''];
    if (media == null || person == null) {
      return missing(r, 'There is no such photo or person.');
    }
    final source = setFact(person.source, 'Photo', media.key);
    if (source == null) return seeOther('/media/$key');
    final result = await site.store.savePerson(
      Person.fromSource(person.id, person.directory, source),
      basedOn: person.revision,
      author: member,
      summary: 'Use ${media.title ?? 'a photo'} as the main photo',
    );
    await site.reload();
    if (!result.saved) return changedMeanwhile(r, result);
    return seeOther('/people/${person.id}');
  });

  router.get('/media', (Request r) => html(render(r).mediaIndex()));
  router.get('/media/<key>', (Request r, String key) {
    final media = site.tree.media[key];
    return media == null
        ? missing(r, 'No file has the id $key.')
        : html(render(r).media(media));
  });
  router.get('/media/<key>/display', (Request r, String key) async {
    final media = site.tree.media[key];
    if (media == null || !media.isImage) {
      return Response.notFound('not an image');
    }
    final width = int.tryParse(r.url.queryParameters['w'] ?? '') ?? 960;
    final file = await copies.get(
      media,
      await site.store.localFile(media),
      width,
    );
    if (file == null) {
      return Response.internalServerError(
        body: 'could not make a display copy',
      );
    }
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': 'image/jpeg',
        // Private: a shared cache must not hand a member's photo to anyone else.
        'cache-control': 'private, max-age=86400',
      },
    );
  });
  router.get('/media/<key>/file', (Request r, String key) async {
    final Media? media = site.tree.media[key];
    if (media == null) return Response.notFound('no such file');
    final file = await site.store.localFile(media);
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type':
            contentTypes[media.extension] ?? 'application/octet-stream',
        'cache-control': 'private, max-age=86400',
      },
    );
  });

  router.all(
    '/<ignored|.*>',
    (Request r) => missing(r, 'There is no page at /${r.url.path}.'),
  );

  Handler handler = (Request request) async {
    await site.refreshIfChanged();
    final segments = request.url.pathSegments;
    if (segments.length >= 2 && segments[0] == 'people') {
      final slug = segments[1];
      final id = idFromDirectory(slug);
      final person = site.tree.people[id] ?? site.tree.deleted[id];
      // A page is shown at its readable address; any other address that
      // ends in its id leads there.
      if (segments.length == 2 &&
          request.method == 'GET' &&
          person != null &&
          slug != person.directory) {
        return Response.found(
          Uri(
            path: '/people/${person.directory}',
            query: request.url.hasQuery ? request.url.query : null,
          ).toString(),
        );
      }
      if (slug != id) {
        request = _withPath(request, ['people', id, ...segments.skip(2)]);
      }
    }
    return router.call(request);
  };
  if (sessions != null) handler = sessions.middleware(handler);
  return handler;
}

/// A new person id, not used by anyone in [tree] or deleted from it.
String newPersonId(Tree tree, [Random? random]) => newId(
  'p',
  (id) => tree.people.containsKey(id) || tree.deleted.containsKey(id),
  random,
);

/// A new id such as `m-x2k9ab`: [prefix], then six characters that are
/// easy to read aloud, not [taken].
String newId(String prefix, bool Function(String) taken, [Random? random]) {
  const alphabet = '23456789abcdefghjkmnpqrstvwxyz'; // no 0/o, 1/i/l, u
  final rng = random ?? Random.secure();
  while (true) {
    final id =
        '$prefix-${List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)]).join()}';
    if (!taken(id)) return id;
  }
}

/// Eight hex digits that identify a change by its new text and the time,
/// for a summary when none could be written: `a867eb56`.
String changeHash(List<({String name, String before, String after})> pages) {
  // FNV-1a, 32 bits.
  var hash = 0x811c9dc5;
  final text =
      '${DateTime.now().microsecondsSinceEpoch}'
      '${pages.map((p) => p.after).join()}';
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// [request] as if it had asked for [segments]: a readable address such
/// as `/people/carew-howard-tbczm8/edit` is handled as `/people/p-tbczm8/edit`.
Request _withPath(Request request, List<String> segments) => Request(
  request.method,
  request.requestedUri.replace(pathSegments: segments),
  protocolVersion: request.protocolVersion,
  headers: request.headers,
  body: request.read(),
  encoding: request.encoding,
  context: request.context,
);
