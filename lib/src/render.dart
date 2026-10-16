import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import 'claude.dart';
import 'completion.dart';
import 'contradictions.dart';
import 'dates.dart';
import 'diff.dart';
import 'index.dart';
import 'page_syntax.dart';
import 'store.dart';
import 'tree.dart';

/// Turns the tree into HTML pages. Nothing here is stored: every page is
/// computed from the repository and the index.
class Renderer {
  Renderer(this.tree, this.index, {this.viewer, this.editable = false});

  final Tree tree;
  final Index index;

  /// The signed-in member the page is for, when the tree requires sign-in.
  final Member? viewer;

  /// Whether the store keeps history and accepts edits.
  final bool editable;

  bool get _canEdit => editable && (viewer?.role.canEdit ?? false);

  static String esc(String? s) => htmlEscape.convert(s ?? '');

  /// A page of the site. A [wide] page has room for a column beside its
  /// text.
  String page(
    String title,
    String body, {
    String query = '',
    bool wide = false,
  }) =>
      '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · ${esc(tree.name)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Sans+3:ital,wght@0,400;0,500;0,600;0,700;1,400&display=swap">
<link rel="stylesheet" href="/style.css">
</head>
<body>
<header>
  <a class="site" href="/">${esc(tree.name)}</a>
  <nav><a href="/">People</a> <a href="/media">Photos</a>${editable ? ' <a href="/changes">Recent changes</a>' : ''}${_canEdit && viewer!.role == Role.owner ? ' <a href="/settings">Settings</a>' : ''}</nav>
  <form action="/search" class="search"><input type="search" name="q" autocomplete="off" value="${esc(query)}" placeholder="Search" aria-label="Search"></form>
  ${viewer == null ? '' : '<form class="account" method="post" action="/sign-out"><span title="${esc(viewer!.email)} · ${viewer!.role.name}">${esc(viewer!.name ?? viewer!.email)}</span> <button>Sign out</button></form>'}
</header>
<main${wide ? ' class="wide"' : ''}>
$body
</main>
<script type="module" src="/assets/search.js"></script>
</body>
</html>
''';

  /// A person's page address, readable: `/people/carew-howard-joseph-tbczm8`.
  /// Only the trailing id is relied on, so older addresses keep working.
  static String pathOf(Person p) => '/people/${p.directory}';

  String personLink(String id, {bool years = false}) {
    final p = tree.people[id];
    if (p == null) {
      final gone = tree.deleted[id];
      return gone == null
          ? '<span class="missing">unknown person ($id)</span>'
          : '<a class="deleted" href="/people/$id">${esc(gone.name)}</a> <span class="years">(page deleted)</span>';
    }
    final suffix = years && p.years.isNotEmpty
        ? ' <span class="years">(${p.years})</span>'
        : '';
    return '<a href="${pathOf(p)}">${esc(p.name)}</a>$suffix';
  }

  // ------------------------------------------------------------------ home

  String home() {
    final groups = <String, List<Person>>{};
    final people = index.peopleByName().map((id) => tree.people[id]!).toList()
      ..sort((a, b) {
        final c = surnameOf(a).compareTo(surnameOf(b));
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    for (final p in people) {
      groups.putIfAbsent(surnameOf(p), () => []).add(p);
    }
    final sb = StringBuffer()
      ..write('<h1>${esc(tree.name)}</h1>')
      ..write(
        '<p class="lead">${tree.people.length} people, ${tree.media.length} photos and documents.</p>',
      );
    if (tree.problems.isNotEmpty) {
      sb.write(
        '<details class="problems"><summary>${tree.problems.length} files could not be read</summary><ul>',
      );
      for (final problem in tree.problems) {
        sb.write('<li>${esc(problem)}</li>');
      }
      sb.write('</ul></details>');
    }
    final mine = viewer?.person == null ? null : tree.people[viewer!.person];
    if (mine != null) {
      sb.write(
        '<p class="actions">Start at ${personLink(mine.id)} · <a href="/welcome">Welcome page</a></p>',
      );
    }
    sb.write('<div class="surnames">');
    groups.forEach((surname, people) {
      sb.write('<section><h2>${esc(surname)}</h2><ul>');
      for (final p in people) {
        sb.write('<li>${personLink(p.id, years: true)}</li>');
      }
      sb.write('</ul></section>');
    });
    sb.write('</div>');
    return page('People', sb.toString());
  }

  /// A newcomer's first page: where they are in the tree, their close
  /// family, and one easy thing to do.
  String welcome() {
    final me = viewer;
    final first = me?.name?.split(' ').first;
    final person = me?.person == null ? null : tree.people[me!.person];
    final sb = StringBuffer(
      '<h1>Welcome${first == null ? '' : ', ${esc(first)}'}</h1>'
      '<p class="lead">This is ${esc(tree.name)}: the family\'s history, kept together by the family. '
      'It holds ${tree.people.length} people and ${tree.media.values.where((m) => !m.isBack).length} photos and documents.</p>',
    );
    if (person != null) {
      final photo = person.photo == null ? null : tree.media[person.photo];
      sb.write('<section class="start">');
      if (photo != null && photo.isImage) {
        sb.write(
          '<a href="${pathOf(person)}"><img src="/media/${photo.key}/display?w=240" alt=""></a>',
        );
      }
      sb.write(
        '<div><h2>${esc(person.name)}</h2>'
        '${person.years.isEmpty ? '' : '<p class="years">${person.years}</p>'}'
        '<p><a class="button primary" href="${pathOf(person)}">Go to ${esc(person.name)}\'s page</a></p>',
      );
      final family = [
        for (final (label, ids) in [
          ('Parents', index.parentsOf(person.id)),
          ('Partners', index.partnersOf(person.id)),
          ('Brothers and sisters', index.siblingsOf(person.id)),
          ('Children', index.childrenOf(person.id)),
        ])
          if (ids.isNotEmpty)
            '<dt>$label</dt><dd>${ids.map(personLink).join(', ')}</dd>',
      ];
      if (family.isNotEmpty) {
        sb.write('<dl class="family">${family.join()}</dl>');
      }
      sb.write('</div></section>');
    }
    sb.write('<h2>Something to try</h2><ul class="try">');
    if (_canEdit && person != null) {
      sb.write(
        '<li><a href="/people/${person.id}/memory">Add a memory of ${esc(person.name)}</a>: a story, a trip, something you remember. A few sentences is plenty.</li>',
      );
    }
    sb.write(
      '<li>Type a name in the search box at the top of any page to find someone.</li>'
      '<li><a href="/">See everyone in the tree</a>, grouped by family name.</li>',
    );
    if (_canEdit) {
      sb.write(
        '<li>Anything can be corrected: choose Edit on a page. Every change is kept, so nothing can be lost.</li>',
      );
    }
    sb.write('</ul>');
    return page('Welcome', sb.toString());
  }

  /// The last word of a person's name, for grouping the list of people.
  static String surnameOf(Person p) {
    final words = p.name.trim().split(RegExp(r'\s+'));
    return words.length > 1 ? words.last : 'Other';
  }

  // ---------------------------------------------------------------- person

  /// A person's page: its title, then the story beside the facts. With an
  /// [editor], the editor takes the story's place and the title stays, as
  /// when editing an issue on GitHub.
  String person(Person p, {String? editor}) {
    final buttons = [
      if (_canEdit)
        '<a class="button primary edit" href="${pathOf(p)}?edit" data-edit="/people/${p.id}/edit?fragment">Edit</a>',
      if (_canEdit)
        '<a class="button" href="/people/${p.id}/memory">Add a memory</a>',
      if (_canEdit)
        '<a class="button" href="/media/add?person=${p.id}">Add photos</a>',
    ];
    final more = [
      if (editable) '<a href="/people/${p.id}/history">Change history</a>',
      if (_canEdit) '<a href="/people/${p.id}/delete">Delete</a>',
    ];
    final actions = [
      ...buttons,
      if (more.isNotEmpty)
        '<details class="more"><summary class="button" aria-label="More actions" title="More actions">⋯</summary><div class="menu">${more.join()}</div></details>',
    ];
    final head = StringBuffer('<div class="person-head">');
    head.write(
      '<div class="title"><div class="name"><h1>${esc(p.name)}</h1>'
      '${p.years.isEmpty ? '' : '<span class="lead">${p.years}</span>'}</div>',
    );
    if (actions.isNotEmpty) {
      head.write(
        '<div class="actions"${editor == null ? '' : ' hidden'}>${actions.join()}</div>',
      );
    }
    head.write('</div>');
    head.write('</div>');
    final edited = editable && p.editedBy != null && p.editedAt != null
        ? '<p class="edited">Edited by ${esc(p.editedBy)} ${ago(p.editedAt!)} · <a href="/people/${p.id}/history">history</a></p>'
        : '';
    return page(
      editor == null ? p.name : 'Editing ${p.name}',
      '$head${personArticle(p, editor: editor)}${editor == null ? edited : ''}'
      '${editor != null
          ? '<script type="module" src="/assets/editor.js"></script>'
          : _canEdit
          ? '<script type="module" src="/assets/page.js"></script>'
          : ''}',
      wide: true,
    );
  }

  /// The facts and the story of a person's page, below its title. Also
  /// used for the editor's preview, where [p] is the text being typed and
  /// not yet part of the tree; a [preview] leaves out photos and actions.
  /// An [editor] takes the story's place.
  String personArticle(Person p, {bool preview = false, String? editor}) {
    final sb = StringBuffer();
    final actions = _canEdit && !preview;
    sb.write(
      '<article class="person${editor == null ? '' : ' editing-on'}">'
      '${_infobox(p, actions: actions)}',
    );
    if (editor != null) {
      sb.write('<div class="editing">$editor</div></article>');
      return sb.toString();
    }
    sb.write('<div class="person-body">');
    if (_canEdit || !requiresViewer) {
      sb.write(_contradictions(p, actions: actions));
      for (final (items, what) in [
        (issuesOf(p), 'could not be read'),
        (checksOf(p), 'may be worth checking'),
      ]) {
        if (items.isEmpty) continue;
        sb.write(
          '<details class="issues"><summary>${items.length == 1 ? 'One thing' : '${items.length} things'} on this page $what</summary><ul>',
        );
        for (final item in items) {
          sb.write('<li>${esc(item)}</li>');
        }
        sb.write('</ul></details>');
      }
    }

    if (p.body.isNotEmpty) {
      sb.write('<div class="prose">${markdown(p.body)}</div>');
    } else {
      sb.write(
        '<p class="empty">Nothing has been written about ${esc(p.name)} yet.</p>',
      );
    }

    final (dated, undated) = _timeline(p);
    if (dated.isNotEmpty) {
      sb.write('<h2>Timeline</h2><table class="timeline">');
      for (final e in dated) {
        sb.write('<tr><th>${date(e.date)}</th><td>${e.html}</td></tr>');
      }
      sb.write('</table>');
    }
    if (undated.isNotEmpty) {
      sb.write('<h2>Also recorded</h2><ul>');
      for (final html in undated) {
        sb.write('<li>$html</li>');
      }
      sb.write('</ul>');
    }

    final media = preview
        ? const <Media>[]
        : [
            for (final key in index.mediaOf(p.id))
              if (!tree.media[key]!.isBack) tree.media[key]!,
          ];
    if (media.isNotEmpty) {
      sb.write('<h2>Photos and documents</h2>${gallery(media)}');
    }
    sb.write('</div></article>');
    return sb.toString();
  }

  /// Whether pages are only for signed-in members (otherwise the tree is a
  /// local set of files, and its reader is its editor).
  bool get requiresViewer => viewer != null;

  /// Everything on [p]'s page that could not be read, including references
  /// to people who are not in the tree.
  List<String> issuesOf(Person p) => [
    ...p.issues,
    for (final r in [...p.parents, ...p.children, ...p.siblings, ...p.partners])
      if (r.id != null && !tree.people.containsKey(r.id))
        'No one in the tree has the id ${r.id}.',
    for (final c in p.couples)
      if (c.partner?.id != null && !tree.people.containsKey(c.partner!.id))
        'No one in the tree has the id ${c.partner!.id}.',
    for (final m in proseRef.allMatches(p.body))
      if (!tree.people.containsKey('p-${m[1]!.split('-').last}'))
        'No one in the tree matches @${m[1]}.',
  ];

  /// Dates that look unlikely. These are questions, never errors: real
  /// records are messy, and the editor may know better.
  List<String> checksOf(Person p) {
    int? year(Event? e) => e?.date?.understood == true ? e!.date!.year : null;
    final born = year(p.born), died = year(p.died), buried = year(p.buried);
    final now = DateTime.now().year;
    return [
      if (born != null && born > now) 'Born in $born, which is in the future.',
      if (born != null && died != null && died < born)
        'Died in $died, before being born in $born.',
      if (died != null && buried != null && buried < died)
        'Buried in $buried, before dying in $died.',
      if (born != null && died != null && died - born > 110)
        'Lived ${died - born} years.',
      for (final id in index.parentsOf(p.id))
        ...() {
          final parent = tree.people[id]!;
          final pb = year(parent.born), pd = year(parent.died);
          return [
            if (born != null && pb != null && born - pb < 12)
              '${parent.name} was ${born - pb} when ${p.name} was born.',
            if (born != null && pb != null && born - pb > 70)
              '${parent.name} was ${born - pb} when ${p.name} was born.',
            if (born != null && pd != null && born > pd + 1)
              'Born in $born, after ${parent.name} died in $pd.',
          ];
        }(),
      for (final c in p.couples)
        if (born != null && year(c.event) != null && year(c.event)! - born < 14)
          '${c.kind} in ${year(c.event)}, at about ${year(c.event)! - born}.',
    ];
  }

  /// Contradictions between [p]'s page and others, each with a way to
  /// resolve it by removing one side.
  String _contradictions(Person p, {required bool actions}) {
    final found = contradictionsOf(tree, p);
    if (found.isEmpty) return '';
    final sb = StringBuffer(
      '<details class="issues contradictions" open><summary>${found.length == 1 ? 'One thing' : '${found.length} things'} on this page contradict${found.length == 1 ? 's' : ''} ${found.length == 1 ? 'another statement' : 'other statements'}</summary><ul>',
    );
    for (final c in found) {
      sb.write('<li>${esc(c.message)}');
      if (actions) {
        sb.write('<div class="resolve">');
        for (final s in c.statements) {
          final page = s.page == p.id ? p : tree.people[s.page];
          if (page == null) continue;
          final other = tree.people[s.other]?.name ?? s.other;
          final where = s.page == p.id ? 'this page' : '${page.name}\'s page';
          sb.write(
            '<form method="post" action="/people/${p.id}/resolve">'
            '<input type="hidden" name="page" value="${s.page}">'
            '<input type="hidden" name="kind" value="${esc(s.kind)}">'
            '<input type="hidden" name="other" value="${s.other}">'
            '<input type="hidden" name="based_on" value="${page.revision}">'
            '<button>Remove ${esc(other)} from the ${esc(s.label)} line on ${esc(where)}</button></form>',
          );
        }
        sb.write('</div>');
      }
      sb.write('</li>');
    }
    sb.write('</ul></details>');
    return sb.toString();
  }

  /// A date as typed, with how it was read shown on hover.
  String date(TreeDate d) => d.understood
      ? '<span class="date" title="Read as: ${esc(d.meaning)}">${esc(d.display)}</span>'
      : '<span class="unresolved" title="Not read as a date">${esc(d.display)}</span>';

  /// A person named in a fact line: linked when they have a page.
  String ref(PersonRef r, {bool years = false}) {
    final q = r.qualifier == null
        ? ''
        : ' <span class="years">(${esc(r.qualifier)})</span>';
    if (r.id != null) {
      if (tree.people.containsKey(r.id)) {
        return personLink(r.id!, years: years) + q;
      }
      return '<span class="unresolved" title="No one in the tree has this id">${esc(r.id)}</span>$q';
    }
    return '<span class="named" title="No page yet">${esc(r.name)}</span>$q';
  }

  /// The marriage of [a] and [b], stated on either page.
  CoupleEvent? marriageOf(String a, String b) {
    for (final (who, other) in [(a, b), (b, a)]) {
      final p = tree.people[who];
      if (p == null) continue;
      for (final c in p.couples) {
        if (c.partner?.id == other && c.kind.toLowerCase() == 'married') {
          return c;
        }
      }
    }
    return null;
  }

  /// A plain name, with an action to give them a page when [from] is
  /// given: the page whose [kind] line names them.
  String _named(PersonRef r, {String? from, String? kind, bool years = false}) {
    final html = ref(r, years: years);
    if (from == null || kind == null || r.name == null) return html;
    final query = Uri(queryParameters: {'kind': kind, 'name': r.name!}).query;
    return '$html <a class="add" href="/people/$from/add?${esc(query)}" title="Create a page for ${esc(r.name)}">+ page</a>';
  }

  String _infobox(Person p, {bool actions = false}) {
    final rows = <(String, String)>[];
    void row(String label, Iterable<String> items) {
      final html = items.where((x) => x.isNotEmpty).join('<br>');
      if (html.isNotEmpty) rows.add((label, html));
    }

    String event(Event? e) => e == null
        ? ''
        : [
            if (e.date != null) date(e.date!),
            if (e.place != null) esc(e.place),
          ].join('<br>');

    String qualified(String id, List<PersonRef> stated, {bool years = false}) {
      final q = stated
          .where((r) => r.id == id && r.qualifier != null)
          .firstOrNull
          ?.qualifier;
      return personLink(id, years: years) +
          (q == null ? '' : ' <span class="years">(${esc(q)})</span>');
    }

    Iterable<String> named(
      List<PersonRef> refs,
      String kind, {
      bool years = false,
      String? from,
    }) => [
      for (final r in refs)
        if (r.id == null || !tree.people.containsKey(r.id))
          _named(
            r,
            from: actions ? (from ?? p.id) : null,
            kind: kind,
            years: years,
          ),
    ];

    if (p.alsoKnownAs.isNotEmpty) {
      row('Also known as', [esc(p.alsoKnownAs.join(', '))]);
    }
    row('Born', [event(p.born)]);
    row('Christened', [event(p.christened)]);
    row('Died', [event(p.died)]);
    row('Buried', [event(p.buried)]);
    row('Parents', [
      for (final id in index.parentsOf(p.id)) qualified(id, p.parents),
      ...named(p.parents, 'parents'),
    ]);
    row('Partners', [
      for (final id in index.partnersOf(p.id))
        personLink(id) +
            switch (marriageOf(p.id, id)?.event.date?.year) {
              null => '',
              final year => ' <span class="years">(married $year)</span>',
            },
      ...named(p.partners, 'partner'),
      for (final c in p.couples)
        if (c.partner != null && c.partner!.id == null)
          _named(
            c.partner!,
            from: actions ? p.id : null,
            kind: c.kind.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
          ),
    ]);
    row('Children', [
      for (final id in index.childrenOf(p.id))
        qualified(id, const [], years: true),
      ...named(p.children, 'children'),
    ]);
    // Children named on a parent's page without a page of their own are
    // siblings too.
    final siblingNames = <String>{};
    row('Siblings', [
      for (final id in index.siblingsOf(p.id)) personLink(id, years: true),
      ...named(p.siblings, 'siblings'),
      for (final parent in index.parentsOf(p.id))
        for (final r in tree.people[parent]!.children)
          if (r.id == null &&
              !p.siblings.any((s) => s.name == r.name) &&
              siblingNames.add(r.name!))
            ...named([r], 'children', from: parent),
    ]);

    final photo = p.photo == null ? null : tree.media[p.photo];
    if (rows.isEmpty && photo == null) return '';
    final sb = StringBuffer('<aside class="infobox">');
    if (photo != null && photo.isImage) {
      sb.write(
        '<a href="/media/${photo.key}"><img src="/media/${photo.key}/display?w=480" alt="${esc(photo.title ?? p.name)}"></a>',
      );
    }
    sb.write('<table>');
    for (final (label, html) in rows) {
      sb.write('<tr><th>$label</th><td>$html</td></tr>');
    }
    sb.write('</table></aside>');
    return sb.toString();
  }

  /// A life in order: life events, other facts, marriages, children's
  /// births, and dated headings from the prose. Facts with no date, and
  /// notes, are returned separately.
  (List<({TreeDate date, String html})>, List<String>) _timeline(Person p) {
    final dated = <({TreeDate date, String html})>[];
    final undated = <String>[];
    void add(TreeDate? date, String html) => date == null || !date.understood
        ? undated.add(date == null ? html : '$html, ${this.date(date)}')
        : dated.add((date: date, html: html));
    String at(String? place) =>
        place == null ? '' : ' <span class="place">${esc(place)}</span>';

    if (p.born?.date != null) add(p.born!.date, 'Born${at(p.born!.place)}');
    if (p.christened != null) {
      add(p.christened!.date, 'Christened${at(p.christened!.place)}');
    }
    for (final f in p.facts) {
      final people = f.people.map(ref).join(', ');
      add(
        f.event.date,
        '<span class="kind">${esc(f.label)}</span> ${esc(f.description)}'
        '${people.isEmpty ? '' : ' with $people'}${at(f.event.place)}',
      );
    }
    // Couple events stated on this page, and on partners' pages about this
    // person.
    final couples = <(CoupleEvent, PersonRef?)>[
      for (final c in p.couples) (c, c.partner),
      for (final other in tree.people.values)
        if (other.id != p.id)
          for (final c in other.couples)
            if (c.partner?.id == p.id) (c, PersonRef.page(other.id)),
    ];
    // The same event stated on both pages is shown once.
    final seen = <String>{};
    for (final (c, partner) in couples) {
      final key =
          '${c.kind.toLowerCase()}|${partner?.id ?? partner?.name}|${c.event.date?.sortKey}';
      if (!seen.add(key)) continue;
      add(
        c.event.date,
        '${esc(c.kind)}${partner == null ? '' : ' ${ref(partner)}'}${at(c.event.place)}',
      );
    }
    for (final id in index.childrenOf(p.id)) {
      final child = tree.people[id]!;
      if (child.born?.date != null) {
        add(child.born!.date, 'Birth of ${personLink(id)}');
      }
    }
    for (final m in RegExp(
      r'^##\s+(.+?)\s*[:–-]\s*(.+)$',
      multiLine: true,
    ).allMatches(p.body)) {
      final d = TreeDate.parse(m[1]!);
      if (d.understood) add(d, esc(m[2]));
    }
    if (p.died?.date != null) add(p.died!.date, 'Died${at(p.died!.place)}');
    if (p.buried != null) add(p.buried!.date, 'Buried${at(p.buried!.place)}');
    for (final note in p.notes) {
      undated.add('<span class="kind">Note</span> ${esc(note)}');
    }

    // A stable sort keeps birth first and death last among equal dates.
    final sorted = [for (final (i, e) in dated.indexed) (i, e)]
      ..sort((a, b) {
        final c = a.$2.date.sortKey.compareTo(b.$2.date.sortKey);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return ([for (final (_, e) in sorted) e], undated);
  }

  /// Renders page prose: `@` references become links to people, and
  /// `[date: …]` and `[place: …]` are marked for display.
  String markdown(String source) {
    final marked = source
        .replaceAllMapped(proseRef, (m) {
          final id = 'p-${m[1]!.split('-').last}';
          final person = tree.people[id];
          return person == null
              ? '<span class="unresolved" title="No one in the tree matches this">@${m[1]}</span>'
              : '<a href="${pathOf(person)}">${esc(person.name)}</a>';
        })
        .replaceAllMapped(proseMarked, (m) {
          if (m[1]!.toLowerCase() == 'date') return date(TreeDate.parse(m[2]!));
          return '<span class="place-ref">${esc(m[2])}</span>';
        });
    final html = md.markdownToHtml(
      marked,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    // Links written as relative file paths in older pages still work.
    return html
        .replaceAllMapped(
          RegExp(r'href="[^"]*?([a-z0-9]{6})/index\.md"'),
          (m) => 'href="/people/p-${m[1]}"',
        )
        .replaceAllMapped(
          RegExp(r'src="[^"]*?media/(m-[a-z0-9]+(?:-back)?)\.\w+"'),
          (m) => 'src="/media/${m[1]}/display?w=960"',
        );
  }

  // ----------------------------------------------------------------- media

  String gallery(Iterable<Media> items) {
    final sb = StringBuffer('<div class="gallery">');
    for (final m in items) {
      final caption = esc(m.title ?? 'Untitled');
      sb.write('<a href="/media/${m.key}">');
      if (m.isImage) {
        sb.write(
          '<img loading="lazy" src="/media/${m.key}/display?w=240" alt="$caption">',
        );
      } else {
        sb.write('<span class="file">${m.extension.toUpperCase()}</span>');
      }
      sb.write('<span>$caption</span></a>');
    }
    sb.write('</div>');
    return sb.toString();
  }

  String mediaIndex() {
    final fronts = tree.media.values.where((m) => !m.isBack).toList();
    return page(
      'Photos',
      '<h1>Photos and documents</h1>'
          '${_canEdit ? '<p class="actions"><a href="/media/add">Add photos</a></p>' : ''}'
          '<p class="lead">${fronts.length} files. Titles and names are read from each file\'s embedded metadata.</p>'
          '${gallery(fronts)}',
    );
  }

  /// A photo, with its back beside it when it has one, what is known about
  /// it, and the others added with it.
  String media(Media m) {
    final front = m.isBack ? tree.media[m.id] ?? m : m;
    final back = tree.media['${front.id}-back'];
    final sb = StringBuffer('<article class="media">');
    if (_canEdit && !front.isBack) {
      sb.write(
        '<p class="actions"><a href="/media/${front.key}/edit">Edit details</a></p>',
      );
    }
    sb.write('<h1>${esc(front.title ?? 'Untitled')}</h1>');
    final facts = [
      if (front.date != null) date(TreeDate.parse(front.date!)),
      if (front.place != null)
        '<span class="place-ref">${esc(front.place)}</span>',
    ];
    if (facts.isNotEmpty) sb.write('<p class="lead">${facts.join(' · ')}</p>');
    String image(Media x, String label) => x.isImage
        ? '<figure><a href="/media/${x.key}/file"><img src="/media/${x.key}/display?w=1920" alt="${esc(front.title ?? '')}, $label"></a>${back == null ? '' : '<figcaption>$label</figcaption>'}</figure>'
        : '<p><a class="file" href="/media/${x.key}/file">Open the ${x.extension.toUpperCase()} file</a></p>';
    sb.write(
      '<div class="sides${back == null ? '' : ' two'}">${image(front, 'Front')}${back == null ? '' : image(back, 'Back')}</div>',
    );
    final writing = front.description ?? back?.description;
    if (writing != null) {
      sb.write(
        '${back == null ? '' : '<h2>Written on the back</h2>'}<p class="description">${esc(writing)}</p>',
      );
    }
    if (front.people.isNotEmpty) {
      sb.write('<h2>People shown</h2><ul class="shown">');
      for (final id in front.people) {
        final person = tree.people[id];
        final main =
            _canEdit &&
                person != null &&
                person.photo != front.key &&
                front.isImage
            ? ' <form method="post" action="/media/${front.key}/main"><input type="hidden" name="person" value="$id"><button>Use as ${esc(person.name)}\'s main photo</button></form>'
            : '';
        sb.write('<li>${personLink(id, years: true)}$main</li>');
      }
      sb.write('</ul>');
    }
    if (front.set != null) {
      final set =
          tree.media.values
              .where(
                (x) => x.set == front.set && !x.isBack && x.key != front.key,
              )
              .toList()
            ..sort((a, b) => (a.setIndex ?? 0).compareTo(b.setIndex ?? 0));
      if (set.isNotEmpty) {
        sb.write('<h2>Added with it</h2>${gallery(set)}');
      }
    }
    sb.write(
      '<p class="meta">${front.key}.${front.extension}${front.width == null ? '' : ' · ${front.width} × ${front.height}'} · <a href="/media/${front.key}/file">original file</a>${back == null ? '' : ' · <a href="/media/${back.key}/file">back</a>'}</p>',
    );
    sb.write('</article>');
    return page(front.title ?? 'Untitled', sb.toString());
  }

  /// The form for adding photos, from [person]'s page when given. The
  /// browser code in photos.ts uploads each file as it is chosen.
  String addPhotos(Person? person, {required bool help}) =>
      page(person == null ? 'Add photos' : 'Add photos of ${person.name}', '''
<h1>Add photos${person == null ? '' : ' of ${esc(person.name)}'}</h1>
<p class="lead">Choose one photo or several. What you type here applies to all of them; you can change it for any one below.</p>
<form class="memory add-photos" data-person="${person?.id ?? ''}" data-help="$help">
  <label for="shared_date">When, if you know</label>
  <input id="shared_date" name="date" maxlength="80" placeholder="about 1949">
  <label for="shared_place">Where</label>
  <input id="shared_place" name="place" maxlength="200" placeholder="Hartford, CT">
  <label>Who is in them</label>
  <div class="people-picker" data-name="people" data-initial="${esc(jsonEncode([
        if (person != null) {'id': person.id, 'name': person.name},
      ]))}"></div>
  <label for="files">Photos</label>
  <input id="files" type="file" multiple accept="image/jpeg,image/heic,image/png,image/tiff,.heic,.tif,.tiff">
  <div class="photo-list"></div>
  <p class="message" role="alert" hidden></p>
  <div class="save"><button class="primary" disabled>Add the photos</button> <a href="${person == null ? '/media' : '/people/${person.id}'}">Cancel</a></div>
