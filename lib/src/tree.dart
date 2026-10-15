import 'dates.dart';
import 'page_syntax.dart';

/// A family tree held in memory. It is loaded through a `TreeStore`, from
/// files or from Firestore, and everything a reader sees is computed from it.
class Tree {
  Tree(this.name);

  final String name;
  final people = <String, Person>{};
  final media = <String, Media>{};

  /// Pages that were deleted, as they were last written. They are not part
  /// of the tree, but their history is kept and they can be brought back.
  final deleted = <String, Person>{};

  /// Records that could not be read, with the reason.
  final problems = <String>[];
}

/// Something that happened at a time and place: a birth, a burial, the date
/// and place parts of any fact.
class Event {
  Event({this.date, this.place});

  final TreeDate? date;
  final String? place;

  bool get isEmpty => date == null && place == null;
}

/// A person named in a fact line: by `@` reference to their page, or by a
/// plain name for someone who has no page.
class PersonRef {
  PersonRef.page(String this.id, {this.qualifier}) : name = null;
  PersonRef.named(String this.name, {this.qualifier}) : id = null;

  /// The id of the person's page, for an `@` reference.
  final String? id;

  /// The name, for someone without a page.
  final String? name;

  /// The kind of relationship, when stated: `adopted`, `step`.
  final String? qualifier;
}

/// A marriage, divorce or other event between two people.
class CoupleEvent {
  CoupleEvent(this.kind, this.partner, this.event);

  /// The label as written: `Married`, `Divorced`.
  final String kind;
  final PersonRef? partner;
  final Event event;
}

/// Anything else known about a person: an occupation, a residence, a title.
class Fact {
  Fact(this.label, this.description, this.event, this.people);

  /// The label as written, such as `Occupation`.
  final String label;
  final String description;
  final Event event;
  final List<PersonRef> people;
}

class Person {
  Person._(this.id, this.directory, this.source);

  /// Reads a person from their page text. Never fails: anything that does
  /// not fit is recorded in [issues] and shown on the page.
  factory Person.fromSource(
    String id,
    String directory,
    String source, {
    int revision = 0,
  }) {
    final person = Person._(id, directory, source)..revision = revision;
    final page = ParsedPage.parse(source);
    person.body = page.body;
    for (final line in page.strayLines) {
      person.issues.add('Not a "Label: value" line: $line');
    }
    if (page.facts.isEmpty) {
      person.issues.add('The page does not start with a "Name:" line.');
    }
    for (final line in page.facts) {
      person._read(line);
    }
    return person;
  }

  static const lifeEvents = {
    'born',
    'christened',
    'baptized',
    'died',
    'buried',
  };
  static const coupleEvents = {'married', 'divorced', 'separated', 'engaged'};
  static const relationships = {
    'parents', 'parent', 'children', 'child', 'siblings', 'sibling', //
    'partner', 'partners', 'spouse',
  };

  void _read(FactLine line) {
    final key = line.key;
    switch (key) {
      case 'name':
        name = line.value;
      case 'also known as':
        alsoKnownAs.addAll(line.segments.map((s) => s.text));
      case 'sex':
        sex = line.value;
      case 'photo':
        photo = line.value;
      case 'note':
        notes.add(line.value);
      case _ when lifeEvents.contains(key):
        final event = _event(line, line.segments, placeUnmarked: true);
        switch (key) {
          case 'born':
            born = event;
          case 'died':
            died = event;
          case 'buried':
            buried = event;
          default:
            christened = event;
        }
      case _ when coupleEvents.contains(key):
        var segments = line.segments;
        PersonRef? partner;
        final first = segments.isEmpty ? null : segments.first;
        if (first is RefSegment) {
          partner = PersonRef.page(first.personId);
          segments = segments.skip(1).toList();
        } else if (first is TextSegment &&
            !TreeDate.parse(first.text).understood) {
          partner = PersonRef.named(first.text);
          segments = segments.skip(1).toList();
        }
        couples.add(
          CoupleEvent(
            line.label,
            partner,
            _event(line, segments, placeUnmarked: true),
          ),
        );
      case _ when relationships.contains(key):
        final list = switch (key) {
          'parents' || 'parent' => parents,
          'children' || 'child' => children,
          'siblings' || 'sibling' => siblings,
          _ => partners,
        };
        for (final segment in line.segments) {
          final ref = _ref(line, segment);
          if (ref != null) list.add(ref);
        }
      default:
        facts.add(_fact(line));
    }
  }

