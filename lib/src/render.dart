import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

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

  String page(String title, String body, {String query = ''}) =>
      '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · ${esc(tree.name)}</title>
<link rel="stylesheet" href="/style.css">
</head>
<body>
<header>
  <a class="site" href="/">${esc(tree.name)}</a>
  <nav><a href="/">People</a> <a href="/media">Photos</a>${editable ? ' <a href="/changes">Recent changes</a>' : ''}</nav>
  <form action="/search" class="search"><input type="search" name="q" autocomplete="off" value="${esc(query)}" placeholder="Search" aria-label="Search"></form>
  ${viewer == null ? '' : '<form class="account" method="post" action="/sign-out"><span title="${esc(viewer!.email)} · ${viewer!.role.name}">${esc(viewer!.name ?? viewer!.email)}</span> <button>Sign out</button></form>'}
</header>
<main>
$body
</main>
<script type="module" src="/assets/search.js"></script>
</body>
</html>
''';

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
    return '<a href="/people/${p.id}">${esc(p.name)}</a>$suffix';
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

  /// The last word of a person's name, for grouping the list of people.
  static String surnameOf(Person p) {
    final words = p.name.trim().split(RegExp(r'\s+'));
    return words.length > 1 ? words.last : 'Other';
  }

  // ---------------------------------------------------------------- person

  String person(Person p) {
    final actions = [
      if (_canEdit) '<a href="/people/${p.id}/edit">Edit</a>',
      if (_canEdit) '<a href="/people/${p.id}/memory">Add a memory</a>',
      if (editable) '<a href="/people/${p.id}/history">History</a>',
      if (_canEdit) '<a href="/people/${p.id}/delete">Delete</a>',
    ];
    return page(
      p.name,
      '${actions.isEmpty ? '' : '<p class="actions">${actions.join(' ')}</p>'}'
      '${personArticle(p)}',
    );
  }

  /// The body of a person's page. Also used for the editor's preview, where
  /// [p] is the text being typed and not yet part of the tree; a [preview]
  /// leaves out photos and actions.
  String personArticle(Person p, {bool preview = false}) {
    final sb = StringBuffer();
    final actions = _canEdit && !preview;
    sb.write('<article class="person">');
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
    sb.write(_infobox(p, actions: actions));
    sb.write('<h1>${esc(p.name)}</h1>');
    if (p.years.isNotEmpty) sb.write('<p class="lead">${p.years}</p>');

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
        : [for (final key in index.mediaOf(p.id)) tree.media[key]!];
    if (media.isNotEmpty) {
      sb.write('<h2>Photos and documents</h2>${gallery(media)}');
    }
    sb.write('</article>');
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
              : '<a href="/people/$id">${esc(person.name)}</a>';
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

  String mediaIndex() => page(
    'Photos',
    '<h1>Photos and documents</h1>'
        '<p class="lead">${tree.media.length} files. Titles and names are read from each file\'s embedded metadata.</p>'
        '${gallery(tree.media.values)}',
  );

  String media(Media m) {
    final sb = StringBuffer('<article class="media">');
    sb.write('<h1>${esc(m.title ?? 'Untitled')}</h1>');
    if (m.isImage) {
      sb.write(
        '<a href="/media/${m.key}/file"><img src="/media/${m.key}/display?w=1920" alt="${esc(m.title ?? '')}"></a>',
      );
    } else {
      sb.write(
        '<p><a class="file" href="/media/${m.key}/file">Open the ${m.extension.toUpperCase()} file</a></p>',
      );
    }
    final other = tree.media[m.isBack ? m.id : '${m.id}-back'];
    if (other != null) {
      sb.write(
        '<p><a href="/media/${other.key}">See the ${other.isBack ? 'back' : 'front'}</a></p>',
      );
    }
    if (m.description != null) {
      sb.write('<p class="description">${esc(m.description)}</p>');
    }
    if (m.people.isNotEmpty) {
      sb.write('<h2>People shown</h2><ul>');
      for (final id in m.people) {
        sb.write('<li>${personLink(id, years: true)}</li>');
      }
      sb.write('</ul>');
    }
    sb.write(
      '<p class="meta">${m.key}.${m.extension}${m.width == null ? '' : ' · ${m.width} × ${m.height}'} · <a href="/media/${m.key}/file">original file</a></p>',
    );
    sb.write('</article>');
    return page(m.title ?? 'Untitled', sb.toString());
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
  String editPerson(
    Person p, {
    required String source,
    required int basedOn,
    String summary = '',
    String? error,
    String? conflict,
  }) {
    return page('Edit ${p.name}', '''
