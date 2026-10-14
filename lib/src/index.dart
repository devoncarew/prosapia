import 'package:sqlite3/sqlite3.dart';

import 'tree.dart';

/// Search and relationship lookups over a [Tree]. It holds nothing original
/// and lives in memory: it is rebuilt whenever the tree is loaded.
class Index {
  Index._(this._db);

  final Database _db;

  static Index build(Tree tree) {
    final db = sqlite3.openInMemory();
    db.execute('''
      create table person (id text primary key, name text, surname text, born integer);
      create table parent (child text, parent text);
      create table partnership (id text, a text, b text, married integer);
      create table shown (media text, person text);
      create virtual table search using fts5(kind unindexed, id unindexed, title, body);
      create index parent_child on parent (child);
      create index parent_parent on parent (parent);
      create index shown_person on shown (person);
    ''');
    db.execute('begin');
    for (final p in tree.people.values) {
      db.execute('insert into person values (?, ?, ?, ?)', [
        p.id,
        p.name,
        p.surname ?? '',
        p.born?.date?.sortKey ?? 99999999,
      ]);
      for (final link in p.parents) {
        db.execute('insert into parent values (?, ?)', [p.id, link.id]);
      }
      db.execute('insert into search values (?, ?, ?, ?)', [
        'person',
        p.id,
        [p.name, ...p.alsoKnownAs].join(' '),
        [
          p.born?.place,
          p.died?.place,
          for (final f in p.facts) ...[f.value, f.event.place],
          p.body,
        ].nonNulls.join('\n'),
      ]);
    }
    for (final u in tree.unions.values) {
      if (u.partners.length < 2) continue;
      db.execute('insert into partnership values (?, ?, ?, ?)', [
        u.id,
        u.partners[0],
        u.partners[1],
        u.married?.date?.sortKey ?? 99999999, //
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

  List<String> _ids(String sql, List<Object?> args) => [
    for (final row in _db.select(sql, args)) row.values.first as String,
  ];

  /// Children, eldest first.
  List<String> childrenOf(String id) => _ids(
    '''
      select child from parent join person on person.id = child
      where parent = ? order by born, name''',
    [id],
  );

  /// Everyone who shares a parent, eldest first.
  List<String> siblingsOf(String id) => _ids(
    '''
      select distinct b.child from parent a
      join parent b on a.parent = b.parent and b.child != a.child
      join person on person.id = b.child
      where a.child = ? order by born, name''',
    [id],
  );

  /// Ids of the partnership records the person is in, earliest first.
  List<String> partnershipsOf(String id) => _ids(
    'select id from partnership where a = ?1 or b = ?1 order by married',
    [id],
  );

  /// Media keys of the files that show the person.
  List<String> mediaOf(String id) =>
      _ids('select media from shown where person = ? order by media', [id]);

  List<String> peopleByName() =>
      _ids('select id from person order by surname, name, born', const []);

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
