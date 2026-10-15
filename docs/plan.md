# Plan

## How to use this document

This is the working list of what Prosapia is building, what it might build, and what it
has built. It has three parts:

- **Planned releases** group the scheduled milestones. Each milestone says what will be
  built and how we will know it is done. Releases, and the milestones within them, are
  listed in the order they will be worked; milestone numbers are labels, not the order.
- **Known future work** is everything we know is needed or wanted but have not scheduled
  or detailed. One line each.
- **Completed milestones** is a changelog: about one sentence per finished milestone,
  newest first.

Keeping it current:

- **When work is discovered** that is not part of the milestone in hand, add a line to
  Known future work. Do not widen the current milestone.
- **When work is scheduled**, move it out of Known future work into a new milestone in a
  release, with its tasks and a "Done when".
- **When a milestone is completed**, delete its section and add a summary line to
  Completed milestones. Anything it left unfinished goes to Known future work.
- **Milestone numbers are never reused**, so a number in a commit message or another
  document always means the same thing.

Design decisions and their reasons live in [design.md](design.md) and the documents it
links to, not here.

## Planned releases

Milestones are grouped into releases. Each release is a point where Prosapia is usable
for something new; releases, and the milestones within them, are listed in the order
they will be worked. Work whose design is clear comes earlier; work whose design is
still forming comes later. The [user journeys](journeys.md) describe what the editing
work is aiming at.

Releases A to C come before relatives are invited. Release D follows.

### Release A: the core of editing

Goal: the family historian keeps their real tree comfortably, on a desktop, without
YAML. Nobody else is invited yet; the real tree is loaded and used privately. Editing on
a phone is not a goal yet; viewing on one is.

#### Milestone 14: adding people and relationships

Journeys 2 and 3.

- Add a child, parent, partner or sibling from a person's page, in a small dialog with
  only a name required; the other parent or partnership is offered from what the tree
  holds.
- Before creating someone, check for an existing person with a similar name and dates,
  and offer to link to them instead.
- Edit partnerships: dates, places, how and when they ended, their order.
- Remove a person, with their links, as a change that can be undone.
- A change that touches several records (a new person plus their links) is saved and
  undone as one.

Done when: a new child can be added to an existing couple in under a minute, appears
among both parents' children and their siblings, and can be undone in one step.

#### Milestone 13: the page syntax and its editor

