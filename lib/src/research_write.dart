import 'dart:io';

import 'package:path/path.dart' as p;

import 'diff.dart';
import 'page_format.dart';
import 'photo_metadata.dart';
import 'research.dart';
import 'server.dart' show itemIdTaken, newId;
import 'staging.dart';
import 'store.dart';
import 'tree.dart';

/// A page's new text, ready to show as a diff and then to save.
class PageEdit {
  PageEdit._(this.page, this.after, this.issues);

  /// The page as it is now.
  final Page page;

  /// Its new text, in the normal form the website saves.
  final String after;

  /// What the new text has wrong that the page did not before: a line that
  /// cannot be read, or a reference to nothing, such as a `#NEW-…`
  /// placeholder not yet replaced.
  final List<String> issues;

  /// Whether the new text differs from the page.
  bool get changed => after != formatPage(page.source);

  /// The page with its new text, as it will be saved.
  Page get draft => page is WikiPage
      ? WikiPage.fromSource(page.id, page.directory, after)
      : Person.fromSource(page.id, page.directory, after);

  /// The change line by line: `-` taken out, `+` put in, and [context]
  /// unchanged lines around each change.
  String diff({int context = 2}) =>
      unifiedDiff(formatPage(page.source), after, context: context);

  /// [page] with its text replaced by [source].
  static PageEdit replace(Research research, Page page, String source) =>
      _of(research, page, formatPage(source.replaceAll('\r\n', '\n')));

  /// [page] with [section] added to the end of its story.
  static PageEdit append(Research research, Page page, String section) => _of(
    research,
    page,
    formatPage(
      '${page.source.trimRight()}\n\n'
      '${section.replaceAll('\r\n', '\n').trim()}\n',
    ),
  );

  static PageEdit _of(Research research, Page page, String after) {
    final before = research.issuesOf(page).toSet();
    final edit = PageEdit._(page, after, const []);
    return PageEdit._(page, after, [
      for (final issue in research.issuesOf(edit.draft))
        if (!before.contains(issue)) issue,
    ]);
  }

  /// Saves the new text as one change by [author], unless the page has
  /// moved on from [basedOn]: then nothing is written and the result says
  /// so.
  Future<SaveResult> save(
    TreeStore store, {
    required int basedOn,
    required Member author,
    required String summary,
    String? helpedBy,
  }) => store.savePerson(
    draft,
    basedOn: basedOn,
    author: author,
    summary: summary,
    helpedBy: helpedBy,
    // The summary is written with the change, by whoever helped write it.
    summaryBy: helpedBy,
  );
}

/// A new item: a record's details, and its file if it has one.
class NewItem {
  NewItem._(this.details, this.link, this.found, this.file, this.kind);

  /// Reads an item's details from [json]: `title` (required), `date`,
  /// `place`, `transcription`, `notes`, `link`, `found`, and `people`, a list
  /// of page ids or references. [file] is a JPEG, PNG, TIFF, HEIC or PDF.
  /// Throws a [FormatException] saying what is wrong.
  static NewItem read(
    Research research,
    Map<String, Object?> json, {
    File? file,
  }) {
    String? text(String key) {
      final value = json[key];
      if (value != null && value is! String) {
        throw FormatException('"$key" should be text.');
      }
      final s = (value as String?)?.trim() ?? '';
      return s.isEmpty ? null : s;
    }

    const known = {
      'title',
      'date',
      'place',
      'transcription',
      'notes',
      'link',
      'found',
      'people',
    };
    for (final key in json.keys) {
      if (!known.contains(key)) {
        throw FormatException(
          '"$key" is not a detail of an item. Use: ${known.join(', ')}.',
        );
      }
    }
    final title = text('title');
    if (title == null) throw const FormatException('An item needs a title.');
    final people = <({String id, String name})>[];
    for (final ref in (json['people'] as List?) ?? const []) {
      final page = research.pageOf('$ref');
      if (page is! Person) {
        throw FormatException('No person in the tree matches $ref.');
      }
      people.add((id: page.id, name: page.name));
    }
    String? kind;
    if (file != null) {
      if (!file.existsSync()) {
        throw FormatException('No such file: ${file.path}');
      }
      final head = file.openSync();
      kind = Staging.kindOf(head.readSync(64));
      head.closeSync();
      if (kind == null) {
        throw FormatException(
          '${file.path} is not a JPEG, PNG, TIFF, HEIC or PDF.',
        );
      }
    }
    return NewItem._(
      PhotoDetails(
        title: title,
        date: text('date'),
        place: text('place'),
        transcription: text('transcription'),
        notes: text('notes'),
        people: people,
      ),
      text('link'),
      text('found'),
      file,
      kind,
    );
  }

