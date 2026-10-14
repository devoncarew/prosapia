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
  Future<SaveResult> savePerson(Person person,
          {required int basedOn, required Member author, required String summary}) =>
      throw UnsupportedError('This store is read-only.');

  /// Every saved version of a person's page, newest first.
  Future<List<Revision>> history(String personId) async => const [];

  Future<Revision?> revision(String personId, int number) async => null;

  /// The log of every change to the tree, newest first.
  Future<List<Change>> recentChanges({int limit = 100}) async => const [];

  /// Records the name Google gives for a member, for display in histories.
  Future<void> rememberName(Member member, String name) async {}

  Future<void> close() async {}
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

/// The outcome of a save: the new revision number, or the revision that got
/// there first.
class SaveResult {
  SaveResult.saved(int this.revision) : conflictWith = null;
  SaveResult.conflict(int this.conflictWith) : revision = null;

  final int? revision;
  final int? conflictWith;

  bool get saved => revision != null;
}

/// One saved version of a page: its full text, and who saved it, when and why.
class Revision {
  Revision(this.number, this.source, {required this.author, this.authorName, required this.summary, required this.at});

  final int number;
  final String source;
  final String author;
  final String? authorName;
  final String summary;
  final DateTime at;

  String get by => authorName ?? author;
}

/// An entry in the tree's change log.
class Change {
  Change({required this.author, this.authorName, required this.summary, required this.at, required this.pages});

  final String author;
  final String? authorName;
  final String summary;
  final DateTime at;

  /// The pages changed, each with the revision the change produced.
  final Map<String, int> pages;

  String get by => authorName ?? author;
}
