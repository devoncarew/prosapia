import 'dates.dart';

/// A family tree held in memory. It is loaded through a `TreeStore`, from
/// files or from Firestore, and everything a reader sees is computed from it.
class Tree {
  Tree(this.name);

  final String name;
  final people = <String, Person>{};
  final unions = <String, Union>{};
  final media = <String, Media>{};

  /// Records that could not be read, with the reason.
  final problems = <String>[];
}

class Event {
  Event({this.date, this.place, this.note, this.coordinates});

  static Event? fromMap(Object? map) {
    if (map is! Map) return null;
    final date = map['date'];
    return Event(
      // YAML reads a bare year as a number.
      date: date == null ? null : TreeDate(date.toString()),
      place: map['place'] as String?,
      note: map['note'] as String?,
      coordinates: (map['coordinates'] as List?)?.cast<num>().toList(),
    );
  }

  final TreeDate? date;
  final String? place;
  final String? note;

  /// Latitude and longitude of [place], when known.
  final List<num>? coordinates;

  Map<String, Object?> toMap() => {
    if (note != null) 'note': note,
    if (date != null) 'date': date!.raw,
    if (place != null) 'place': place,
    if (coordinates != null) 'coordinates': coordinates,
  };
}

/// Something known about a person beyond birth and death: an occupation, a
/// residence, a burial.
class Fact {
  Fact(this.type, this.value, this.event);

  final String type;
  final String? value;
  final Event event;

  Map<String, Object?> toMap() => {
    'type': type,
    if (value != null) 'value': value,
    ...event.toMap()..remove('note'),
  };
}

class ParentLink {
  ParentLink(this.id, [this.relationship]);

  final String id;

  /// Set when the parent is not a birth parent: `adopted`, `step`.
  final String? relationship;
}

class Person {
  Person(this.id, this.name, this.directory);

  /// Reads a person from its structured fields, which have the same shape in
  /// a file's front matter and in a Firestore document.
  factory Person.fromMap(
    Map<dynamic, dynamic> map,
    String body,
    String directory,
  ) {
    final person = Person(map['id'] as String, map['name'] as String, directory)
      ..surname = map['surname'] as String?
      ..sex = map['sex'] as String?
      ..born = Event.fromMap(map['born'])
      ..died = Event.fromMap(map['died'])
      ..photo = map['photo'] as String?
      ..body = body;
    person.alsoKnownAs.addAll(
      ((map['also_known_as'] as List?) ?? const []).cast<String>(),
    );
    for (final parent in (map['parents'] as List?) ?? const []) {
      person.parents.add(
        parent is Map
            ? ParentLink(
                parent['id'] as String,
                parent['relationship'] as String?,
              )
            : ParentLink(parent as String),
      );
    }
    for (final fact in (map['facts'] as List?) ?? const []) {
      person.facts.add(
        Fact(
          (fact as Map)['type'] as String,
          fact['value']?.toString(),
          Event.fromMap(fact)!,
        ),
      );
    }
    for (final key in map.keys) {
      if (!_known.contains(key)) person.extra[key as String] = map[key];
    }
    return person;
  }

  static const _known = {
    'id', 'name', 'surname', 'also_known_as', 'sex', 'born', 'died', //
    'parents', 'photo', 'facts',
  };

  final String id;
  final String name;

  /// The person's directory in the file layout: a readable name ending in
  /// the id. Only the trailing id is relied on.
  final String directory;
  String? surname;
  String? sex;
  Event? born;
  Event? died;
  String? photo;
  String body = '';

  /// The number of the saved version this is. Zero when the store keeps no
  /// history.
  int revision = 0;
  final alsoKnownAs = <String>[];
  final parents = <ParentLink>[];
  final facts = <Fact>[];

  /// Fields this version of Prosapia does not interpret. They are kept so a
  /// record survives a round trip unchanged.
  final extra = <String, Object?>{};

  /// The structured fields, in the order they are written.
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    if (surname != null) 'surname': surname,
    if (alsoKnownAs.isNotEmpty) 'also_known_as': alsoKnownAs,
    if (sex != null) 'sex': sex,
    if (born != null) 'born': born!.toMap(),
    if (died != null) 'died': died!.toMap(),
    if (parents.isNotEmpty)
      'parents': [
        for (final link in parents)
          link.relationship == null
              ? link.id
              : {'id': link.id, 'relationship': link.relationship},
      ],
    if (photo != null) 'photo': photo,
    if (facts.isNotEmpty) 'facts': [for (final f in facts) f.toMap()],
    ...extra,
  };

  /// `1911–1987`, `born 1950`, `died 1987`, or empty.
  String get years {
    final b = born?.date?.year, d = died?.date?.year;
    if (b != null && d != null) return '$b–$d';
    if (b != null) return 'born $b';
    if (d != null) return 'died $d';
    return '';
  }
}

class Union {
  Union(this.id, this.partners, this.married);

  factory Union.fromMap(Map<dynamic, dynamic> map) {
    final union = Union(
      map['id'] as String,
      (map['partners'] as List).cast<String>().toList(),
      Event.fromMap(map['married']),
    );
    for (final key in map.keys) {
      if (!const {'id', 'partners', 'married'}.contains(key)) {
        union.extra[key as String] = map[key];
      }
    }
    return union;
  }

  final String id;
  final List<String> partners;
  final Event? married;
  final extra = <String, Object?>{};

  Map<String, Object?> toMap() => {
    'id': id,
    'partners': partners,
    if (married != null) 'married': married!.toMap(),
    ...extra,
  };
}

class Media {
  Media(
    this.id, {
    required this.isBack,
    required this.extension,
    required this.location,
  });

  factory Media.fromMap(Map<dynamic, dynamic> map) =>
      Media(
          map['id'] as String,
          isBack: map['back'] as bool? ?? false,
          extension: map['extension'] as String,
          location: map['location'] as String,
        )
        ..title = map['title'] as String?
        ..description = map['description'] as String?
        ..width = map['width'] as int?
        ..height = map['height'] as int?
        ..size = map['size'] as int?
        ..people.addAll(((map['people'] as List?) ?? const []).cast<String>());

  /// Ids written into a file's metadata carry this prefix, so they can be
  /// told apart from other software's identifiers: `prosapia:p-7k2m9x`.
  static const idScheme = 'prosapia:';

  /// `m-5t1q8z.jpg` is a front, `m-5t1q8z-back.jpg` its back.
  static final namePattern = RegExp(r'^(m-[a-z0-9]+)(-back)?\.(\w+)$');

  final String id;
  final bool isBack;
  final String extension;

  /// Where the store keeps the file: a path on disk, or an object name in
  /// Cloud Storage. Only the store interprets it.
  final String location;
  String? title;
  String? description;
  int? width, height, size;

  /// Ids of the people shown, from the file's embedded metadata.
  final people = <String>[];

  String get key => isBack ? '$id-back' : id;
  String get fileName => '$key.$extension';
  bool get isImage => const {'jpg', 'jpeg', 'heic', 'png'}.contains(extension);

  /// What the database keeps about a file so it can be listed and searched
  /// without opening it. The file's embedded metadata remains the authority.
  Map<String, Object?> toMap({String? location}) => {
    'id': id,
    'back': isBack,
    'extension': extension,
    'location': location ?? this.location,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (size != null) 'size': size,
    'people': people,
  };
}