  final PhotoDetails details;
  final String? link, found;
  final File? file;

  /// The kind of [file]: `jpg`, `png`, `tif`, `heic` or `pdf`.
  final String? kind;

  /// What will be saved, for the owner to check.
  Map<String, Object?> toJson() => {
    'title': details.title,
    'date': ?details.date,
    'place': ?details.place,
    'people': [for (final p in details.people) '${p.name} (${p.id})'],
    'transcription': ?details.transcription,
    'notes': ?details.notes,
    'link': ?link,
    'found': ?found,
    if (file != null) 'file': '${file!.path} ($kind)',
  };

  /// Adds the item to the tree as one change by [author], with [helpedBy]
  /// the model that helped, and returns it with its new id. A file is
  /// stored as the website stores an upload: a JPEG, HEIC or PDF as it is,
  /// anything else as a JPEG, with the details written into it.
  Future<Media> save(
    TreeStore store,
    Tree tree, {
    required Member author,
    String? summary,
    String? helpedBy,
  }) async {
    final id = newId('m', (id) => itemIdTaken(tree, id));
    final Media item;
    final MediaWrite write;
    if (file == null) {
      item = Media(id, isBack: false, extension: '', location: '')
        ..title = details.title
        ..date = details.date
        ..place = details.place
        ..transcription = details.transcription
        ..notes = details.notes;
      item.people.addAll(details.people.map((p) => p.id));
      write = MediaWrite(item, null);
    } else {
      final work = Directory.systemTemp.createTempSync('prosapia_item');
      final staged = file!.copySync(p.join(work.path, 'upload.$kind'));
      final archival = await Staging(work.path).archival(staged);
      final extension = switch (p.extension(archival.path).substring(1)) {
        'heic' => 'heic',
        'pdf' => 'pdf',
        _ => 'jpg',
      };
      write = await prepareMedia(
        archival,
        Media(id, isBack: false, extension: extension, location: ''),
        details,
      );
      item = write.media;
    }
    item
      ..link = link
      ..found = found;
    await store.saveMedia(
      [write],
      author: author,
      helpedBy: helpedBy,
      summary:
          summary ??
          'Add a ${switch (item.kind) {
            'source' => 'source',
            'document' => 'document',
            _ => 'photo',
          }}: ${details.title}',
    );
    return item;
  }
}

/// [before] and [after] compared line by line, as `-`, `+` and ` ` lines,
/// with [context] unchanged lines around each change and `…` between.
String unifiedDiff(String before, String after, {int context = 2}) {
  final lines = diffLines(before.trimRight(), after.trimRight());
  final near = List.filled(lines.length, false);
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].kind == DiffKind.same) continue;
    for (var j = i - context; j <= i + context; j++) {
      if (j >= 0 && j < lines.length) near[j] = true;
    }
  }
  final out = <String>[];
  var skipped = false;
  for (var i = 0; i < lines.length; i++) {
    if (!near[i]) {
      skipped = true;
      continue;
    }
    if (skipped && out.isNotEmpty) out.add('…');
    skipped = false;
    final (kind: kind, text: text) = lines[i];
    out.add(switch (kind) {
      DiffKind.same => ' $text',
      DiffKind.removed => '-$text',
      DiffKind.added => '+$text',
    });
  }
  return out.join('\n');
}