<h1>Edit: ${esc(p.name)}</h1>
${conflict ?? ''}
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}
<form class="editor" method="post" action="/people/${p.id}/edit" data-preview="/people/${p.id}/preview">
  <input type="hidden" name="based_on" value="$basedOn">
  <div class="tabs" role="tablist">
    <button type="button" role="tab" id="tab-write" aria-selected="true" aria-controls="panel-write">Write</button>
    <button type="button" role="tab" id="tab-preview" aria-selected="false" aria-controls="panel-preview">Preview</button>
  </div>
  <div class="tab-panel" id="panel-write" role="tabpanel" aria-labelledby="tab-write">
    <textarea id="source" name="source" spellcheck="true" required aria-label="Page text">${esc(source)}</textarea>
  </div>
  <div class="tab-panel" id="panel-preview" role="tabpanel" aria-labelledby="tab-preview" hidden>
    <div id="preview" class="preview">${personArticle(p, preview: true)}</div>
  </div>
  <div class="save">
    <label for="summary">What did you change?</label>
    <input id="summary" name="summary" value="${esc(summary)}" maxlength="200" required placeholder="Added her years in Wales">
    <a class="button" href="/people/${p.id}">Cancel</a>
    <button class="primary" title="Save (⌘ Enter)">Save <kbd>⌘ ⏎</kbd></button>
  </div>
  <p class="hint">Facts first, one per line, starting with <code>Name:</code>; then a blank line and the story.</p>
  <details class="legend" open>
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
<script type="module" src="/assets/editor.js"></script>
''');
  }

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
  <label for="summary">Why?</label>
  <input id="summary" name="summary" value="Delete ${esc(p.name)}'s page" required maxlength="200">
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
  }) => page('Add a memory of ${p.name}', '''
<h1>Add a memory of ${esc(p.name)}</h1>
<p class="lead">A story, a trip, something you remember. It is added to the end of the page as its own section; nothing else on the page changes.</p>
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}
<form class="memory" method="post" action="/people/${p.id}/memory">
  <label for="title">Title</label>
  <input id="title" name="title" value="${esc(title)}" required maxlength="120" placeholder="Trip to Wales">
  <label for="date">When, if you know. A year is enough.</label>
  <input id="date" name="date" value="${esc(date)}" maxlength="40" placeholder="1923">
  <label for="text">The memory</label>
  <textarea id="text" name="text" required spellcheck="true">${esc(text)}</textarea>
  <div class="save"><button class="primary">Add</button> <a href="/people/${p.id}">Cancel</a></div>
