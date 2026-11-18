import 'contradictions.dart';
import 'index.dart';
import 'page_syntax.dart';
import 'render.dart';
import 'tree.dart';

/// What `prosapia:research` reads from a tree for an agent researching a
/// person: a page with its family and items, what it lacks, and who in the
/// tree matches a name. Every answer is a JSON-ready map.
class Research {
  Research(this.tree) : index = Index.build(tree) {
    _render = Renderer(tree, index);
  }

  final Tree tree;
  final Index index;
  late final Renderer _render;

  /// The page [reference] names: a person or a page about something else,
  /// given as `@carew-michael-k3m9qa`, `carew-michael-k3m9qa`, `p-k3m9qa`,
  /// `#carew-family-k3m9qa` or `w-k3m9qa`. Null if there is none.
  Page? pageOf(String reference) {
    final r = reference.trim();
    final suffix = itemIdOf(r.replaceFirst('@', ''));
    if (r.startsWith('w-') || r.startsWith('#')) {
      return tree.pages['${WikiPage.prefix}-$suffix'];
    }
    return tree.people['p-$suffix'] ?? tree.pages['${WikiPage.prefix}-$suffix'];
  }

  /// What on [page] could not be read, or refers to nothing in the tree.
  List<String> issuesOf(Page page) =>
      page is Person ? _render.issuesOf(page) : page.issues;

  /// A page as written and as read: its text and revision, its facts, its
  /// family, the items that show it or that it cites, and the pages that
  /// mention it.
  Map<String, Object?> show(Page page) {
    if (page is WikiPage) {
      return {
        'id': page.id,
        'reference': page.reference,
        'title': page.title,
        ..._edited(page),
        'source': page.source,
        'mentions': [for (final id in page.mentioned) _brief(id)],
        'items': [for (final m in _itemsOf(page)) _item(m)],
        'issues': page.issues,
      };
    }
    final p = page as Person;
    return {
      'id': p.id,
      'reference': p.reference,
      'name': p.name,
      if (p.alsoKnownAs.isNotEmpty) 'alsoKnownAs': p.alsoKnownAs,
      if (p.nicknames.isNotEmpty) 'nicknames': p.nicknames,
      'years': p.years,
      ..._edited(p),
      'source': p.source,
      'facts': [
        for (final line in ParsedPage.parse(p.source).facts)
          {
            'label': line.label,
            'value': line.value,
            if (_sourcesOf(line) case final s when s.isNotEmpty) 'sources': s,
          },
      ],
      'events': {
        for (final (label, e) in [
          ('born', p.born),
          ('christened', p.christened),
          ('died', p.died),
          ('buried', p.buried),
        ])
          if (e != null)
            label: {
              ..._event(e),
              if (p.alternativesTo(e).isNotEmpty)
                'alsoRecorded': [
                  for (final a in p.alternativesTo(e)) _event(a),
                ],
            },
      },
      if (p.externalIds.isNotEmpty) 'externalIds': p.externalIds,
      'family': {
        'parents': [for (final id in index.parentsOf(p.id)) _brief(id)],
        'partners': [for (final id in index.partnersOf(p.id)) _brief(id)],
        'children': [for (final id in index.childrenOf(p.id)) _brief(id)],
        'siblings': [for (final id in index.siblingsOf(p.id)) _brief(id)],
        ..._named(p),
      },
      'items': [for (final m in _itemsOf(p)) _item(m)],
      'mentionedOn': [
        for (final other in [...tree.people.values, ...tree.pages.values])
          if (other.id != p.id && _mentions(other.source, p.id))
            {'id': other.id, 'title': other.title},
      ],
      if (p.families.isNotEmpty)
        'familyPages': [
          for (final id in p.families)
            {'id': id, 'title': tree.pages[id]?.title},
        ],
    };
  }

  /// What [p]'s page lacks: empty facts, facts without a source, sources
  /// marked as wanted, and what does not fit with the rest of the tree.
  Map<String, Object?> gaps(Person p) {
    final citations = _render.citationsOn(p);
    return {
      'id': p.id,
      'name': p.name,
      'empty': [
        for (final line in ParsedPage.parse(p.source).facts)
          if (line.key != 'name' && line.value.trim().isEmpty) line.label,
      ],
      'missing': [
        if (p.born == null && p.christened == null) 'Born',
        if (p.died == null && p.buried == null) 'Died',
        if (index.parentsOf(p.id).isEmpty && p.parents.isEmpty) 'Parents',
      ],
      'unsourced': [
        for (final (label, e) in [
          ('Born', p.born),
          ('Christened', p.christened),
          ('Died', p.died),
          ('Buried', p.buried),
        ])
          for (final event in [?e, ...p.alternativesTo(e)])
            if (event.sources.isEmpty) '$label: ${_describe(event)}',
        for (final c in p.couples)
          if (c.event.sources.isEmpty)
            '${c.kind}: ${[c.partner?.name ?? tree.people[c.partner?.id]?.name, _describe(c.event)].nonNulls.where((s) => s.isNotEmpty).join(', ')}',
        for (final f in p.facts)
          if (f.event.sources.isEmpty)
            '${f.label}: ${[f.description, _describe(f.event)].where((s) => s.isNotEmpty).join(', ')}',
      ],
      'wanted': [
        for (final c in citations)
          if (Renderer.isWanted(c.source)) c.where,
      ],
      'contradictions': [for (final c in contradictionsOf(tree, p)) c.message],
      'checks': _render.checksOf(p),
      'issues': _render.issuesOf(p),
    };
  }

