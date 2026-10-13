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

  Future<void> close() async {}
}

enum Role {
  owner,
  editor,
  viewer;

  bool get canEdit => this != viewer;
}

/// Someone invited to a tree. Google confirms who they are; Loom decides
/// what they may do.
class Member {
  Member(this.email, this.role, {this.name});

  final String email;
  final Role role;
  final String? name;
}
