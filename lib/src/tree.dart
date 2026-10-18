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

  /// Photos and documents that were deleted. Their files are kept, so they
  /// can be brought back.
  final deletedMedia = <String, Media>{};

  /// Records that could not be read, with the reason.
  final problems = <String>[];
}

/// Something that happened at a time and place: a birth, a burial, the date
/// and place parts of any fact.
class Event {
  Event({this.date, this.place, this.sources = const []});

  final TreeDate? date;
  final String? place;

  /// Where the fact comes from, as written: `1920 census, Hartford, CT`.
  final List<String> sources;

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
      case 'nickname':
        nicknames.addAll(line.segments.map((s) => s.value));
      case 'also known as':
        alsoKnownAs.addAll(line.segments.map((s) => s.value));
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
        // The partner is the `@` reference, wherever it is in the line;
        // or else the first plain part that is not a date.
        final segments = [...line.segments];
        PersonRef? partner;
        final ref = segments.whereType<RefSegment>().firstOrNull;
        final named = segments
            .whereType<TextSegment>()
            .where((s) => !TreeDate.parse(s.value).understood)
            .firstOrNull;
        if (ref != null) {
          partner = PersonRef.page(ref.personId);
          segments.remove(ref);
        } else if (named != null) {
          partner = PersonRef.named(named.value);
          segments.remove(named);
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
    // A plain part is a name, unless it has a year in it, as a date or
    // "married 1945" would, or has no letters. A name may have a small
    // number, as in "Rudie Wilhelm 3rd".
    if (segment is TextSegment &&
        RegExp(r'\p{L}', unicode: true).hasMatch(segment.value) &&
        !RegExp(r'\d{3}').hasMatch(segment.value)) {
      final m = _namedWithQualifier.firstMatch(segment.value);
      return m == null
          ? PersonRef.named(segment.value)
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
    final sources = <String>[];
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
        case SourceSegment():
          sources.add(segment.source);
        case TextSegment():
          final asDate = TreeDate.parse(segment.value);
          // A date may come after the place, as in `"Portland, Oregon",
          // 18 March 1914`; there it needs a year, so a word of a place is
          // not taken for one.
          if (date == null &&
              asDate.understood &&
              (place.isEmpty || asDate.year != null)) {
            date = asDate;
          } else {
            place.add(segment.value);
          }
        case RefSegment():
          break;
      }
    }
    return Event(
      date: date,
      place: place.isEmpty ? null : place.join(', '),
      sources: sources,
    );
  }

  Fact _fact(FactLine line) {
    TreeDate? date;
    String? place;
    final description = <String>[];
    final people = <PersonRef>[];
    final sources = <String>[];
    for (final segment in line.segments) {
      switch (segment) {
        case DateSegment():
          date ??= segment.date;
        case PlaceSegment():
          place ??= segment.place;
        case SourceSegment():
          sources.add(segment.source);
        case RefSegment():
          people.add(
            PersonRef.page(segment.personId, qualifier: segment.qualifier),
          );
        case TextSegment():
          // A part that is wholly a date is the fact's date; the rest
          // describes the fact.
          final asDate = TreeDate.parse(segment.value);
          if (date == null && asDate.understood) {
            date = asDate;
          } else {
            description.add(segment.value);
          }
      }
    }
    return Fact(
      line.label,
      description.join(', '),
      Event(date: date, place: place, sources: sources),
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

  /// What they were called in place of their given name: "Scotty".
  final nicknames = <String>[];

  /// Other full names: a maiden or married name, a changed name, another
  /// spelling.
  final alsoKnownAs = <String>[];
  final parents = <PersonRef>[];
  final children = <PersonRef>[];
  final siblings = <PersonRef>[];
  final partners = <PersonRef>[];
  final couples = <CoupleEvent>[];
  final facts = <Fact>[];
  final notes = <String>[];
  String body = '';

  /// Who last saved the page, and when, if the store records it.
  String? editedBy;
  DateTime? editedAt;

  /// What could not be read from the page, in words for its editors.
  final issues = <String>[];

  /// What a reference to this person looks like: `@hughes-thomas-3f8d1a`.
  String get reference => '@$directory';

  /// `1911–1987`, `born 1950`, `died 1987`, or empty.
  /// The name with the first nickname after the given name, as the family
  /// would write it: Allan “Scotty” MacLean Davidson.
  String get displayName {
    if (nicknames.isEmpty) return name;
    final words = name.trim().split(RegExp(r'\s+'));
    return [words.first, '“${nicknames.first}”', ...words.skip(1)].join(' ');
  }

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
        ..transcription = map['description'] as String?
        ..notes = map['notes'] as String?
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

  /// The words written or printed on it, as written: for a photo with a
  /// back, the writing on the back. It is kept in both files, so the words
  /// survive if the back is lost.
  String? transcription;

  /// What is known about it rather than written on it: where the original
  /// is, who scanned it, who identified the people.
  String? notes;
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

  /// A document whose first page can be shown as a picture.
  bool get isDocument => extension == 'pdf';

  /// What the database keeps about a file so it can be listed and searched
  /// without opening it. The file's embedded metadata remains the authority.
  Map<String, Object?> toMap({String? location}) => {
    'id': id,
    'back': isBack,
    'extension': extension,
    'location': location ?? this.location,
    if (title != null) 'title': title,
    if (transcription != null) 'description': transcription,
    if (notes != null) 'notes': notes,
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

/// A name in its parts: the given names, the family name, and anything
/// after it such as "Jr." or "3rd", which is not the family name.
({List<String> given, String? surname, List<String> suffix}) nameParts(
  String name,
) {
  final words = name.trim().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  var end = words.length;
  while (end > 1 && _suffixes.hasMatch(words[end - 1])) {
    end--;
  }
  if (end < 2) return (given: words, surname: null, suffix: const []);
  return (
    given: words.sublist(0, end - 1),
    surname: words[end - 1],
    suffix: words.sublist(end),
  );
}

final _suffixes = RegExp(
  r'^(jr|sr|ii|iii|iv|v|vi|\d+(st|nd|rd|th)|esq|phd|md)\.?,?$',
  caseSensitive: false,
);
