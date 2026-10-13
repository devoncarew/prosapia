# Loom

Loom is a family-history wiki: pages about people, written as markdown with images,
served by a hosted web app that relatives sign in to with a Google account. Eight
directions are set, one design is proposed for confirmation, and three questions are
open. Two of the open questions, privacy tiers and access enforcement, are deferred: for
now every member of a tree sees all of it.

## Status

"Direction set" means you stated it in the brief. "Proposed" is a design this document
suggests and you have not yet confirmed. "Open" has no answer yet. "Deferred" marks an
open item set aside on purpose.

| Area | Status | Where it stands |
| --- | --- | --- |
| Viewing and editing | Direction set | Wikipedia-like pages: text, light formatting, images |
| Backing store | Direction set | Firestore for records, Cloud Storage for photos. Every save is kept as a revision and logged. A nightly export writes the tree as markdown files to a private GitHub repository |
| Interchange | Direction set | GEDCOM 7.0 for import and export |
| Photo information | Direction set | Names, dates and transcriptions embedded in the image file |
| Content model | Direction set | One markdown file per person, in the person's own directory; structured facts on top, free-form entries below |
| Sources and citations | Proposed | A record per source, cited from individual claims |
| Privacy tiers | Open | Deferred. The sharing model is to be decided; four levels are sketched below as a starting point |
| Editing | Direction set | Members with write access edit directly, with no review step. Every edit is logged, attributed and reversible |
| Access enforcement | Open | Deferred with the sharing model. Members are invited by email and sign in with Google; roles are owner, editor and viewer |
| Photo storage | Direction set | JPEGs and HEICs kept as they are; uncompressed scans become JPEG. A front and back are two files paired by name and embedded id |
| Hosting and technology stack | Direction set | A Dart server on Cloud Run behind Firebase Hosting; TypeScript in the browser; Firebase sign-in. Fallback: TypeScript for the server too |
| Merging new entries | Open | An update is kept as a dated entry first; how it is woven into the biography is undecided |

## Principles

- **A family's history outlives the software.** The database is the live record, and the
  whole tree is continuously exported as plain markdown files and photos that need no
  Loom to read.
- **Prose first, structure where it pays.** A contributor can add a story without
  filling in a form.
- **Information travels with its artifact.** What is known about a photo lives inside
  the photo file, including which photo it is the back of.
- **Every change is attributed, logged and reversible.**
- **Private by default.** Only invited members can sign in. Wider sharing is designed
  later, deliberately.
- **Every claim can cite its source.**
- **Standards at the edges.** GEDCOM 7.0 for trees, XMP and IPTC for image metadata.

## Running it

The server needs Dart, `exiftool` and `libvips`.

### From files, with no sign-in

The quickest way to look at a tree. The directory is a tree in Loom's file layout;
`spikes/gedcom_import` can generate a sample one from a GEDCOM export.

```
dart pub get
dart run loom data/tree
```

### From Firestore, with Google sign-in

This is how production works, run locally against Firebase's emulators. It also needs
the Firebase command-line tools, Java and Node.

```
(cd web && npm install && npm run build)        # the browser-side code: sign-in and the editor
firebase emulators:start --import=.emulator_data --export-on-exit=.emulator_data
```

Leave the emulators running. The first time, omit `--import`, since there is nothing to
import yet. In a second terminal:

```
source tool/emulator_env.sh
dart run loom:load --tree carew --owner you@example.com data/tree
dart run loom --tree carew
```

`loom:load` copies a tree from files into Firestore and Cloud Storage and names its
members. Open http://localhost:8080 and sign in; the emulator shows a stand-in for
Google's account chooser, where you add an account with the owner's email address.
Anyone not on the member list is refused. Owners and editors can edit pages; add
`--editor` and `--viewer` addresses to `loom:load` to try the other roles.

Resized images and files fetched from storage go in `.loom_cache/`, which can be deleted
at any time.

## Working on it

```
dart format . && dart analyze && dart test
npm install && npm run format:md
```

The second line wraps the repository's markdown at 88 columns; `npm run check:md` only
checks. A person's page in a tree is the family's text and is never re-wrapped.

## Design documents

| File | Covers |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | System overview, technology stack, storage and versioning, editing, derived views |
| [docs/content-model.md](docs/content-model.md) | Person pages, sources and citations, GEDCOM 7.0 interchange |
| [docs/media.md](docs/media.md) | Photos, embedded metadata, front-and-back scan format |
| [docs/sharing.md](docs/sharing.md) | Privacy, sharing and trust (deferred) |
| [docs/open-questions.md](docs/open-questions.md) | Open questions |
| [docs/plan.md](docs/plan.md) | Planned milestones, known future work, and a changelog of completed milestones |
