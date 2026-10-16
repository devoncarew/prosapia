import 'package:sqlite3/sqlite3.dart';

import 'tree.dart';

/// Search and relationship lookups over a [Tree]. It holds nothing original
/// and lives in memory: it is rebuilt whenever the tree is loaded.
///
/// A relationship may be stated on either person's page; the index combines
/// both sides, so each page shows it.
class Index {
  Index._(this._db);

  final Database _db;

  static Index build(Tree tree) {
    final db = sqlite3.openInMemory();
    db.execute('''
      create table person (id text primary key, name text, born integer);
      create table parent (child text, parent text, unique (child, parent));
      create table sibling (a text, b text, unique (a, b));
      create table partnership (a text, b text, married integer, unique (a, b));
      create table shown (media text, person text);
      create virtual table search using fts5(kind unindexed, id unindexed, title, body);
      create index parent_child on parent (child);
      create index parent_parent on parent (parent);
      create index shown_person on shown (person);
    ''');
    db.execute('begin');
    final people = tree.people;
    bool known(PersonRef r) => r.id != null && people.containsKey(r.id);

    for (final p in people.values) {
      db.execute('insert into person values (?, ?, ?)', [
        p.id,
        p.name,
        p.born?.date?.sortKey ?? 99999999,
      ]);
      for (final r in p.parents.where(known)) {
        db.execute('insert or ignore into parent values (?, ?)', [p.id, r.id]);
      }
      for (final r in p.children.where(known)) {
        db.execute('insert or ignore into parent values (?, ?)', [r.id, p.id]);
      }
      for (final r in p.siblings.where(known)) {
        final (a, b) = _pair(p.id, r.id!);
        db.execute('insert or ignore into sibling values (?, ?)', [a, b]);
      }
      final partners = <String, int>{
        for (final r in p.partners.where(known)) r.id!: 99999999,
        for (final c in p.couples)
          if (c.partner != null && known(c.partner!))
            c.partner!.id!: c.event.date?.sortKey ?? 99999999,
      };
      partners.forEach((other, married) {
        final (a, b) = _pair(p.id, other);
        db.execute(
          'insert into partnership values (?, ?, ?) '
          'on conflict (a, b) do update set married = min(married, excluded.married)',
          [a, b, married],
        );
      });
      db.execute('insert into search values (?, ?, ?, ?)', [
        'person',
        p.id,
        [p.name, ...p.nicknames, ...p.alsoKnownAs].join(' '),
        [
          p.born?.place,
          p.died?.place,
          p.buried?.place,
          for (final f in p.facts) ...[f.description, f.event.place],
          ...p.notes,
          p.body,
        ].nonNulls.join('\n'),
      ]);
    }
    for (final m in tree.media.values) {
      for (final person in m.people) {
        db.execute('insert into shown values (?, ?)', [m.key, person]);
      }
      db.execute('insert into search values (?, ?, ?, ?)', [
        'media',
        m.key,
        m.title ?? '',
        m.description ?? '',
      ]);
    }
    db.execute('commit');
    return Index._(db);
  }

  static (String, String) _pair(String x, String y) =>
      x.compareTo(y) < 0 ? (x, y) : (y, x);

  List<String> _ids(String sql, List<Object?> args) => [
    for (final row in _db.select(sql, args)) row.values.first as String,
  ];

  /// Parents with pages, whichever page states the relationship.
  List<String> parentsOf(String id) => _ids(
    '''
      select parent from parent join person on person.id = parent
      where child = ? order by born, name''',
    [id],
  );

  /// Children with pages, eldest first.
  List<String> childrenOf(String id) => _ids(
    '''
      select child from parent join person on person.id = child
      where parent = ? order by born, name''',
    [id],
  );

  /// Everyone who shares a parent, or is stated to be a sibling, eldest first.
  List<String> siblingsOf(String id) => _ids(
    '''
      select id from person where id != ?1 and id in (
        select b.child from parent a join parent b on a.parent = b.parent where a.child = ?1
        union select b from sibling where a = ?1
        union select a from sibling where b = ?1)
      order by born, name''',
    [id],
  );

  /// Partners with pages, earliest marriage first.
  List<String> partnersOf(String id) => _ids(
    '''
      select case when a = ?1 then b else a end from partnership
      where a = ?1 or b = ?1 order by married''',
    [id],
  );

  /// Media keys of the files that show the person.
  List<String> mediaOf(String id) =>
      _ids('select media from shown where person = ? order by media', [id]);

  List<String> peopleByName() =>
      _ids('select id from person order by name, born', const []);

  /// Full-text search over people and media. Each word matches as a prefix.
  List<({String kind, String id, String snippet})> search(String query) {
    final words = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(query).map((m) => '"${m[0]}"*').join(' ');
    if (words.isEmpty) return const [];
    return [
      for (final row in _db.select(
        '''
          select kind, id, snippet(search, 3, '<mark>', '</mark>', ' … ', 16) as s
          from search where search match ? order by rank limit 100''',
        [words],
      ))
        (
          kind: row['kind'] as String,
          id: row['id'] as String,
          snippet: row['s'] as String,
        ),
    ];
  }

  void close() => _db.close();
}
