# Plan

## How to use this document

This is the working list of what Prosapia is building, what it might build, and what it
has built. It has three parts:

- **Milestones** are the scheduled work. Each says what will be built and how we will
  know it is done. They are listed in the order they will be worked; milestone numbers
  are labels, not the order.
- **Known future work** is everything we know is needed or wanted but have not scheduled
  or detailed. One line each.
- **Completed milestones** is a changelog: about one sentence per finished milestone,
  newest first.

Keeping it current:

- **When work is discovered** that is not part of the milestone in hand, add a line to
  Known future work. Do not widen the current milestone.
- **When work is scheduled**, move it out of Known future work into a new milestone,
  with its tasks and a "Done when".
- **When a milestone is completed**, delete its section and add a summary line to
  Completed milestones. Anything it left unfinished goes to Known future work.
- **Milestone numbers are never reused**, so a number in a commit message or another
  document always means the same thing.

Design decisions and their reasons live in [design.md](design.md) and the documents it
links to, not here.

## Milestones

### Milestone 18: the first visit

Journey 10. Everything below is built; what is left is the Done when, which needs
relatives who have not seen the site before.

- An invitation email that says who invited them and what Prosapia is.
- Readable addresses for people's pages, such as `/people/carew-howard-joseph-tbczm8`,
  so a link someone shares says who it is. Only the trailing id is relied on.
- A home page that orients a newcomer: a welcome, their own page with their close family
  and Add a memory, the latest changes, and where to go next.
- Every page readable on a phone, since a first visit is often on one.

Done when: a relative who has never seen Prosapia can accept an invitation, find their
own family, and add a memory without help.

### Milestone 20: dogfooding and polish

Using the deployed site on the real tree, and fixing what that turns up. Small items are
kept in the [punch list](punchlist.md) and worked from there.

- A design pass over the photo pages. The person page, the editor, the change history
  and Recent changes have had theirs.

Done when: the family historian has used the deployed site for a few weeks, and what
they found is fixed or moved to Known future work.

### Milestone 15: events and memories

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

### Milestone 17: more help from the model

- Entry from a sentence: typing "Margaret moved to Chicago with her sister in spring
  1925" proposes fact lines or an event, for the person to check before saving.
- Weave loose memories into an existing biography, as a proposed edit.

Built so far: **Claude: Draft…** takes a request and notes to work in, which covers
targeted requests such as "add a brief mention of the trip John took with Jane and Sam
in 2011", and marks the lines it changed; and **Claude: Research ideas** on a person's
page suggests records to look for and where, as advice only.

Done when: journeys 1 and 2 can each start from one typed sentence, and nothing the
model proposes is saved without the person confirming it.

### Milestone 19: editing on a phone

- Adding a memory, correcting a fact and tagging a photo work comfortably on a phone.

Done when: journey 7 works on a phone.

### Milestone 7: GEDCOM import

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
- Bring back a deleted page when the pages around it have changed since, by working out
  what to take back, instead of restoring only the page as now.
- Give a page to a plain name written elsewhere than a relationship line, such as a
  fact's people or the story.
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
- A way to report a mistake without editing, for those who would rather not.

### Sources and research

- Source records and citations: create a source, cite it from a fact or from prose, and
  mark uncited claims.
- Capture a record from a research site as a draft source.

### Language-model assistance

Uses not yet scheduled; the rules every use follows are in
[design.md](design.md#language-models).

- Resolving names to people. A memory that mentions "Michelle", or notes being revised,
  could have the name linked to the right person, such as `@carew-michelle-x4k2ab`. The
  model needs to know who is meant: either give it the likely people with the request
  (the page's relatives, people with that name nearby in the tree), or give it tools to
  look people up in the tree as it writes.
- Transcribing a scanned letter or certificate.
- Checking: point out conflicts, such as a child born after a parent's death, beyond the
  simple checks in milestone 13.
- Research leads: Claude searches open sites (Find a Grave, Chronicling America, the
  Internet Archive) with the API's web search tool, and returns leads with links for the
  person to check and copy in, never facts saved directly. Watch for people with the
  same name, and for names of living people sent to a search engine.

### Photos and media

- Choose the JPEG quality for scans from a real full-resolution scanner output; 92 is a
  placeholder.
- Upload files larger than Cloud Run's 32 MB request limit, such as large TIFF scans,
  straight to storage with a signed upload address.
- Documents: read a PDF's pages in the site, and add a text layer (OCR) to typed ones so
  they can be searched.
- Video: store short clips, link to long ones, as proposed in [media.md](media.md).
- Multi-page scanned PDFs, such as the two baby books: keep as one document, or store as
  a set of page images.
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
- When a tree is loaded again with `--replace`, delete stored files the new tree no
  longer uses. They are left behind today.
- Run the Firebase emulator checks in continuous integration, so sign-in and storage are
  tested on every change.
- Require the continuous integration checks to pass before a pull request can merge (a
  GitHub repository setting).
- More than one tree on one server.
- Decide when a tree is too large to hold in memory, and what replaces that.

## Completed milestones

Newest first.

- **Milestone 5, deploy and backup.** The server runs on Cloud Run in `us-west1` behind
  Firebase Hosting at `prosapia.app`, with its own service account and the Anthropic key
  in Secret Manager; owners invite members, change their roles and remove them from
  Settings; a forged sign-in is refused; Firestore keeps daily backups for two weeks;
  and a nightly job exports the tree to a private GitHub repository, one commit per
  logged change, which the server renders the same in file mode.
- **Milestone 6, photos in the app.** Photos are added from a person's page or from
  Photos, several at once with a shared date, place and people, and an optional back
  that Claude can transcribe; a photo names the people in it rather than belonging to a
  page, and photos added together form a set. Caption, date, place, people, the writing
  on the back, the pairing and the set are written into the files, and can be changed
  later without re-encoding the image.
- **Milestone 16, help from a language model.** Claude can draft or revise a page's
  story, improve a selection, and tidy a memory; its text replaces what it acted on in
  the editor, with undo, and nothing is saved until the person publishes. Claude Haiku
  writes every change summary, so the editor no longer asks for one. Owners switch help
  on with a monthly limit and each call's cost is recorded; the history shows which
  revisions had help, and each version's diff from the one before.
- **Milestone 14, relationships in the text.** A name typed in a `Children:`,
  `Parents:`, `Siblings:` or `Partner:` line shows on the page with an action to give
  that person a page, which first offers similar people already in the tree and starts
  the new page with what is known, such as both parents; pages can be deleted, with
  references elsewhere becoming plain names; contradictions between two pages are
  flagged, with a button to remove either side; and a change of several pages is saved,
  and undone from Recent changes, as one.
- **Milestone 13, the page syntax and its editor.** Pages are stored exactly as written,
  as "Name: value" fact lines and markdown, and read forgivingly: dates are understood
  in many forms, `@` references link people, relationships stated on either page count,
  and anything unreadable or implausible is listed on the page. The editor highlights
  the syntax, completes people, places and labels, shows a legend, and keeps unsaved
  text; the search box suggests people. The real tree was converted with its history
  kept.
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
