# Contributing

## Running Prosapia locally

The server is written in Dart and needs `exiftool` and `libvips` (both available from
Homebrew). The browser code and the formatting tools need Node.

### From files, with no sign-in

The quickest way to look at a tree. The directory is a tree in Prosapia's file layout;
[spikes/gedcom_import](spikes/gedcom_import/README.md) can generate a sample one from a
GEDCOM export.

```
dart pub get
dart run prosapia data/tree
```

### From Firestore, with Google sign-in

This is how production works, run locally against Firebase's emulators. It also needs
the Firebase command-line tools and Java.

```
(cd web && npm install && npm run build)
firebase emulators:start --import=.emulator_data --export-on-exit=.emulator_data
```

The first line builds the browser code: sign-in and the editor. Leave the emulators
running. The first time, omit `--import`, since there is nothing to import yet. In a
second terminal:

```
source tool/emulator_env.sh
dart run prosapia:load --tree carew --owner you@example.com data/tree
dart run prosapia --tree carew
```

`prosapia:load` copies a tree from files into Firestore and Cloud Storage and names its
members. Open http://localhost:8080 and sign in; the emulator shows a stand-in for
Google's account chooser, where you add an account with the owner's email address.
Anyone not on the member list is refused. Owners and editors can edit pages; add
`--editor` and `--viewer` addresses to `prosapia:load` to try the other roles.

Resized images and files fetched from storage go in `.prosapia_cache/`, which can be
deleted at any time.

## Checks

Continuous integration runs these on every pull request. To run them yourself:

```
dart format . && dart analyze && dart test
(cd web && npm run typecheck && npm run lint && npm run build)
npm install && npm run format
```

The last line formats the repository's markdown and TypeScript with Prettier;
`npm run check` only checks. Markdown is wrapped at 88 columns. Prettier pads tables so
their columns line up, which suits small tables; a table with long cells gets
`<!-- prettier-ignore -->` on the line above it and is written compactly, one space
around each cell, so it does not become lines hundreds of characters wide.

A person's page in a tree is the family's text, and Prosapia never re-wraps it.

## How work is organised

- **The plan.** [docs/plan.md](docs/plan.md) lists the milestones being worked on, work
  that is known but not scheduled, and a changelog. Its first section explains how to
  keep it up to date.
- **Decisions.** Design decisions, and the reasons for them, live in the other documents
  in [docs/](docs/).
- **Changes.** Work happens on a branch and merges into `main` through a pull request
  once the checks pass.