  /// People whose names match every word of [name], each as the start of a
  /// word in a name they are known by. With [born], only those born within
  /// [within] years of it, or with no birth year; with [place], only those
  /// with an event or fact there.
  List<Map<String, Object?>> find(
    String name, {
    int? born,
    int within = 5,
    String? place,
  }) {
    final words = _words(name);
    if (words.isEmpty) return const [];
    final found = <(int, Person)>[];
    for (final p in tree.people.values) {
      final names = _words(
        [p.name, ...p.alsoKnownAs, ...p.nicknames, ?p.familyName].join(' '),
      );
      if (!words.every((w) => names.any((n) => n.startsWith(w)))) continue;
      final year = (p.born ?? p.christened)?.date?.year;
      if (born != null && year != null && (year - born).abs() > within) {
        continue;
      }
      if (place != null && !_placesOf(p).any((s) => _has(s, place))) continue;
      // Exact words, then a known birth year near the one given, rank first.
      var score = words.where(names.contains).length * 10;
      if (born != null && year != null) score += 10 - (year - born).abs();
      found.add((score, p));
    }
    found.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : a.$2.name.compareTo(b.$2.name);
    });
    return [
      for (final (_, p) in found.take(50))
        {
          ..._brief(p.id),
          if (p.born case final e?) 'born': _event(e),
          if (p.died case final e?) 'died': _event(e),
          'parents': [
            for (final id in index.parentsOf(p.id)) tree.people[id]!.name,
          ],
          'partners': [
            for (final id in index.partnersOf(p.id)) tree.people[id]!.name,
          ],
        },
    ];
  }

  Map<String, Object?> _edited(Page page) => {
    'revision': page.revision,
    if (page.editedBy != null) 'editedBy': page.editedBy,
    if (page.editedAt != null) 'editedAt': page.editedAt!.toIso8601String(),
  };

  Map<String, Object?> _brief(String id) {
    final p = tree.people[id];
    if (p == null) return {'id': id, 'title': tree.pages[id]?.title};
    return {
      'id': id,
      'reference': p.reference,
      'name': p.name,
      if (p.years.isNotEmpty) 'years': p.years,
    };
  }

  /// People named in relationship lines who have no page.
  Map<String, Object?> _named(Person p) => {
    for (final (key, refs) in [
      ('namedParents', p.parents),
      ('namedPartners', [...p.partners, for (final c in p.couples) ?c.partner]),
      ('namedChildren', p.children),
      ('namedSiblings', p.siblings),
    ])
      if (refs.where((r) => r.name != null).toList() case final named
          when named.isNotEmpty)
        key: [for (final r in named) r.name],
  };

  Map<String, Object?> _event(Event e) => {
    if (e.date case final d?) 'date': d.raw,
    if (e.date case final d? when d.understood) 'dateMeaning': d.meaning,
    if (e.place != null) 'place': e.place,
    if (e.sources.isNotEmpty) 'sources': e.sources,
  };

  String _describe(Event e) => [e.date?.raw, e.place].nonNulls.join(', ');

  List<String> _sourcesOf(FactLine line) => [
    for (final s in line.segments)
      if (s is SourceSegment) s.source,
  ];

  /// Items that show [page]'s person, or that it cites or mentions with `#`,
  /// in the order of their ids.
  List<Media> _itemsOf(Page page) {
    final keys = <String>{
      for (final m in tree.media.values)
        if (m.people.contains(page.id)) m.key,
      for (final m in proseItemRef.allMatches(page.source))
        if (itemOf(tree, m[1]!) case final item?) item.key,
      if (page is Person) ?page.photo,
    };
    return [for (final key in keys.toList()..sort()) ?tree.media[key]];
  }

  Map<String, Object?> _item(Media m) => {
    'id': m.key,
    'reference': '#${m.key}',
    'kind': m.kind,
    if (m.title != null) 'title': m.title,
    if (m.date != null) 'date': m.date,
    if (m.place != null) 'place': m.place,
    if (m.link != null) 'link': m.link,
    if (m.found != null) 'found': m.found,
    if (m.hasFile) 'file': m.fileName,
    'people': m.people,
    if (m.transcription != null) 'transcription': m.transcription,
    if (m.notes != null) 'notes': m.notes,
  };

  /// Whether [source] refers to the person [id] with `@`.
  static bool _mentions(String source, String id) {
    final suffix = id.substring(2);
    return RegExp(
      '(?<![\\w@.])@(?:[a-z0-9]+-)*$suffix(?![a-z0-9])',
    ).hasMatch(source);
  }

  Iterable<String> _placesOf(Person p) => [
    for (final e in [p.born, p.christened, p.died, p.buried]) ?e?.place,
    for (final c in p.couples) ?c.event.place,
    for (final f in p.facts) ...[?f.event.place, f.description],
  ];

  static bool _has(String text, String part) =>
      text.toLowerCase().contains(part.toLowerCase());

  static List<String> _words(String text) => [
    for (final m in RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(text))
      m[0]!.toLowerCase(),
  ];
}