</form>
<script type="module" src="/assets/photos.js"></script>''');

  /// The form for changing what is known about a photo.
  String editPhoto(Media m, {required bool help}) {
    final back = tree.media['${m.id}-back'];
    final people = [
      for (final id in m.people)
        if (tree.people[id] case final p?) {'id': p.id, 'name': p.name},
    ];
    return page('Edit ${m.title ?? 'a photo'}', '''
<h1>Edit: ${esc(m.title ?? 'Untitled')}</h1>
<p class="lead">These details are written into the photo file itself, so a copy that leaves Prosapia still carries them.</p>
<form class="memory edit-photo" method="post" action="/media/${m.key}/edit" data-help="$help">
  ${m.isImage ? '<img class="thumb" src="/media/${m.key}/display?w=480" alt="">' : ''}
  <label for="title">Caption</label>
  <input id="title" name="title" value="${esc(m.title ?? '')}" maxlength="200">
  <label for="date">When</label>
  <input id="date" name="date" value="${esc(m.date ?? '')}" maxlength="80" placeholder="about 1949">
  <label for="place">Where</label>
  <input id="place" name="place" value="${esc(m.place ?? '')}" maxlength="200">
  <label>Who is in it</label>
  <div class="people-picker" data-name="people" data-initial="${esc(jsonEncode(people))}"></div>
  ${back == null ? '' : '''<label for="back">Written on the back</label>
  ${back.isImage ? '<img class="thumb" src="/media/${back.key}/display?w=480" alt="The back">' : ''}
  <textarea id="back" name="back" spellcheck="true">${esc(back.description ?? m.description ?? '')}</textarea>
  ${help ? '<div class="help tidy" data-key="${back.key}"><button type="button" class="transcribe">Claude: Transcribe</button></div>' : ''}'''}
  <div class="save"><button class="primary">Save</button> <a href="/media/${m.key}">Cancel</a></div>