  static final _namedWithQualifier = RegExp(r'^(.*?)\s*\(([^)]*)\)$');

  PersonRef? _ref(FactLine line, Segment segment) {
    if (segment is RefSegment) {
      return PersonRef.page(segment.personId, qualifier: segment.qualifier);
    }
    if (segment is TextSegment && !RegExp(r'\d').hasMatch(segment.text)) {
      final m = _namedWithQualifier.firstMatch(segment.text);
      return m == null
          ? PersonRef.named(segment.text)
          : PersonRef.named(m[1]!, qualifier: m[2]!.trim());
    }
    final hint =
        line.key == 'partner' || line.key == 'partners' || line.key == 'spouse'
        ? ' For a marriage, use a "Married:" line.'
        : '';
    issues.add('In "${line.label}:", "${segment.text}" is not a person.$hint');
    return null;
  }

  /// Reads date and place parts. For life events an unmarked place is
  /// expected; elsewhere a place must be marked.
  Event _event(
    FactLine line,
    List<Segment> segments, {
    required bool placeUnmarked,
  }) {
    TreeDate? date;
    final place = <String>[];
    for (final segment in segments) {
      switch (segment) {
        case DateSegment():
          date ??= segment.date;
          if (!segment.date.understood) {
            issues.add(
              'In "${line.label}:", "${segment.date.raw}" is not a date Prosapia can read.',
            );
          }
        case PlaceSegment():
          place.add(segment.place);
        case TextSegment():
          final asDate = TreeDate.parse(segment.text);
          if (date == null && place.isEmpty && asDate.understood) {
            date = asDate;
          } else {
            place.add(segment.text);
          }
        case RefSegment():
          break;
      }
    }
    return Event(date: date, place: place.isEmpty ? null : place.join(', '));
  }

  Fact _fact(FactLine line) {
    TreeDate? date;
    String? place;
    final description = <String>[];
    final people = <PersonRef>[];
    for (final segment in line.segments) {
      switch (segment) {
        case DateSegment():
          date ??= segment.date;
        case PlaceSegment():
          place ??= segment.place;
        case RefSegment():
          people.add(
            PersonRef.page(segment.personId, qualifier: segment.qualifier),
          );
        case TextSegment():
          // A part that is wholly a date is the fact's date; the rest
          // describes the fact.
          final asDate = TreeDate.parse(segment.text);
          if (date == null && asDate.understood) {
            date = asDate;
          } else {
            description.add(segment.text);
          }
      }
    }
    return Fact(
      line.label,
      description.join(', '),
      Event(date: date, place: place),
      people,
    );
  }

  final String id;

  /// The person's directory in the file layout, and what follows `@` in a
  /// reference to them: a readable name ending in the id.
  final String directory;

  /// The page exactly as written. Everything else here is read from it.
  final String source;

  /// The number of the saved version this is. Zero when the store keeps no
  /// history.
  int revision = 0;

  String name = '(no name)';
  String? sex;
  String? photo;
  Event? born, christened, died, buried;
  final alsoKnownAs = <String>[];
  final parents = <PersonRef>[];
  final children = <PersonRef>[];
  final siblings = <PersonRef>[];
  final partners = <PersonRef>[];
  final couples = <CoupleEvent>[];
  final facts = <Fact>[];
  final notes = <String>[];
  String body = '';

  /// What could not be read from the page, in words for its editors.
  final issues = <String>[];

  /// What a reference to this person looks like: `@hughes-thomas-3f8d1a`.
  String get reference => '@$directory';

  /// `1911–1987`, `born 1950`, `died 1987`, or empty.
  String get years {
    final b = born?.date?.year, d = died?.date?.year;
    if (b != null && d != null) return '$b–$d';
    if (b != null) return 'born $b';
    if (d != null) return 'died $d';
    return '';
  }
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
        ..date = map['date'] as String?
        ..place = map['place'] as String?
        ..set = map['set'] as String?
        ..setIndex = map['setIndex'] as int?
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

  /// For a photo with writing on its back, the transcription of it. It is
  /// kept in both files, so the words survive if the back is lost.
  String? description;
  int? width, height, size;

  /// When it was taken, as typed: "about 1949".
  String? date;

  /// Where it was taken, as typed.
  String? place;

  /// The set it was added with, and its place in that set's order.
  String? set;
  int? setIndex;

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
    if (date != null) 'date': date,
    if (place != null) 'place': place,
    if (set != null) 'set': set,
    if (setIndex != null) 'setIndex': setIndex,
    'people': people,
  };
}