</form>
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
      '<p class="lead">${revisions.length} saved ${revisions.length == 1 ? 'version' : 'versions'}, newest first. Pick two to compare.</p>',
    );
    sb.write('<form action="/people/${p.id}/compare"><table class="history">');
    for (final (i, r) in revisions.indexed) {
      sb.write(
        '<tr>'
        '<td><input type="radio" name="from" value="${r.number}" aria-label="Compare from version ${r.number}"${i == 1 || revisions.length == 1 ? ' checked' : ''}></td>'
        '<td><input type="radio" name="to" value="${r.number}" aria-label="Compare to version ${r.number}"${i == 0 ? ' checked' : ''}></td>'
        '<td><a href="/people/${p.id}/revisions/${r.number}">${time(r.at)}</a></td>'
        '<td>${esc(r.by)}</td>'
        '<td>${esc(r.summary)}${r.deleted
            ? ' <span class="years">(page deleted)</span>'
            : i == 0
            ? ' <span class="years">(current)</span>'
            : ''}</td>'
        '</tr>',
      );
    }
    sb.write(
      '</table>${revisions.length > 1 ? '<p><button>Compare</button></p>' : ''}</form>',
    );
    return page('History of ${p.name}', sb.toString());
  }

  String revision(
    Person p,
    Revision r, {
    required bool isCurrent,
  }) => page('${p.name}, version ${r.number}', '''
<h1>${personLink(p.id)}: version ${r.number}</h1>
<p class="lead">Saved ${time(r.at)} by ${esc(r.by)}: “${esc(r.summary)}”. <a href="/people/${p.id}/history">All versions</a></p>
${r.deleted
      ? '<p class="lead">This version deleted the page.</p>'
      : isCurrent
      ? '<p class="lead">This is the current version.</p>'
      : _canEdit
      ? '<form method="post" action="/people/${p.id}/restore"><input type="hidden" name="number" value="${r.number}"><button>Restore this version</button> <span class="years">The current text is kept in the history.</span></form>'
      : ''}
<pre class="source">${esc(r.source)}</pre>
''');

  String compare(Person p, Revision from, Revision to) =>
      page('Compare versions of ${p.name}', '''
<h1>${personLink(p.id)}: version ${from.number} to ${to.number}</h1>
<p class="lead">${from.number == 0 ? 'From before the page existed' : 'From <a href="/people/${p.id}/revisions/${from.number}">${time(from.at)}</a> by ${esc(from.by)}'}, to <a href="/people/${p.id}/revisions/${to.number}">${time(to.at)}</a> by ${esc(to.by)}. <a href="/people/${p.id}/history">All versions</a></p>
${diff(from.source, to.source)}
''');

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
                        '${personLink(e.key)} <a class="years" href="/people/${e.key}/compare?from=${e.value - 1}&amp;to=${e.value}">(what changed)</a>',
                  )
                  .join(', ');
        final undo = _undoable(c)
            ? '<form method="post" action="/changes/${c.id}/undo"><button>Undo</button></form>'
            : '';
        sb.write(
          '<tr><td>${time(c.at)}</td><td>${esc(c.by)}</td><td>${esc(c.summary)}</td><td>$pages</td><td>$undo</td></tr>',
        );
      }
      sb.write('</table>');
    }
    return page('Recent changes', sb.toString());
  }

  /// Whether [c] can be undone in one step: every page it touched is still
  /// as it left them. Large changes, such as loading the tree, are not
  /// offered.
  bool _undoable(Change c) =>
      _canEdit &&
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

  /// A short page that explains why something could not be done.
  String message(String title, String what) =>
      page(title, '<h1>${esc(title)}</h1><p class="lead">${esc(what)}</p>');

  String notFound(String what) =>
      page('Not found', '<h1>Not found</h1><p class="lead">${esc(what)}</p>');
}