</form>
<script type="module" src="/assets/photos.js"></script>''');
  }

  // ---------------------------------------------------------------- search

  String search(String query) {
    final results = index.search(query);
    final sb = StringBuffer('<h1>Search</h1>');
    if (query.trim().isEmpty) {
      sb.write(
        '<p class="lead">Type a name, a place or a word from a page.</p>',
      );
    } else if (results.isEmpty) {
      sb.write('<p class="lead">Nothing found for “${esc(query)}”.</p>');
    } else {
      sb.write(
        '<p class="lead">${results.length} results for “${esc(query)}”.</p><ul class="results">',
      );
      for (final r in results) {
        // The snippet is escaped, then the highlight marks are restored.
        final snippet = esc(r.snippet)
            .replaceAll('&lt;mark&gt;', '<mark>')
            .replaceAll('&lt;&#47;mark&gt;', '</mark>');
        final link = r.kind == 'person'
            ? personLink(r.id, years: true)
            : '<a href="/media/${r.id}">${esc(tree.media[r.id]?.title ?? 'Untitled')}</a> <span class="years">(${tree.media[r.id]?.isImage ?? false ? 'photo' : 'document'})</span>';
        sb.write(
          '<li>$link${snippet.trim().isEmpty ? '' : '<div class="snippet">$snippet</div>'}</li>',
        );
      }
      sb.write('</ul>');
    }
    return page('Search', sb.toString(), query: query);
  }

  // --------------------------------------------------------------- editing

  /// The editor: the page's text on the left, a live preview on the right.
  ///
  /// [conflict] is shown when someone else saved first; it describes their
  /// change so this editor can reapply their own on top of it.
  /// The editor for [p]'s page, which takes the place of the page's content
  /// while editing. [inPlace] marks one opened from the page itself, whose
  /// script starts and stops it.
  String editorForm(
    Person p, {
    required String source,
    required int basedOn,
    bool help = false,
    String? helpOff,
    String? helpedBy,
    bool inPlace = false,
  }) =>
      '''
