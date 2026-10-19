import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'firestore_store.dart';
import 'store.dart';
import 'tree.dart';

/// Copies a tree into a git repository in the file layout, one commit per
/// logged change, with the change's author, time and summary. Each run
/// carries on from where the last one stopped, so it can run nightly.
///
/// The repository is a backup that needs no Prosapia to read, and the
/// server can load it in file mode.
class Exporter {
  Exporter(this.store, {required this.repo, this.sshKey, this.log = print});

  final FirestoreStore store;

  /// Where to push: `git@github.com:owner/name.git`, or a local path.
  final String repo;

  /// A private key that may push to [repo] over SSH.
  final String? sshKey;
  final void Function(String) log;

  /// GitHub's published host key, so the connection cannot be intercepted.
  static const githubHostKey =
      'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl';

  /// Files larger than this are listed but not copied; GitHub refuses
  /// files over 100 MB.
  static const maxFileBytes = 95 * 1000 * 1000;

  static const _stateFile = '.prosapia/export.json';

  late final Directory _work;
  late final Map<String, String> _gitEnv;

  /// Exports what has changed since the last run, and returns how many
  /// commits were pushed.
  Future<int> run() async {
    _work = Directory.systemTemp.createTempSync('prosapia_export');
    try {
      _gitEnv = _environment();
      final checkout = p.join(_work.path, 'repo');
      // Only the latest files are needed to add commits on top.
      await _git([
        'clone',
        '--quiet',
        '--depth',
        '1',
        if (!repo.contains(':')) 'file://$repo' else repo,
        checkout,
      ], dir: _work.path);
      // A new, empty repository has no branch yet.
      if (await _git(
            ['rev-parse', '--verify', 'HEAD'],
            dir: checkout,
            check: false,
          ) !=
          0) {
        await _git(['checkout', '--quiet', '-b', 'main'], dir: checkout);
      }

      final state = _readState(checkout);
      final tree = await store.load();
      final since = state.at;
      final changes = [
        for (final c in await store.changesSince(since))
          if (!state.ids.contains(c.id)) c,
      ];
      log('${changes.length} changes to export since ${since ?? 'the start'}.');

      var commits = 0;
      for (final change in changes) {
        await _writeChange(checkout, tree, change);
        final ids = change.at == state.at
            ? {...state.ids, change.id}
            : {change.id};
        state
          ..at = change.at
          ..ids = ids;
        _writeState(checkout, state, tree);
        if (await _commit(
          checkout,
          message: '${change.summary}\n\nProsapia change ${change.id}',
          name: change.authorName ?? change.author,
          email: change.author.contains('@')
              ? change.author
              : 'export@prosapia.app',
          at: change.at,
        )) {
          commits++;
        }
      }

      // Files no logged change added, such as those loaded with the tree.
      if (await _copyMissingMedia(checkout, tree) > 0) {
        _writeState(checkout, state, tree);
        if (await _commit(
          checkout,
          message: 'Add photos and documents not yet exported',
          name: 'Prosapia export',
          email: 'export@prosapia.app',
          at: DateTime.now(),
        )) {
          commits++;
        }
      }

      if (commits > 0) {
        await _git(['push', '--quiet', 'origin', 'HEAD:main'], dir: checkout);
      }
      log('Pushed $commits commits.');
      return commits;
    } finally {
      _work.deleteSync(recursive: true);
    }
  }

  Future<void> _writeChange(String checkout, Tree tree, Change change) async {
    for (final MapEntry(key: id, value: number) in change.pages.entries) {
      final person = tree.people[id] ?? tree.deleted[id];
      final dir = p.join(checkout, 'people', person?.directory ?? id);
      final revision = await store.revision(id, number);
      if (revision == null) continue;
      if (revision.deleted) {
        if (Directory(dir).existsSync()) {
          Directory(dir).deleteSync(recursive: true);
        }
      } else {
        Directory(dir).createSync(recursive: true);
        File(p.join(dir, 'index.md')).writeAsStringSync(revision.source);
      }
    }
    for (final key in change.media) {
      final media = tree.media[key];
      if (media != null) await _copyMedia(checkout, media);
    }
  }