const stylesheet = '''
:root {
  --bg: #fbfaf7; --surface: #ffffff; --text: #1f1d1a; --muted: #6b665e;
  --line: #e2ded5; --link: #1a5a96; --mark: #fff1a8;
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #191817; --surface: #222120; --text: #ebe8e1; --muted: #a39e94;
          --line: #3a3835; --link: #8ab8e6; --mark: #6b5a00; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
       font: 17px/1.6 Georgia, "Iowan Old Style", "Times New Roman", serif; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
header { display: flex; flex-wrap: wrap; align-items: center; gap: 12px 24px;
         padding: 12px 24px; border-bottom: 1px solid var(--line); background: var(--surface);
         font-family: system-ui, sans-serif; font-size: 15px; }
header .site { font-weight: 600; color: var(--text); }
header nav { display: flex; gap: 16px; flex: 1; }
header input { font: inherit; padding: 6px 10px; border: 1px solid var(--line); border-radius: 6px;
               background: var(--bg); color: var(--text); width: 220px; max-width: 100%; }
main { max-width: 960px; margin: 0 auto; padding: 24px 24px 64px; }
h1 { font-size: 2em; font-weight: 500; line-height: 1.2; margin: 0 0 4px; }
h2 { font-size: 1.3em; font-weight: 500; margin: 1.8em 0 0.5em; padding-bottom: 4px;
     border-bottom: 1px solid var(--line); overflow: hidden; }
.lead, .years, .meta, .place, .empty, .snippet { color: var(--muted); }
.lead { margin: 0 0 1.2em; }
.years, .meta, .snippet { font-size: 0.88em; }
.place::before { content: " · "; }
.kind { font-variant: small-caps; letter-spacing: 0.03em; color: var(--muted); }
.empty { font-style: italic; }
.missing { color: var(--muted); font-style: italic; }
.infobox { float: right; width: 300px; margin: 0 0 16px 24px; padding: 12px; background: var(--surface);
           border: 1px solid var(--line); border-radius: 6px; font: 14px/1.45 system-ui, sans-serif; }
.infobox img { display: block; width: 100%; border-radius: 4px; margin-bottom: 10px; }
.infobox table { border-collapse: collapse; width: 100%; }
.infobox th { text-align: left; vertical-align: top; padding: 4px 10px 4px 0; color: var(--muted);
              font-weight: 500; white-space: nowrap; }
.infobox td { padding: 4px 0; }
.prose { white-space: normal; }
.prose p { margin: 0 0 1em; }
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
.gallery a { display: block; font: 13px/1.35 system-ui, sans-serif; color: var(--text);
             overflow-wrap: anywhere; }
.gallery img, .gallery .file { display: block; width: 100%; aspect-ratio: 1; object-fit: cover;
                               border-radius: 4px; border: 1px solid var(--line); margin-bottom: 6px; }
.gallery .file { display: grid; place-items: center; background: var(--surface); color: var(--muted);
                 font-weight: 600; letter-spacing: 0.05em; }
.media img { max-width: 100%; max-height: 80vh; border: 1px solid var(--line); border-radius: 4px; }
.description { white-space: pre-line; }
.problems, .issues { font: 14px/1.4 system-ui, sans-serif; margin-bottom: 16px; }
.issues summary { color: var(--muted); cursor: pointer; }
.unresolved { text-decoration: underline dotted; text-underline-offset: 3px; color: var(--muted); cursor: help; }
.named { text-decoration: underline dotted; text-underline-offset: 3px; cursor: help; }
.date { cursor: help; }
a.add { font: 12px system-ui, sans-serif; margin-left: 4px; white-space: nowrap; }
a.deleted { color: var(--muted); text-decoration: line-through; }
.contradictions summary { color: #b3261e; }
@media (prefers-color-scheme: dark) { .contradictions summary { color: #f2b8b5; } }
.resolve { display: flex; flex-wrap: wrap; gap: 6px; margin: 6px 0 10px; }
.resolve form { margin: 0; }
.resolve button { font-size: 13px; }
.similar { list-style: none; padding: 0; font: 15px/1.5 system-ui, sans-serif; }
.similar li { margin-bottom: 8px; }
.similar button { margin-left: 8px; font-size: 13px; }
.add-person fieldset { border: none; padding: 0; margin: 14px 0 0; }
.add-person legend { font: 13px/1.4 system-ui, sans-serif; color: var(--muted); }
.add-person fieldset label { display: block; margin: 6px 0 0; color: var(--text); font-size: 15px; }
.add-person fieldset input { width: auto; margin-right: 6px; }
button.danger { background: #b3261e; border-color: #8c1d18; color: #fff; }
.legend { margin-top: 12px; font: 13px/1.5 system-ui, sans-serif; color: var(--muted); }
.legend summary { cursor: pointer; }
.legend dt { margin-top: 8px; color: var(--text); }
.legend dd { margin: 2px 0 0 0; }
.legend code, label code { font-size: 12px; }
.editor .cm-editor { min-height: 60vh; background: var(--surface); color: var(--text);
  font: 14px/1.6 ui-monospace, Menlo, monospace; border-radius: 0 0 6px 6px; }
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
.cm-tooltip.cm-tooltip-autocomplete { font: 14px system-ui, sans-serif; background: var(--surface);
  color: var(--text); border: 1px solid var(--line); border-radius: 6px; overflow: hidden;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); }
.cm-tooltip.cm-tooltip-autocomplete > ul { font-family: system-ui, sans-serif; max-height: 18em; }
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
.actions { display: flex; gap: 16px; margin: 0 0 12px; font: 14px system-ui, sans-serif; }
.tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--line); margin-bottom: -1px; }
.tabs button { border: 1px solid transparent; border-bottom: none; border-radius: 6px 6px 0 0;
  background: none; color: var(--muted); padding: 8px 16px; font: 14px system-ui, sans-serif; }
.tabs button[aria-selected=true] { border-color: var(--line); background: var(--surface); color: var(--text);
  margin-bottom: -1px; }
.tab-panel { border: 1px solid var(--line); border-top: none; border-radius: 0 0 6px 6px; background: var(--surface); }
.editor .preview { min-height: 60vh; padding: 16px 20px; font-size: 16px; }
.hint { font: 13px/1.5 system-ui, sans-serif; color: var(--muted); margin: 20px 0 4px; }
.memory label { display: block; font: 13px/1.4 system-ui, sans-serif; color: var(--muted); margin-bottom: 6px; }
.memory label { min-height: 0; margin-top: 14px; }
textarea, .save input, .memory input { font: 14px/1.5 ui-monospace, Menlo, monospace;
  width: 100%; padding: 10px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); }
.memory input, .memory textarea, .save input { font: 16px/1.5 Georgia, serif; }
.memory textarea { height: 30vh; }
.memory { max-width: 640px; }
.preview.stale { opacity: 0.55; }
.button { display: inline-block; padding: 9px 18px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); font: 15px system-ui, sans-serif; }
.button:hover { text-decoration: none; background: var(--bg); }
button.primary { background: #2f7d32; border-color: #2a6f2d; color: #fff; }
button.primary kbd { font: 12px system-ui, sans-serif; background: rgba(255,255,255,0.18); border-radius: 4px;
  padding: 2px 6px; margin-left: 6px; }
.save { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; margin-top: 16px;
  font: 14px system-ui, sans-serif; }
.save label { margin: 0; min-height: 0; }
.save input { flex: 1; min-width: 240px; }
.conflict { border: 1px solid #b3261e; border-radius: 6px; padding: 4px 16px 16px; margin: 12px 0;
  font: 15px/1.5 system-ui, sans-serif; }
.history { border-collapse: collapse; font: 14px/1.5 system-ui, sans-serif; width: 100%; }
.history td { padding: 6px 12px 6px 0; border-bottom: 1px solid var(--line); vertical-align: top; }
.source, .diff { font: 13px/1.5 ui-monospace, Menlo, monospace; white-space: pre-wrap; overflow-wrap: anywhere;
  background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 12px; }
.diff > div { padding: 0 6px; }
.diff .mark { display: inline-block; width: 1.5em; color: var(--muted); user-select: none; }
.diff .added { background: rgba(46, 160, 67, 0.2); }
.diff .removed { background: rgba(218, 54, 51, 0.2); }
.diff .skip { color: var(--muted); text-align: center; }
.account { display: flex; align-items: center; gap: 10px; color: var(--muted); }
button { font: inherit; padding: 5px 12px; border: 1px solid var(--line); border-radius: 6px;
         background: var(--surface); color: var(--text); cursor: pointer; }
button.primary { font: 600 16px system-ui, sans-serif; padding: 10px 20px; }
button:disabled { opacity: 0.6; cursor: default; }
.sign-in { max-width: 520px; padding-top: 12vh; }
.message { font: 15px/1.5 system-ui, sans-serif; color: #b3261e; min-height: 1.5em; }
@media (max-width: 640px) {
  .infobox { float: none; width: auto; margin: 0 0 16px; }
  main { padding: 16px 16px 48px; }
}
''';