<form class="editor" method="post" action="/people/${p.id}/edit" data-preview="/people/${p.id}/preview"${inPlace ? ' data-in-place' : ''}>
  <input type="hidden" name="based_on" value="$basedOn">
  <input type="hidden" name="helped_by" value="${esc(helpedBy ?? '')}">
  <div class="tabs" role="tablist">
    <button type="button" role="tab" id="tab-write" aria-selected="true" aria-controls="panel-write">Write</button>
    <button type="button" role="tab" id="tab-preview" aria-selected="false" aria-controls="panel-preview">Preview</button>
    ${help
          ? '''<span class="help" data-url="/people/${p.id}/help">
      <button type="button" data-request="draft" title="Write the story from the facts, memories and photo captions">Claude: Draft</button>
      <button type="button" data-request="revise" title="Rewrite the whole story">Claude: Revise…</button>
      <button type="button" data-request="selection" title="Rewrite the selected text" disabled>Claude: Revise selection</button>
    </span>'''
          : helpOff != null && viewer?.role == Role.owner
          ? '<span class="help off">${esc(helpOff)} <a href="/settings">Settings</a></span>'
          : ''}
  </div>
  <div class="help-bar" hidden role="status"></div>
  <div class="tab-panel" id="panel-write" role="tabpanel" aria-labelledby="tab-write">
    <div class="format" role="toolbar" aria-label="Formatting">
      <button type="button" data-format="heading" title="Heading">H</button>
      <button type="button" data-format="bold" title="Bold"><b>B</b></button>
      <button type="button" data-format="italic" title="Italic"><i>I</i></button>
      <button type="button" data-format="list" title="List">List</button>
      <button type="button" data-format="link" title="Link">Link</button>
      <span class="sep"></span>
      <button type="button" data-format="person" title="Link a person: type @ and part of a name">@ Person</button>
      <button type="button" data-format="date" title="Mark a date">Date</button>
      <button type="button" data-format="place" title="Mark a place">Place</button>
    </div>
    <textarea id="source" name="source" spellcheck="true" required aria-label="Page text">${esc(source)}</textarea>
  </div>
  <div class="tab-panel" id="panel-preview" role="tabpanel" aria-labelledby="tab-preview" hidden>
    <div id="preview" class="preview">${personArticle(p, preview: true)}</div>
  </div>
  <div class="save">
    <a class="button discard" href="${pathOf(p)}">Discard</a>
    <button class="primary" title="Publish (⌘ Enter)">Publish <kbd>⌘ ⏎</kbd></button>
  </div>
  <p class="hint">Facts first, one per line, starting with <code>Name:</code>; then a blank line and the story.</p>
  <details class="legend">
    <summary>How to write a page</summary>
    <dl>
      <dt><code>Born: 6 January 1911, Brooklyn, NY</code></dt>
      <dd>A fact: a label, a colon, then its parts separated by commas. Dates can be written as you would say them: <code>about 1925</code>, <code>spring 1925</code>, <code>the 1880s</code>.</dd>
      <dt><code>Occupation: teacher, 1908 to 1920, [place: Scranton, PA]</code></dt>
      <dd>Other facts read as what, when, where. Mark a place with <code>[place: …]</code>.</dd>
      <dt><code>Parents: @</code> then a name</dt>
      <dd>Type <code>@</code> and part of a name to link a person already in the tree. A plain name means someone without a page yet.</dd>
      <dt><code>Married: @…, 1945, Hartford, CT</code></dt>
      <dd>Relationships: <code>Parents</code>, <code>Children</code>, <code>Partner</code>, <code>Siblings</code>, <code>Married</code>.</dd>
      <dt>A blank line</dt>
      <dd>Ends the facts. Below it, write in <a href="https://commonmark.org/help/" target="_blank" rel="noopener">markdown</a>; <code>[date: …]</code> and <code>[place: …]</code> mark dates and places in the story.</dd>
    </dl>
  </details>
</form>
''';

  /// [p]'s page with the editor in place of its content: opened directly,
  /// or shown again after a save that could not be made.
  String editPerson(
    Person p, {
    required String source,
    required int basedOn,
    String? error,
    String? conflict,
    bool help = false,
    String? helpOff,
    String? helpedBy,
  }) => person(
    p,
    editor:
        '${conflict ?? ''}${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}'
        '${editorForm(p, source: source, basedOn: basedOn, help: help, helpOff: helpOff, helpedBy: helpedBy)}',
  );

  /// Creating a page for [name], a plain name on [from]'s page in a [kind]
  /// line. Offers the [similar] people already in the tree first. The new
  /// page starts with [relatives], as [field] (`parents` or `partners`):
  /// the [fixed] ones always, the others when ticked.
  String addPerson(
    Person from, {
    required String kind,
    required String name,
    required List<Person> similar,
    required Completion completion,
    required String field,
    List<Person> fixed = const [],
    List<(Person, bool)> optional = const [],
    String born = '',
    String? error,
  }) {
    final hidden =
        '<input type="hidden" name="kind" value="${esc(kind)}">'
        '<input type="hidden" name="name" value="${esc(name)}">'
        '<input type="hidden" name="based_on" value="${from.revision}">';
    final role = switch (kind) {
      'parents' => 'a parent',
      'children' => 'a child',
      'siblings' => 'a sibling',
      'partner' => 'a partner',
      _ => 'in a “${esc(kind)}” line',
    };
    final sb = StringBuffer('''