  Future<int> _copyMissingMedia(String checkout, Tree tree) async {
    var copied = 0;
    for (final media in tree.media.values) {
      final dest = File(
        p.join(
          checkout,
          'media',
          media.hasFile ? media.fileName : '${media.key}.json',
        ),
      );
      if (dest.existsSync()) continue;
      if (await _copyMedia(checkout, media)) copied++;
    }
    return copied;
  }

  Future<bool> _copyMedia(String checkout, Media media) async {
    // An item without a file is written as its details.
    if (!media.hasFile) {
      final dest = File(p.join(checkout, 'media', '${media.key}.json'));
      dest.parent.createSync(recursive: true);
      dest.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(media.toMap()..remove('location'))}\n',
      );
      return true;
    }
    if ((media.size ?? 0) > maxFileBytes) {
      log('Not copied, too large: ${media.fileName}');
      return false;
    }
    final source = await store.localFile(media);
    final dest = File(p.join(checkout, 'media', media.fileName));
    dest.parent.createSync(recursive: true);
    source.copySync(dest.path);
    return true;
  }

  /// Commits everything that changed; false if nothing did.
  Future<bool> _commit(
    String checkout, {
    required String message,
    required String name,
    required String email,
    required DateTime at,
  }) async {
    await _git(['add', '--all'], dir: checkout);
    if (await _git(
          ['diff', '--cached', '--quiet'],
          dir: checkout,
          check: false,
        ) ==
        0) {
      return false;
    }
    await _git(
      ['commit', '--quiet', '--message', message],
      dir: checkout,
      env: {
        'GIT_AUTHOR_NAME': name,
        'GIT_AUTHOR_EMAIL': email,
        'GIT_AUTHOR_DATE': at.toUtc().toIso8601String(),
      },
    );
    return true;
  }

  static _ExportState _readState(String checkout) {
    final file = File(p.join(checkout, _stateFile));
    if (!file.existsSync()) return _ExportState();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return _ExportState()
      ..at = DateTime.tryParse(json['at'] as String? ?? '')
      ..ids = {...((json['ids'] as List?) ?? const []).cast<String>()};
  }

  static void _writeState(String checkout, _ExportState state, Tree tree) {
    final file = File(p.join(checkout, _stateFile));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'at': state.at?.toUtc().toIso8601String(), 'ids': state.ids.toList()})}\n',
    );
    File(
      p.join(checkout, 'tree.yaml'),
    ).writeAsStringSync('name: ${jsonEncode(tree.name)}\n');
    final readme = File(p.join(checkout, 'README.md'));
    if (!readme.existsSync()) {
      readme.writeAsStringSync(
        '# ${tree.name}\n\n'
        'A copy of the family tree kept in Prosapia, written each night: one '
        'commit for each change made there, with its author and time.\n\n'
        'Each person is a page in `people/`: facts as "Label: value" lines, '
        'then their story in markdown. Photos and documents are in `media/`, '
        'with what is known about them written into each file.\n',
      );
    }
  }

  /// Git's settings for this run: who commits, and how to reach GitHub.
  Map<String, String> _environment() {
    final env = <String, String>{
      'GIT_COMMITTER_NAME': 'Prosapia export',
      'GIT_COMMITTER_EMAIL': 'export@prosapia.app',
      'GIT_TERMINAL_PROMPT': '0',
    };
    if (sshKey != null) {
      final key = File(p.join(_work.path, 'key'))
        ..writeAsStringSync(sshKey!.endsWith('\n') ? sshKey! : '$sshKey\n');
      Process.runSync('chmod', ['600', key.path]);
      final hosts = File(p.join(_work.path, 'known_hosts'))
        ..writeAsStringSync('$githubHostKey\n');
      env['GIT_SSH_COMMAND'] =
          'ssh -i ${key.path} -o IdentitiesOnly=yes '
          '-o UserKnownHostsFile=${hosts.path} -o StrictHostKeyChecking=yes';
    }
    return env;
  }

  Future<int> _git(
    List<String> args, {
    required String dir,
    Map<String, String> env = const {},
    bool check = true,
  }) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: dir,
      environment: {..._gitEnv, ...env},
    );
    if (check && result.exitCode != 0) {
      throw StateError('git ${args.first} failed: ${result.stderr}');
    }
    return result.exitCode;
  }
}

class _ExportState {
  DateTime? at;

  /// The changes already exported at time [at], which a query for changes
  /// since [at] returns again.
  Set<String> ids = {};
}