Journeys 2, 4 and 8. The syntax is decided in
[content-model.md](content-model.md#page-syntax): facts as "Name: value" lines, `@`
references to people, `[date: …]` and `[place: …]`.

- Start with a short prototype on the real tree to settle the open details: the id form
  after `@`, the fact names, and how a fact with a date, a place and people is written.
- Read and write pages in the new syntax, forgivingly: an unreadable line is kept and
  shown as unresolved. Convert existing pages from YAML, as a logged change.
- Render `@` references as linked names, and dates and places for display; show anything
  unresolved with an explanation.
- Forgiving dates inside fact lines: accept the ways people write dates ("about 1925",
  "spring 1925", "the 1880s", "14 March 1887", "3/14/1887", "between 1880 and 1885",
  "bapt. 1891"), show how each was understood, and ask only when a date is truly
  ambiguous.
- In the editor: syntax highlighting, completion after `@` (people, with years and
  parents to tell namesakes apart) and inside `[place: …]` (places already in the tree),
  and a short legend. The same people completion powers the search box.
- Gentle checks: implausible dates produce a question, never a refusal.
- Unsaved input survives a closed tab.

Done when: a birth date can be corrected and an occupation added by editing fact lines,
a person can be referenced by typing `@` and part of their name, and no page shows YAML.

### Release B: help and photos

Goal: the most useful language-model feature, and the ability to add photos, before
relatives arrive.

#### Milestone 16: language-model foundation and biography drafts

Journey 5. The rules every use follows are in [design.md](design.md#language-models).

- Choose the model provider, Claude or Gemini, by trying both on biography drafting; the
  server calls it, never the browser.
- An owner switches the feature on for their tree. Each call's cost is recorded, with a
  monthly limit.
- Draft a biography from a person's facts, memories and photo captions, shown beside the
  current page for editing before it is saved.
- Revisions that began as a model's draft record the model's name.

Done when: a usable draft can be produced and saved for a person with only facts, and
for one with several memories, and the history shows which revisions began as drafts.

#### Milestone 6: photos in the app

Journey 6.

- Upload a front, an optional back and the related text, from the browser straight to
  Cloud Storage. The server stores JPEGs and HEICs as they are, encodes uncompressed
  scans to JPEG, names the pair, and writes the metadata into each file.
- Offer a transcription of the back, and a suggested caption and rough date, from a
  language model.
- Tag the people in a photo using people completion; the names are written into the
  file.
- Verify the XMP and IPTC field names in [media.md](media.md) against the
  specifications, and define Prosapia's own field for which side a file is.
- Choose the JPEG quality for scans using a real full-resolution scanner output.
- Front and back shown together wherever the photo appears.
- Rolls: create one, add photos in order, and suggest a frame's date or place to the
  rest.

Done when: a photo added through the app shows on the right people's pages with its
back, and both files downloaded from storage still carry their names, date,
transcription and pairing.

### Release C: open to the family

Goal: relatives are invited, can find their way around, and can contribute from a
desktop.

#### Milestone 5: deploy and backup

- The server in a container on Cloud Run in `us-west1`, beside the database and storage,
  behind Firebase Hosting. On Cloud Run the server's credentials come from its service
  account, so no key file is needed there either.
- Attach `prosapia.app`, which is reserved. Until then the site is at
  `prosapia-ea818.web.app`.
- Confirm that a sign-in with a forged signature is refused. The emulators cannot test
  this.
- Invite members by email address, and change or remove them, from the site.
- A nightly export of the tree, in the file layout, to a private GitHub repository: one
  commit per logged change, with its author.
- Firestore's scheduled backups switched on.

Done when: invited relatives can sign in at `prosapia.app` and edit, and the exported
repository, loaded by the server in file mode, renders the same site.

#### Milestone 18: a relative's first visit

Journey 10.

- An invitation email that says who invited them and what Prosapia is.
- A first page after sign-in that orients a newcomer: their own page or their nearest
  relative's, and one easy thing to do.
- Every page readable on a phone.
- A way to report a mistake without editing, for those who would rather not.

Done when: a relative who has never seen Prosapia can accept an invitation, find their
own family, and add a memory without help.

### Release D: after opening

Goal: richer entry and more help, shaped by how the family actually uses Prosapia.

#### Milestone 15: events and memories

Journeys 1 and 7.

- Add an event to someone's life: a kind (moved, married, served, emigrated, graduated,
  or anything else), a forgiving date and place, the other people involved, and
  optionally some words and a photo.
- An event involving several people appears on each of their timelines. Settle the
  shared-events question in [content-model.md](content-model.md), and how an event is
  written in the page syntax, to do this.
- Memories gain an optional date, place and people, and show on the timeline when dated.

Done when: an event with two people involved, entered from one person's page, appears on
both people's timelines.

#### Milestone 17: more help from the model

- Entry from a sentence: typing "Margaret moved to Chicago with her sister in spring
  1925" proposes fact lines or an event, for the person to check before saving.
- Weave loose memories into an existing biography, as a proposed edit.
- Tidy or shorten a passage, or turn an imported note into prose.

Done when: journeys 1 and 2 can each start from one typed sentence, and nothing the
model proposes is saved without the person confirming it.

#### Milestone 19: editing on a phone

- Adding a memory, correcting a fact and tagging a photo work comfortably on a phone.

Done when: journey 7 works on a phone.

#### Milestone 7: GEDCOM import

The spike in [spikes/gedcom_import](../spikes/gedcom_import/README.md) already converts
a real GEDCOM 5.5.1 export into the file layout, and milestone 12 makes it the way a
tree is first loaded. This milestone brings import into the app, for trees already in
use.

- Import from the browser: upload a GEDCOM file, preview what it will add, apply it as
  one logged change that can be undone as a whole.
- Read GEDCOM 7.0 as well as 5.5.1, and verify the tags listed in
  [content-model.md](content-model.md) against the specification.
- Re-import: match people already in the tree by their GEDCOM reference instead of
  duplicating them.
- GEDCOM export.

Done when: a real export imports through the app, a second import of the same file
changes nothing, and the mapping table is confirmed or corrected.

## Known future work

Not yet scheduled or detailed. Roughly grouped; the order means nothing.

### People and relationships

- Merge two records that turn out to be the same person.
- A page for a shared event (a wedding, a reunion) or a household, if the content model
  adopts them.
- Places as records with coordinates and historical names.
- Record ids from other systems (FamilySearch, WikiTree) on a person, and link out to
  them.

### Editing

- A formatted editor for the story, for relatives who will not write markdown.
- Talk pages: a discussion thread per person.
- Watchlist: follow a person and hear about changes.
- Blame: for any sentence or fact, who added it and when.
- Contributions from people who are not members, such as a correction sent by email.
- Optional review of edits, for families that want it.

### Sources and research

- Source records and citations: create a source, cite it from a fact or from prose, and
  mark uncited claims.
- Capture a record from a research site as a draft source.

### Language-model assistance

Uses not yet scheduled; the rules every use follows are in
[design.md](design.md#language-models).

- Transcribing a scanned letter or certificate.
- Checking: point out conflicts, such as a child born after a parent's death, beyond the
  simple checks in milestone 13.

### Photos and media

- Documents (letters, certificates, census pages): previews and metadata for PDFs.
- Video: store short clips, link to long ones, as proposed in [media.md](media.md).
- Audio recordings.
- Suggesting where faces are in a photo.
- Check that embedded text survives email, photo services and messaging apps.

### Views

- Family tree and descendant charts.
- A "needs source" report.
- Printing: family books and wall charts.

### Sharing and privacy

- The sharing model: visibility levels per person, and treating living people as private
  by default.
- Removing something for good, from revisions, the change log and the exported
  repository.
- Consent and legal duties for data about living people.
- Linking trees that share ancestors.

### Running it

- Reload only what changed after a save, not the whole tree.
- Export on every change, not nightly.
- Search the European and international trademark registers for "Prosapia" before any
  commercial launch. The US register showed no conflict.
- Run the Firebase emulator checks in continuous integration, so sign-in and storage are
  tested on every change.
- Require the continuous integration checks to pass before a pull request can merge (a
  GitHub repository setting).
- More than one tree on one server.
- Decide when a tree is too large to hold in memory, and what replaces that.

## Completed milestones

Newest first.

- **Milestone 12, loading the real family tree.** The Carew family tree, 203 people and
  135 photos and documents, is loaded into the production project as tree `carew`,
  visible only to its owner; the loader is now safe to rerun, and
  [loading.md](loading.md) gives the steps.
- **Milestone 11, Firebase project.** The project `prosapia-ea818` has billing with a
  budget alert, Firestore and Cloud Storage in `us-west1`, Google sign-in, a registered
  web app, and deny-all rules; the server, run locally with a developer's own `gcloud`
  login, serves an invented test tree from it to a member signed in with a real Google
  account.
- **Milestone 10, GitHub project and continuous integration.** The code is public at
  `devoncarew/prosapia` under the BSD 3-Clause licence; every pull request runs Dart
  formatting, strict analysis and tests, the browser code's type check, lint and build,
  and Prettier checks, and the README now introduces the project, with setup moved to
  CONTRIBUTING.md.
- **Milestone 9, project name.** The project is named Prosapia, Latin for lineage or
  family line, with the subtitle "Genealogy, in prose"; `prosapia.app` was unregistered,
  and the US trademark register held only an unrelated application for agave spirits, so
  Loom, the working title, was renamed throughout.
- **Milestone 8, markdown formatter.** `npm run format` wraps the repository's markdown
  at 88 columns using Prettier, and `npm run check` verifies it; tables too wide for the
  line are marked `<!-- prettier-ignore -->` and kept compact, and tree content is left
  alone.
- **Milestone 4, editing.** Members with write access edit an existing person's page as
  text with a live preview; every save is a revision and a change-log entry, stale saves
  are refused, and history, compare, restore, recent changes and "Add a memory" work.
- **Milestone 3, Firebase foundation.** A spike showed Dart works with Firebase's
  official Admin SDK ([spikes/firebase](../spikes/firebase/README.md)); the server now
  reads a tree through a store interface, from files or from Firestore and Cloud
  Storage, and serves it only to members signed in with Google.
- **Milestone 2, read-only server.** A Dart server renders the sample tree as a site:
  person pages with infobox, timeline and photos, a people list, a gallery, and
  full-text search over an in-memory index.
- **Milestone 1, image-format spike.** One photo was packaged sixteen ways
  ([spikes/image_format](../spikes/image_format/README.md)); the outcome is that JPEGs
  and HEICs are stored as they are, scans become JPEG, and a front and back are two
  files paired by name and embedded id.
- **Milestone 0, sample tree.** A script
  ([spikes/gedcom_import](../spikes/gedcom_import/README.md)) generates a 203-person
  sample tree in the file layout from a real GEDCOM 5.5.1 export, which tested the
  content model and shaped several changes to it.