<h1>A page for ${esc(name)}</h1>
<p class="lead">${personLink(from.id)}'s page names ${esc(name)} as $role, without a page of their own.</p>
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}''');
    if (similar.isNotEmpty) {
      sb.write(
        '<h2>Already in the tree?</h2><p>These people have similar names. If one of them is ${esc(name)}, link to their page instead.</p><ul class="similar">',
      );
      for (final p in similar) {
        final detail = completion.detail(p);
        sb.write(
          '<li><form method="post" action="/people/${from.id}/link">$hidden'
          '<input type="hidden" name="target" value="${p.id}">'
          '${personLink(p.id)}${detail.isEmpty ? '' : ' <span class="years">${esc(detail)}</span>'} '
          '<button>Link to this person</button></form></li>',
        );
      }
      sb.write('</ul><h2>Or create a new page</h2>');
    }
    final relatives = [
      for (final p in fixed)
        '<label><input type="checkbox" checked disabled> ${esc(p.name)}</label>'
            '<input type="hidden" name="$field" value="${p.id}">',
      for (final (p, checked) in optional)
        '<label><input type="checkbox" name="$field" value="${p.id}"${checked ? ' checked' : ''}> ${esc(p.name)}</label>',
    ];
    sb.write('''
<form class="memory add-person" method="post" action="/people/${from.id}/add">
  $hidden
  <label for="new_name">Name</label>
  <input id="new_name" name="new_name" value="${esc(name)}" required maxlength="120">
  <label for="born">Born, if you know: a date, then a place</label>
  <input id="born" name="born" value="${esc(born)}" maxlength="120" placeholder="about 1925, Hartford, CT">
  ${relatives.isEmpty ? '' : '<fieldset><legend>${field == 'parents' ? 'Parents' : 'Partner'}</legend>${relatives.join()}</fieldset>'}
  <p class="hint">The new page starts with these facts, and ${esc(from.name)}'s page links to it in place of the name. Both are saved as one change, which can be undone from Recent changes.</p>
  <div class="save"><button class="primary">Create the page</button> <a href="/people/${from.id}">Cancel</a></div>
</form>''');
    return page('A page for $name', sb.toString());
  }

  /// Asks before deleting [p]'s page. [mentioning] are the pages that refer
  /// to [p], whose references will become plain names.
  String deletePerson(Person p, List<Person> mentioning) {
    final sb = StringBuffer(
      '''
<h1>Delete ${esc(p.name)}'s page?</h1>
<p class="lead">The page leaves the tree. Its text is kept in its history, and the deletion can be undone from Recent changes.</p>''',
    );
    if (mentioning.isNotEmpty) {
      sb.write(
        '<p>${mentioning.length == 1 ? 'One other page mentions' : '${mentioning.length} other pages mention'} ${esc(p.name)}. There, the link becomes the plain name “${esc(p.name)}”, so nothing they say is lost:</p><ul>',
      );
      for (final other in mentioning) {
        sb.write('<li>${personLink(other.id, years: true)}</li>');
      }
      sb.write('</ul>');
    }
    sb.write('''
<form class="memory" method="post" action="/people/${p.id}/delete">
  <input type="hidden" name="based_on" value="${p.revision}">
  <div class="save"><button class="danger">Delete the page</button> <a href="/people/${p.id}">Cancel</a></div>
</form>''');
    return page('Delete ${p.name}', sb.toString());
  }

  /// What is shown at a deleted page's address.
  String deletedPerson(Person p) => page(
    p.name,
    '''
<h1>${esc(p.name)}</h1>
<p class="lead">This page was deleted. Its earlier versions are in its <a href="/people/${p.id}/history">history</a>.</p>
${_canEdit && p.revision > 1 ? '<form method="post" action="/people/${p.id}/restore"><input type="hidden" name="number" value="${p.revision - 1}"><button>Bring the page back</button></form>' : ''}''',
  );

  /// Explains a save that was refused because the page had moved on.
  String conflictNotice(Revision theirs, String before) =>
      '''
<div class="conflict" role="alert">
<p><strong>${esc(theirs.by)} saved a change to this page while you were editing</strong> (“${esc(theirs.summary)}”). Your text is still below and has not been saved.</p>
<p>Their change is shown here. Work it into your text, then save again; saving now will replace their version with yours.</p>
${diff(before, theirs.source)}
</div>''';

  String memoryForm(
    Person p, {
    String title = '',
    String date = '',
    String text = '',
    String? error,
    bool help = false,
  }) => page('Add a memory of ${p.name}', '''
<h1>Add a memory of ${esc(p.name)}</h1>
<p class="lead">A story, a trip, something you remember. It is added to the end of the page as its own section; nothing else on the page changes.</p>
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}
<form class="memory" method="post" action="/people/${p.id}/memory">
  <input type="hidden" name="helped_by" value="">
  <label for="title">Title</label>
  <input id="title" name="title" value="${esc(title)}" required maxlength="120" placeholder="Trip to Wales">
  <label for="date">When, if you know. A year is enough.</label>
  <input id="date" name="date" value="${esc(date)}" maxlength="40" placeholder="1923">
  <label for="text">The memory</label>
  <textarea id="text" name="text" required spellcheck="true">${esc(text)}</textarea>
  ${help ? '<div class="help tidy" data-url="/people/${p.id}/memory/tidy"><button type="button">Claude: Tidy up</button></div><div class="help-bar" hidden role="status"></div>' : ''}
  <div class="save"><button class="primary">Add</button> <a href="/people/${p.id}">Cancel</a></div>
</form>
${help ? '<script type="module" src="/assets/memory.js"></script>' : ''}
''');

  String history(Person p, List<Revision> revisions) {
    final sb = StringBuffer('<h1>History: ${personLink(p.id)}</h1>');
    if (revisions.isEmpty) {
      sb.write(
        '<p class="lead">No versions have been recorded for this page.</p>',
      );
      return page('History of ${p.name}', sb.toString());
    }
    sb.write(
      '<p class="lead">${revisions.length} saved ${revisions.length == 1 ? 'version' : 'versions'}, newest first. Choose one to see what it changed.</p>',
    );
    sb.write('<table class="history">');
    for (final (i, r) in revisions.indexed) {
      final helped = Model.byId(r.helpedBy);
      sb.write(
        '<tr>'
        '<td><a href="/people/${p.id}/revisions/${r.number}">${time(r.at)}</a></td>'
        '<td>${esc(r.by)}</td>'
        '<td>${esc(r.summary)}'
        '${helped == null ? '' : ' <span class="years">(with ${esc(helped.name)})</span>'}'
        '${r.deleted
            ? ' <span class="years">(page deleted)</span>'
            : i == 0
            ? ' <span class="years">(current)</span>'
            : ''}</td>'
        '</tr>',
      );
    }
    sb.write('</table>');
    sb.write(_summaryNote(revisions.map((r) => r.summaryBy)));
    return page('History of ${p.name}', sb.toString());
  }

  /// The single note on a page listing changes whose summaries a model
  /// wrote. Entries are not marked one by one.
  String _summaryNote(Iterable<String?> writers) {
    final names = {
      for (final id in writers.nonNulls) Model.byId(id)?.name ?? id,
    };
    return names.isEmpty
        ? ''
        : '<p class="meta">Change summaries by ${esc(names.join(' and '))}.</p>';
  }

  /// One saved version, and what it changed from the version before it.
  String revision(
    Person p,
    Revision r, {
    Revision? previous,
    required bool isCurrent,
  }) {
    final helped = Model.byId(r.helpedBy);
    return page('${p.name}, version ${r.number}', '''
<h1>${personLink(p.id)}: version ${r.number}</h1>
<p class="lead">Saved ${time(r.at)} by ${esc(r.by)}${helped == null ? '' : ', with ${esc(helped.name)}'}: “${esc(r.summary)}”. <a href="/people/${p.id}/history">All versions</a></p>
${r.deleted
        ? '<p class="lead">This version deleted the page.</p>'
        : isCurrent
        ? '<p class="lead">This is the current version.</p>'
        : _canEdit
        ? '<form method="post" action="/people/${p.id}/restore"><input type="hidden" name="number" value="${r.number}"><button>Restore this version</button> <span class="years">The current text is kept in the history.</span></form>'
        : ''}
