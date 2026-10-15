import 'dart:io';

import 'tree.dart';

/// Where a tree is kept. The rest of the server only ever sees this
/// interface, so the store can change without the pages changing.
abstract class TreeStore {
  /// Reads the whole tree into memory.
  Future<Tree> load();

  /// A number that changes whenever the tree does. Cheap to ask for; the
  /// server uses it to decide when to reload.
  Future<int> version();

  /// The original file for [media], on local disk so tools can read it.
  Future<File> localFile(Media media);

  /// The member with this email address, or null if they are not a member.
  Future<Member?> member(String email);

  /// Whether readers must sign in. False only for a local tree of files.
  bool get requiresSignIn;

  /// Whether pages can be edited through this store.
  bool get editable => false;

  /// Saves a new version of a person's page.
  ///
  /// [basedOn] is the revision the editor started from. If the page has
  /// moved on since, nothing is written and the result says so: one
  /// person's edit never silently overwrites another's.
  Future<SaveResult> savePerson(
    Person person, {
    required int basedOn,
    required Member author,
    required String summary,
    String? helpedBy,
    String? summaryBy,
  }) => saveChange(
    [PageWrite(person, basedOn: basedOn)],
    author: author,
    summary: summary,
    helpedBy: helpedBy,
    summaryBy: summaryBy,
  );

  /// Saves several pages as one change: a new page and the reference that
  /// names it, or a deletion and the pages that mentioned the person. All
  /// are written, as one entry in the log, or none are.
  ///
  /// [helpedBy] names the model that helped write the text, and [summaryBy]
  /// the model that wrote the summary, when one did.
  Future<SaveResult> saveChange(
    List<PageWrite> pages, {
    required Member author,
    required String summary,
    String? helpedBy,
    String? summaryBy,
  }) => throw UnsupportedError('This store is read-only.');

  /// Whether members may ask a language model for help, and the most it may
  /// cost in a month.
  Future<HelpSettings> helpSettings() async => const HelpSettings();

  Future<void> setHelpSettings(HelpSettings settings) =>
      throw UnsupportedError('This store is read-only.');

  /// What calls to the model have cost this calendar month, in US dollars.
  Future<double> spentThisMonth() async => 0;

  /// Records the cost of one call to the model.
  Future<void> recordCost(double dollars, {required String model}) async {}

  /// Adds photos to the tree: each [MediaWrite]'s file is stored and its
  /// record written, as one entry in the log. Also used to replace a
  /// photo's file after its details change.
  Future<void> saveMedia(
    List<MediaWrite> files, {
    required Member author,
    required String summary,
  }) => throw UnsupportedError('This store is read-only.');

  /// Every saved version of a person's page, newest first.
  Future<List<Revision>> history(String personId) async => const [];

  Future<Revision?> revision(String personId, int number) async => null;

  /// The log of every change to the tree, newest first.
  Future<List<Change>> recentChanges({int limit = 100}) async => const [];

  /// One entry in the log, by its id.
  Future<Change?> change(String id) async => null;

  /// Everyone invited to the tree, by email address.
  Future<List<Member>> members() async => const [];

  /// Invites [email] with [role], or changes their role. A name already
  /// recorded for them is kept.
  Future<void> setMember(String email, Role role) =>
      throw UnsupportedError('This store is read-only.');

  /// Removes [email] from the tree. Their past edits keep their name.
  Future<void> removeMember(String email) =>
      throw UnsupportedError('This store is read-only.');

  /// Records the name Google gives for a member, for display in histories.
  Future<void> rememberName(Member member, String name) async {}

  Future<void> close() async {}
}

class HelpSettings {
  const HelpSettings({this.enabled = false, this.monthlyLimit = 10});

  final bool enabled;

  /// US dollars.
  final double monthlyLimit;
}

enum Role {
  owner,
  editor,
  viewer;

  bool get canEdit => this != viewer;
}

/// Someone invited to a tree. Google confirms who they are; Prosapia decides
/// what they may do.
class Member {
  Member(this.email, this.role, {this.name});

  final String email;
  final Role role;
  final String? name;
}

/// One page in a change: its new text, or its deletion.
class PageWrite {
  PageWrite(this.person, {required this.basedOn}) : delete = false;

  /// Deletes [person]'s page. Its text stays in the history, and the last
  /// version is kept so the page can be shown as deleted and brought back.
  PageWrite.delete(this.person, {required this.basedOn}) : delete = true;

  final Person person;

  /// The revision this write was based on; zero for a new page.
  final int basedOn;
  final bool delete;
}

/// A photo file to store, with its record.
class MediaWrite {
  MediaWrite(this.media, this.file);

  final Media media;

  /// The file as it should be stored, with its metadata already written.
  final File file;
}

/// The outcome of a save: the new revision number, or the page and revision
/// that got there first.
class SaveResult {
  SaveResult.saved(int this.revision)
    : conflictWith = null,
      conflictPage = null;
  SaveResult.conflict(int this.conflictWith, {this.conflictPage})
    : revision = null;

  /// The new revision of the first page written.
  final int? revision;
  final int? conflictWith;

  /// Which page had moved on, for a change of several pages.
  final String? conflictPage;

  bool get saved => revision != null;
}

/// One saved version of a page: its full text, and who saved it, when and why.
class Revision {
  Revision(
    this.number,
    this.source, {
    required this.author,
    this.authorName,
    required this.summary,
    required this.at,
    this.deleted = false,
    this.helpedBy,
    this.summaryBy,
  });

  final int number;

  /// The page's text; empty for a version that deleted the page.
  final String source;

  /// Whether this version deleted the page.
  final bool deleted;

  /// The model that helped write this version, if one did.
  final String? helpedBy;

  /// The model that wrote [summary], if one did.
  final String? summaryBy;
  final String author;
  final String? authorName;
  final String summary;
  final DateTime at;

  String get by => authorName ?? author;
}

/// An entry in the tree's change log.
class Change {
  Change({
    required this.id,
    required this.author,
    this.authorName,
    required this.summary,
    required this.at,
    required this.pages,
    this.media = const [],
    this.summaryBy,
  });

  final String id;
  final String author;
  final String? authorName;
  final String summary;
  final DateTime at;

  /// The pages changed, each with the revision the change produced.
  final Map<String, int> pages;

  /// The photos and other files added or changed, by key.
  final List<String> media;

  /// The model that wrote [summary], if one did.
  final String? summaryBy;

  String get by => authorName ?? author;
}