<h2>What changed</h2>
${r.number == 1 ? '<p class="meta">The first version of the page.</p>' : ''}
${diff(previous?.source ?? '', r.source)}
${r.deleted ? '' : '<details class="whole"><summary>The whole page as it was</summary><pre class="source">${esc(r.source)}</pre></details>'}
''');
  }

  /// A line-by-line comparison, with unchanged stretches folded away.
  String diff(String before, String after) {
    final lines = diffLines(before, after);
    if (lines.every((l) => l.kind == DiffKind.same)) {
      return '<p class="lead">The two versions are identical.</p>';
    }
    // Keep two lines of context around each change.
    final keep = List.filled(lines.length, false);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].kind == DiffKind.same) continue;
      for (var j = i - 2; j <= i + 2; j++) {
        if (j >= 0 && j < lines.length) keep[j] = true;
      }
    }
    final sb = StringBuffer('<div class="diff">');
    var skipping = false;
    for (final (i, line) in lines.indexed) {
      if (!keep[i]) {
        if (!skipping) sb.write('<div class="skip">⋯</div>');
        skipping = true;
        continue;
      }
      skipping = false;
      final (cls, mark) = switch (line.kind) {
        DiffKind.same => ('same', ' '),
        DiffKind.removed => ('removed', '−'),
        DiffKind.added => ('added', '+'),
      };
      sb.write(
        '<div class="$cls"><span class="mark">$mark</span>${esc(line.text)}</div>',
      );
    }
    sb.write('</div>');
    return sb.toString();
  }

  String changes(List<Change> changes) {
    final sb = StringBuffer('<h1>Recent changes</h1>');
    if (changes.isEmpty) {
      sb.write('<p class="lead">Nothing has changed yet.</p>');
    } else {
      sb.write(
        '<p class="lead">Every change to the tree, newest first.</p><table class="history">',
      );
      for (final c in changes) {
        final pages = c.pages.length > 5
            ? '${c.pages.length} pages'
            : c.pages.entries
                  .map(
                    (e) =>
                        '${personLink(e.key)} <a class="years" href="/people/${e.key}/revisions/${e.value}">(what changed)</a>',
                  )
                  .join(', ');
        // A front and its back are one photo.
        final photos = c.media.where((key) => !key.endsWith('-back')).toList();
        final media = [
          for (final key in photos.take(5))
            '<a href="/media/$key">${esc(tree.media[key]?.title ?? 'a photo')}</a>',
          if (photos.length > 5) '${photos.length - 5} more',
        ].join(', ');
        final undo = _undoable(c)
            ? '<form method="post" action="/changes/${c.id}/undo"><button>Undo</button></form>'
            : '';
        sb.write(
          '<tr><td>${time(c.at)}</td><td>${esc(c.by)}</td><td>${esc(c.summary)}</td><td>$pages${pages.isNotEmpty && media.isNotEmpty ? ', ' : ''}$media</td><td>$undo</td></tr>',
        );
      }
      sb.write('</table>');
      sb.write(_summaryNote(changes.map((c) => c.summaryBy)));
    }
    return page('Recent changes', sb.toString());
  }

  /// Whether [c] can be undone in one step: every page it touched is still
  /// as it left them. Large changes, such as loading the tree, are not
  /// offered.
  bool _undoable(Change c) =>
      _canEdit &&
      c.media.isEmpty &&
      c.pages.length <= 10 &&
      c.pages.entries.every(
        (e) => (tree.people[e.key] ?? tree.deleted[e.key])?.revision == e.value,
      );

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// When something happened, as GitHub says it: "today", "3 days ago", or
  /// the date for anything older than a month.
  static String ago(DateTime at, [DateTime? now]) {
    final days = (now ?? DateTime.now()).difference(at).inDays;
    if (days < 1) return 'today';
    if (days < 2) return 'yesterday';
    if (days < 31) return '$days days ago';
    final t = at.toLocal();
    return 'on ${t.day} ${_monthNames[t.month - 1]} ${t.year}';
  }

  /// `12 Oct 2026, 20:46`, in the server's time zone.
  static String time(DateTime at) {
    final t = at.toLocal();
    return '${t.day} ${_monthNames[t.month - 1]} ${t.year}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String forbidden(String what) => page(
    'Not allowed',
    '<h1>Not allowed</h1><p class="lead">${esc(what)}</p>',
  );

  /// The page shown to someone who is not signed in. [config] is handed to
  /// the browser-side sign-in code.
  static String signIn(String treeName, Map<String, Object?> config) =>
      '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sign in · ${esc(treeName)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Sans+3:ital,wght@0,400;0,500;0,600;0,700;1,400&display=swap">
<link rel="stylesheet" href="/style.css">
</head>
<body>
<main class="sign-in">
<h1>${esc(treeName)}</h1>
<p class="lead">This family tree is private. Sign in with the Google account you were invited with.</p>
<p><button id="sign-in" class="primary">Sign in with Google</button></p>
<p id="message" class="message" role="alert"></p>
</main>
<script id="config" type="application/json">${jsonEncode(config).replaceAll('<', r'\u003c')}</script>
<script type="module" src="/assets/sign_in.js"></script>
</body>
</html>
''';

  /// The owner's settings for the tree: help from Claude.
  String settings(
    HelpSettings help, {
    required double spent,
    required bool available,
    List<Member> members = const [],
    String? error,
  }) => page('Settings', '''
<h1>Settings</h1>
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}
<h2 id="members">Members</h2>
<p>Only the people listed here can open the tree, by signing in with Google using this email address. Owners can also change these settings; editors can edit pages and add photos; viewers can read. Changes take effect within a minute.</p>
<table class="history members">
${[for (final m in members) _memberRow(m)].join('\n')}
</table>
<h3>Invite someone</h3>
<form class="memory invite" method="post" action="/settings/members">
  <input type="hidden" name="action" value="invite">
  <label for="invite_email">Their Google account's email address</label>
  <input id="invite_email" name="email" type="email" required placeholder="cousin@example.com">
  <label for="invite_role">What they may do</label>
  ${_roleSelect(Role.editor, id: 'invite_role')}
  <label>Who they are: their own page, or for someone without one, their nearest relative's. Their first visit starts there.</label>
  <div class="people-picker" data-name="person" data-single="true" data-initial="[]"></div>
  <div class="save"><button class="primary">Invite</button></div>
</form>
<p class="hint">Next you'll see an invitation to send them from your own email. Inviting someone already listed changes their role and who they are.</p>
<script type="module" src="/assets/photos.js"></script>
<h2>Help from Claude</h2>
<p>Members who can edit may ask Claude to draft or revise a page's story, and to tidy a memory. The text replaces what Claude was asked to act on in the editor, and nothing is saved until the member publishes it. Claude Haiku writes the one-line summary of each change.</p>
${available ? '' : '<p class="message">This server has no Anthropic API key, so help is not available whatever is set here. Set <code>ANTHROPIC_API_KEY</code> where the server runs.</p>'}
<form class="memory" method="post" action="/settings">
  <label class="check"><input type="checkbox" name="help"${help.enabled ? ' checked' : ''}> Members may ask Claude for help</label>
  <label for="monthly_limit">Monthly limit, in US dollars</label>
  <input id="monthly_limit" name="monthly_limit" type="number" min="0" step="1" value="${help.monthlyLimit.toStringAsFixed(0)}">
  <p class="hint">Spent this month: \$${spent.toStringAsFixed(2)}. When the limit is reached, help stops until the next month.</p>
  <div class="save"><button class="primary">Save</button></div>
</form>''');

  String _roleSelect(Role selected, {String? id}) =>
      '<select name="role"${id == null ? ' aria-label="Role"' : ' id="$id"'}>${[for (final role in Role.values) '<option value="${role.name}"${role == selected ? ' selected' : ''}>${role.name}</option>'].join()}</select>';

  String _memberRow(Member m) {
    final self = m.email == viewer?.email;
    final form =
        '<form method="post" action="/settings/members"><input type="hidden" name="email" value="${esc(m.email)}">';
    final who = m.person == null ? null : tree.people[m.person];
    return '<tr><td>${esc(m.name ?? '')}<br><span class="years">${esc(m.email)}</span></td>'
        '<td>${who == null ? '' : personLink(who.id)}</td>'
        '<td>${self ? '${m.role.name} (you)' : '$form${_roleSelect(m.role)} <button>Change</button></form>'}</td>'
        '<td>${self ? '' : '<a href="/settings/invitation?email=${Uri.encodeQueryComponent(m.email)}">Invitation</a>'}</td>'
        '<td>${self ? '' : '$form<input type="hidden" name="action" value="remove"><button>Remove</button></form>'}</td></tr>';
  }

  /// An invitation for [from] to send [member] from their own email, so it
  /// comes from someone the member knows.
  String invitation(
    Member member, {
    required Member from,
    required String address,
  }) {
    final person = member.person == null ? null : tree.people[member.person];
    final first = member.name?.split(' ').first;
    final subject = 'You\'re invited to the ${tree.name} history';
    final body = [
      'Hi${first == null ? '' : ' $first'},',
      '',
      'I\'ve added you to "${tree.name}", our family\'s history on Prosapia: a '
          'private website where the family keeps its stories, dates and '
          'photos together${member.role.canEdit ? ', and where anyone invited can add what they know and remember' : ''}.',
      '',
      'To visit, go to $address and sign in with your Google account, '
          '${member.email}.${person == null ? '' : ' You\'ll start at ${person.name}\'s page.'}',
      if (member.role.canEdit) ...[
        '',
        'Every change is kept, so nothing you do can be lost or break anything.',
      ],
      '',
      from.name ?? from.email,
    ].join('\n');
    final mailto = Uri(
      scheme: 'mailto',
      path: member.email,
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    return page('Invitation', '''
<h1>Invite ${esc(member.name ?? member.email)}</h1>
<p class="lead">${esc(member.email)} can now sign in. Send them this from your own email, so it comes from someone they know; change it as you like.</p>
<form class="memory invitation">
  <label for="subject">Subject</label>
  <input id="subject" value="${esc(subject)}" readonly>
  <label for="body">Message</label>
  <textarea id="body" readonly>${esc(body)}</textarea>
  <div class="save">
    <a class="button primary" href="${esc(mailto.toString())}">Open in your email</a>
    <button type="button" class="copy" data-copy="body">Copy the message</button>
    <a href="/settings#members">Back to Settings</a>
  </div>
</form>
<script>
document.querySelector('.copy').addEventListener('click', async (e) => {
  await navigator.clipboard.writeText(document.getElementById('body').value);
  e.target.textContent = 'Copied';
});
</script>''');
  }

  /// A short page that explains why something could not be done.
  String message(String title, String what) =>
      page(title, '<h1>${esc(title)}</h1><p class="lead">${esc(what)}</p>');

  String notFound(String what) =>
      page('Not found', '<h1>Not found</h1><p class="lead">${esc(what)}</p>');
}

const stylesheet = '''
/* "Archive": one humanist sans throughout, ink blue on a cool white. */
:root {
  --bg: #fbfcfd; --surface: #ffffff; --tint: #f3f5f9; --text: #1d2433; --muted: #5a6478;
  --line: #dfe4ec; --link: #24518a; --accent: #24518a; --on-accent: #ffffff; --mark: #fff1a8;
  --ui: "Source Sans 3", system-ui, -apple-system, "Segoe UI", sans-serif;
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #12161d; --surface: #19202a; --tint: #171c24; --text: #e3e8f0; --muted: #97a2b5;
          --line: #2a3240; --link: #9cc0ec; --accent: #3d6fae; --on-accent: #ffffff; --mark: #6b5a00; }
}
* { box-sizing: border-box; }
[hidden] { display: none !important; }
body { margin: 0; background: var(--bg); color: var(--text); font: 18px/1.6 var(--ui); }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
header { display: flex; flex-wrap: wrap; align-items: center; gap: 12px 24px;
         padding: 12px 24px; border-bottom: 1px solid var(--line); background: var(--tint);
         font-size: 16px; }
header .site { font-weight: 600; color: var(--text); }
header nav { display: flex; gap: 16px; flex: 1; }
header input { font: inherit; padding: 6px 10px; border: 1px solid var(--line); border-radius: 6px;
               background: var(--bg); color: var(--text); width: 220px; max-width: 100%; }
main { max-width: 960px; margin: 0 auto; padding: 24px 24px 64px; }
main.wide { max-width: 1100px; }
h1 { font-size: 2em; font-weight: 600; line-height: 1.15; letter-spacing: -0.005em; margin: 0 0 4px;
     text-wrap: balance; }
h2 { font-size: 1.15em; font-weight: 600; margin: 1.8em 0 0.5em; padding-bottom: 4px; text-wrap: balance;
     border-bottom: 1px solid var(--line); overflow: hidden; }
.lead, .years, .meta, .place, .empty, .snippet { color: var(--muted); }
.lead { margin: 0 0 1.2em; }
.years, .meta, .snippet { font-size: 0.88em; }
.place::before { content: " · "; }
.kind { font-variant: small-caps; letter-spacing: 0.03em; color: var(--muted); }
.empty { font-style: italic; }
.missing { color: var(--muted); font-style: italic; }
.infobox { float: right; width: 320px; margin: 0 0 16px 24px; padding: 12px; background: var(--tint);
           border: 1px solid var(--line); border-radius: 6px; font: 15px/1.5 var(--ui); }
.infobox img { display: block; width: 100%; border-radius: 4px; margin-bottom: 10px; }
.infobox table { border-collapse: collapse; width: 100%; }
.infobox th { text-align: left; vertical-align: top; padding: 4px 10px 4px 0; color: var(--muted);
              font-weight: 500; white-space: nowrap; }
.infobox td { padding: 4px 0; }
.prose { white-space: normal; }
.prose p { margin: 0 0 1em; }
.prose a { font-weight: 500; }
.timeline { border-collapse: collapse; }
.timeline th { text-align: right; vertical-align: top; padding: 4px 16px 4px 0; font-weight: 400;
               color: var(--muted); font-variant-numeric: tabular-nums; }
.timeline td { padding: 4px 0; }
.surnames { columns: 3 220px; column-gap: 32px; }
.surnames section { break-inside: avoid; margin-bottom: 16px; }
.surnames h2 { margin-top: 0; font-size: 1.1em; }
.surnames ul, .results { list-style: none; padding: 0; margin: 0; }
.results li { margin-bottom: 12px; }
mark { background: var(--mark); color: inherit; }
.gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 16px; }
.gallery a { display: block; font: 14px/1.4 var(--ui); color: var(--text);
             overflow-wrap: anywhere; }
.gallery img, .gallery .file { display: block; width: 100%; aspect-ratio: 1; object-fit: cover;
                               border-radius: 4px; border: 1px solid var(--line); margin-bottom: 6px; }
.gallery .file { display: grid; place-items: center; background: var(--surface); color: var(--muted);
                 font-weight: 600; letter-spacing: 0.05em; }
.media img { max-width: 100%; max-height: 80vh; border: 1px solid var(--line); border-radius: 4px; }
.description { white-space: pre-line; }
.problems, .issues { font: 14px/1.4 var(--ui); margin-bottom: 16px; }
.issues summary { color: var(--muted); cursor: pointer; }
.unresolved { text-decoration: underline dotted; text-underline-offset: 3px; color: var(--muted); cursor: help; }
.named { text-decoration: underline dotted; text-underline-offset: 3px; cursor: help; }
.date { cursor: help; }
a.add { font: 12px var(--ui); margin-left: 4px; white-space: nowrap; }
a.deleted { color: var(--muted); text-decoration: line-through; }
.contradictions summary { color: #b3261e; }
@media (prefers-color-scheme: dark) { .contradictions summary { color: #f2b8b5; } }
.resolve { display: flex; flex-wrap: wrap; gap: 6px; margin: 6px 0 10px; }
.resolve form { margin: 0; }
.resolve button { font-size: 13px; }
.help { margin-left: auto; display: flex; gap: 6px; align-items: center; }
.help.off { font: 13px var(--ui); color: var(--muted); }
.tabs .help button, .help button { font: 13px var(--ui); padding: 4px 10px; margin: 0 0 4px;
  border: 1px solid var(--line); border-radius: 6px; background: var(--surface); color: var(--text);
  cursor: pointer; }
.tabs .help button:hover:not(:disabled) { border-color: var(--link); color: var(--link); }
.tabs .help button:disabled { opacity: 0.45; cursor: default; }
.help-bar { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; padding: 8px 12px; margin: 8px 0;
  border: 1px solid var(--line); border-radius: 6px; background: var(--surface); font: 14px var(--ui); }
.help-bar[hidden] { display: none; }
.help-bar.error { border-color: #b3261e; }
.help-bar input { flex: 1; min-width: 200px; font: 14px var(--ui); padding: 5px 8px;
  border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--text); }
.cm-helped { background: rgba(140, 90, 220, 0.14); }
textarea.helped { background: rgba(140, 90, 220, 0.08); }
.tidy { margin: 8px 0 0; }
label.check { display: flex; gap: 8px; align-items: center; color: var(--text); font-size: 15px; }
label.check input { width: auto; }
.whole { margin-top: 16px; font: 14px var(--ui); }
.whole summary { cursor: pointer; color: var(--muted); }
.sides { display: grid; gap: 16px; }
.sides.two { grid-template-columns: 1fr 1fr; }
@media (max-width: 640px) { .sides.two { grid-template-columns: 1fr; } }
.sides figure { margin: 0; }
.sides figcaption { font: 13px var(--ui); color: var(--muted); margin-top: 4px; }
.media .sides img { max-width: 100%; }
.shown form { display: inline; margin-left: 8px; }
.shown button { font-size: 13px; }
img.thumb { display: block; max-width: 240px; max-height: 240px; border-radius: 4px; margin-top: 10px;
  border: 1px solid var(--line); }
.people-picker { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; padding: 6px;
  border: 1px solid var(--line); border-radius: 6px; background: var(--surface); position: relative; }
.people-picker .chip { display: inline-flex; gap: 4px; align-items: center; padding: 2px 4px 2px 10px;
  border-radius: 12px; background: var(--bg); border: 1px solid var(--line); font: 14px var(--ui); }
.people-picker .chip button { border: none; background: none; padding: 0 6px; color: var(--muted); }
.memory .people-picker input { flex: 1; min-width: 160px; border: none; padding: 4px; font: 15px var(--ui);
  background: transparent; width: auto; }
.people-picker .suggestions { position: absolute; top: 100%; left: 0; z-index: 10; min-width: 280px; margin-top: 4px;
  background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 4px 0;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); font: 14px var(--ui); }
.people-picker .suggestions div { padding: 6px 12px; cursor: pointer; }
.people-picker .suggestions div.active, .people-picker .suggestions div:hover { background: var(--bg); }
.people-picker .suggestions span { display: block; color: var(--muted); font-size: 12px; }
.photo-list { display: grid; gap: 16px; margin-top: 12px; }
.photo-card { display: grid; grid-template-columns: 160px 1fr; gap: 16px; padding: 12px;
  border: 1px solid var(--line); border-radius: 6px; background: var(--surface); }
@media (max-width: 640px) { .photo-card { grid-template-columns: 1fr; } }
.photo-card img { width: 160px; max-height: 200px; object-fit: contain; border-radius: 4px; background: var(--bg); }
.photo-card .status { font: 13px var(--ui); color: var(--muted); }
.photo-card label { margin-top: 8px; }
.memory .photo-card textarea, .edit-photo textarea { height: 7em; }
.photo-card button { font: 13px var(--ui); }
.photo-card .add-back { font: 13px var(--ui); margin-top: 10px; display: inline-block; }
.members form, .add-member { display: flex; gap: 8px; align-items: center; margin: 0; }
.add-member { margin-top: 12px; max-width: 640px; }
a.button.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
.invitation textarea { height: 16em; font: 15px/1.5 var(--ui); }
.invite select { display: block; }
.add-member input { flex: 1; font: 15px var(--ui); padding: 6px 10px; border: 1px solid var(--line);
  border-radius: 6px; background: var(--surface); color: var(--text); }
select { font: 14px var(--ui); padding: 4px 6px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); }
.start { display: flex; gap: 20px; align-items: flex-start; padding: 16px; margin: 8px 0 24px;
  background: var(--surface); border: 1px solid var(--line); border-radius: 8px; }
.start img { width: 160px; border-radius: 4px; display: block; }
.start h2 { margin-top: 0; border: none; }
.family { font: 16px/1.5 var(--ui); margin: 12px 0 0; }
.family dt { color: var(--muted); font-size: 14px; margin-top: 6px; }
.family dd { margin: 0; }
.try li { margin-bottom: 8px; }
/* A person's page: the title across the top, then the story beside the facts. */
.person-head { border-bottom: 1px solid var(--line); padding-bottom: 14px; margin-bottom: 24px; }
.person-head .title { display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: space-between;
  gap: 8px 24px; }
.person-head .name { display: flex; flex-wrap: wrap; align-items: baseline; gap: 0 14px;
  flex: 1 1 12em; min-width: 0; }
.person-head h1 { margin: 0; min-width: 0; }
.person-head .lead { margin: 0; }
.edited { font: 15px var(--ui); color: var(--muted); margin: 40px 0 0; padding-top: 12px;
  border-top: 1px solid var(--line); clear: both; }
.actions { display: flex; flex-wrap: wrap; gap: 8px 16px; margin: 0 0 12px; font: 15px var(--ui); }
.person-head .actions { gap: 8px; align-items: center; margin: 6px 0 0; }
.person-head .actions .button { padding: 5px 14px; font-size: 15px; }
details.more { position: relative; }
details.more summary { list-style: none; cursor: pointer; padding: 5px 12px; }
details.more summary::-webkit-details-marker { display: none; }
details.more .menu { position: absolute; right: 0; top: calc(100% + 4px); z-index: 10; min-width: 160px;
  padding: 4px 0; background: var(--surface); border: 1px solid var(--line); border-radius: 6px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); font: 15px var(--ui); }
details.more .menu a { display: block; padding: 6px 14px; color: var(--text); }
details.more .menu a:hover { background: var(--tint); text-decoration: none; }
@media (min-width: 1100px) {
  main > article.person { display: grid; grid-template-columns: minmax(0, 1fr) 320px; gap: 0 40px;
    align-items: start; }
  main > article.person > .infobox { grid-column: 2; grid-row: 1; float: none; width: auto; margin: 0; }
  main > article.person > .person-body, main > article.person > .editing { grid-column: 1; grid-row: 1; }
  main > article.person .preview .infobox { display: none; }
}
/* Below that, the facts float beside the story, so they make way for the editor. */
@media (max-width: 1099px) { main > article.editing-on > .infobox { display: none; } }
.format { display: flex; flex-wrap: wrap; gap: 2px; padding: 6px 8px; border-bottom: 1px solid var(--line); }
.format button { border: none; background: none; color: var(--muted); padding: 3px 8px; border-radius: 4px;
  font: 14px var(--ui); min-width: 28px; }
.format button:hover { background: var(--tint); color: var(--text); }
.format .sep { width: 1px; background: var(--line); margin: 2px 6px; }
.similar { list-style: none; padding: 0; font: 15px/1.5 var(--ui); }
.similar li { margin-bottom: 8px; }
.similar button { margin-left: 8px; font-size: 13px; }
.add-person fieldset { border: none; padding: 0; margin: 14px 0 0; }
.add-person legend { font: 13px/1.4 var(--ui); color: var(--muted); }
.add-person fieldset label { display: block; margin: 6px 0 0; color: var(--text); font-size: 15px; }
.add-person fieldset input { width: auto; margin-right: 6px; }
button.danger { background: #b3261e; border-color: #8c1d18; color: #fff; }
.legend { margin-top: 12px; font: 14px/1.5 var(--ui); color: var(--muted); }
.legend summary { cursor: pointer; }
.legend dt { margin-top: 8px; color: var(--text); }
.legend dd { margin: 2px 0 0 0; }
.legend code, label code { font-size: 12px; }
.editor .cm-editor { min-height: 60vh; background: var(--surface); color: var(--text);
  font: 15px/1.6 ui-monospace, Menlo, monospace; border-radius: 0 0 6px 6px; }
.editor .cm-editor .cm-content { min-height: 60vh; caret-color: var(--text); padding: 12px 4px; }
.editor .cm-editor .cm-cursor { border-left: 2px solid var(--text); }
.editor .cm-editor.cm-focused { outline: 2px solid var(--link); outline-offset: -1px; }
.editor .cm-editor .cm-selectionBackground,
.editor .cm-editor.cm-focused .cm-selectionBackground { background: rgba(66, 133, 244, 0.28); }
.editor .cm-scroller { font-family: inherit; }
.cm-label { color: var(--link); font-weight: 600; }
.cm-ref { color: var(--link); text-decoration: underline; text-underline-offset: 3px; }
.cm-marked { color: #8a5a00; }
@media (prefers-color-scheme: dark) { .cm-marked { color: #e0b35a; } }
.cm-heading { font-weight: 700; }
.cm-tooltip.cm-tooltip-autocomplete { font: 14px var(--ui); background: var(--surface);
  color: var(--text); border: 1px solid var(--line); border-radius: 6px; overflow: hidden;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); }
.cm-tooltip.cm-tooltip-autocomplete > ul { font-family: var(--ui); max-height: 18em; }
.cm-tooltip.cm-tooltip-autocomplete > ul > li { padding: 5px 12px; color: var(--text); }
.cm-tooltip.cm-tooltip-autocomplete > ul > li[aria-selected] { background: var(--link); color: var(--bg); }
.cm-tooltip-autocomplete .cm-completionDetail { color: var(--muted); margin-left: 10px; font-style: normal;
  font-size: 12px; }
.cm-tooltip-autocomplete ul li[aria-selected] .cm-completionDetail { color: inherit; opacity: 0.85; }
.search-suggestions { position: absolute; z-index: 10; background: var(--surface); border: 1px solid var(--line);
  border-radius: 6px; margin-top: 4px; min-width: 260px; max-width: 420px; padding: 4px 0;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); }
.search-suggestions a { display: block; padding: 6px 12px; color: var(--text); }
.search-suggestions a span { color: var(--muted); font-size: 12px; display: block; }
.search-suggestions a.active, .search-suggestions a:hover { background: var(--bg); text-decoration: none; }
header form { position: relative; }
.tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--line); margin-bottom: -1px; }
.tabs button { border: 1px solid transparent; border-bottom: none; border-radius: 6px 6px 0 0;
  background: none; color: var(--muted); padding: 8px 16px; font: 15px var(--ui); }
.tabs button[aria-selected=true] { border-color: var(--line); background: var(--surface); color: var(--text);
  margin-bottom: -1px; }
.tab-panel { border: 1px solid var(--line); border-top: none; border-radius: 0 0 6px 6px; background: var(--surface); }
.editor .preview { min-height: 60vh; padding: 16px 20px; }
.hint { font: 14px/1.5 var(--ui); color: var(--muted); margin: 20px 0 4px; }
.memory label { display: block; font: 14px/1.4 var(--ui); color: var(--muted); margin-bottom: 6px; }
.memory label { min-height: 0; margin-top: 14px; }
textarea, .save input, .memory input { font: 15px/1.5 ui-monospace, Menlo, monospace;
  width: 100%; padding: 10px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); }
.memory input, .memory textarea, .save input { font: 16px/1.5 var(--ui); }
.memory textarea { height: 30vh; }
.memory { max-width: 640px; }
.preview.stale { opacity: 0.55; }
.button { display: inline-block; padding: 9px 18px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); font: 15px var(--ui); }
.button:hover { text-decoration: none; background: var(--bg); }
button.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
button.primary kbd { font: 12px var(--ui); background: rgba(255,255,255,0.18); border-radius: 4px;
  padding: 2px 6px; margin-left: 6px; }
.save { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; margin-top: 16px;
  font: 15px var(--ui); }
.save label { margin: 0; min-height: 0; }
.editor .save { justify-content: flex-end; }
.save input { flex: 1; min-width: 240px; }
.conflict { border: 1px solid #b3261e; border-radius: 6px; padding: 4px 16px 16px; margin: 12px 0;
  font: 15px/1.5 var(--ui); }
.history { border-collapse: collapse; font: 15px/1.5 var(--ui); width: 100%; }
.history td { padding: 6px 12px 6px 0; border-bottom: 1px solid var(--line); vertical-align: top; }
.source, .diff { font: 14px/1.5 ui-monospace, Menlo, monospace; white-space: pre-wrap; overflow-wrap: anywhere;
  background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 12px; }
.diff > div { padding: 0 6px; }
.diff .mark { display: inline-block; width: 1.5em; color: var(--muted); user-select: none; }
.diff .added { background: rgba(46, 160, 67, 0.2); }
.diff .removed { background: rgba(218, 54, 51, 0.2); }
.diff .skip { color: var(--muted); text-align: center; }
.account { display: flex; align-items: center; gap: 10px; color: var(--muted); }
button { font: inherit; padding: 5px 12px; border: 1px solid var(--line); border-radius: 6px;
         background: var(--surface); color: var(--text); cursor: pointer; }
button.primary { font: 600 16px var(--ui); padding: 10px 20px; }
button:disabled { opacity: 0.6; cursor: default; }
.sign-in { max-width: 520px; padding-top: 12vh; }
.message { font: 16px/1.5 var(--ui); color: #b3261e; min-height: 1.5em; }
@media (max-width: 640px) {
  .infobox { float: none; width: auto; margin: 0 0 16px; }
  main { padding: 16px 16px 48px; }
}
/* Phones: one column, and nothing wider than the screen. */
@media (max-width: 700px) {
  header { padding: 10px 16px; gap: 8px 16px; }
  header nav { order: 3; flex-basis: 100%; gap: 14px; }
  header form.search { flex: 1; }
  header input { width: 100%; }
  main { padding: 16px 16px 48px; }
  h1 { font-size: 1.6em; }
  .infobox { float: none; width: auto; margin: 0 0 16px; }
  .history { display: block; overflow-x: auto; }
  .tabs { flex-wrap: wrap; }
  .tabs .help { margin-left: 0; flex-wrap: wrap; }
  .start { flex-direction: column; }
  .start img { width: 100%; max-width: 320px; }
  .timeline th { padding-right: 10px; white-space: normal; }
  .save { gap: 8px; }
  .save input { min-width: 0; }
}
''';
