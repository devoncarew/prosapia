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

None scheduled. The next is chosen from Known future work.

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

- Events and memories (was milestone 15; journeys 1 and 7): add an event to someone's
  life (moved, served, emigrated, graduated, or anything else) with a forgiving date and
  place, the other people involved, and optionally words and a photo; an event with
  several people shows on each of their timelines, once the shared-events question in
  [content-model.md](content-model.md) is settled; memories gain an optional date, place
  and people, and show on the timeline when dated.

- Watchlist: follow a person and hear about changes.
- Blame: for any sentence or fact, who added it and when.
- Optional review of edits, for families that want it.
- A way to report a mistake without editing, for those who would rather not.
- Editing on a phone (was milestone 19): adding a memory, correcting a fact and tagging
  a photo work comfortably on one, so that journey 7 works on a phone.

### Sources and research

- Capture a record from a research site as a draft source.

### Language-model assistance

Uses not yet scheduled; the rules every use follows are in
[design.md](design.md#language-models).

- Resolving names to people, with tools. A memory that mentions "Michelle", or notes
  being revised, could have the name linked to the right person, such as
  `@carew-michelle-x4k2ab`. Give the model tools to look people up as it writes:
  `find_person(name, near)` for candidates and how they are related, `read_page(id)`,
  and `search_tree(text)` over the full-text index. Cap the calls (about five) so a
  request stays inside Hosting's 60-second limit.
- Offer what the tree says elsewhere when revising a story, not only for a first draft,
  when the editor asks for it ("add anything else the tree knows").
- Entry from a sentence: typing "Margaret moved to Chicago with her sister in spring
  1925" proposes fact lines or an event, for the person to check before saving.
- Weave loose memories into an existing biography, as a proposed edit.
- Checking: point out conflicts, such as a child born after a parent's death, beyond the
  simple checks in milestone 13.
- Research leads: Claude searches open sites (Find a Grave, Chronicling America, the
  Internet Archive) with the API's web search tool, and returns leads with links for the
  person to check and copy in, never facts saved directly. Watch for people with the
  same name, and for names of living people sent to a search engine.

### Photos and media

- Choose the JPEG quality for scans from a real full-resolution scanner output; 92 is a
  placeholder.
- Documents: read a PDF's pages in the site, rather than only its first page's preview.
- A text layer (OCR) in typed PDFs, so a downloaded copy can be searched in a PDF
  viewer. The transcription is in the file's metadata and searched in Prosapia already.
- A design pass over the photo pages.
- Multi-page scanned PDFs, such as the two baby books: keep as one document, or store as
  a set of page images.
- Video (was milestone 21): store short clips like photos, up to a size limit (working
  figure 50 MB), with a poster frame and playback, and add long videos as links
  (YouTube, a shared drive) with their date, place and people, as proposed in
  [media.md](media.md). Files over Cloud Run's 32 MB request limit, including large TIFF
  scans, go straight to storage with a signed upload address. The database record is the
  authority for video, so settle how it is exported.
- Audio recordings.
- Suggesting where faces are in a photo.
- Check that embedded text survives email, photo services and messaging apps.
- Add photos from Google Photos, beside choosing files. Google's Photos Picker API lets
  a person choose photos in Google Photos: Prosapia creates a picking session, the
  person picks in a Google Photos tab, and the server lists the chosen items and
  downloads the originals into staging, so the 32 MB upload limit does not apply and
  shared albums work. It needs the `photospicker.mediaitems.readonly` scope, asked for
  on top of sign-in, which sees only what the person picks. Before building, add the
  scope to the OAuth consent screen and see how the Cloud Console classes it. If it is
  sensitive, Google must verify the app before the public can use it; until then an app
  in Testing status works for up to 100 listed test users, whose grants expire after
  about a week. Android's file chooser already offers Google Photos. Asked for once so
  far (October 2026): look at the scope and verification when we build it, or when a few
  more people ask.

### Import and export

GEDCOM import in the app (was milestone 7). The spike in
[spikes/gedcom_import](../spikes/gedcom_import/README.md) already converts a real GEDCOM
5.5.1 export into the file layout, and is how a tree is first loaded.

- Import from the browser: upload a GEDCOM file, preview what it will add, and apply it
  as one logged change that can be undone as a whole.
- Re-import: match people already in the tree by their GEDCOM reference, so a second
  import of the same file changes nothing.
- Read GEDCOM 7.0 as well as 5.5.1, and verify the tags listed in
  [content-model.md](content-model.md) against the specification.
- Data export, mainly for preservation: download the whole tree from Settings as one
  archive that keeps everything, at full fidelity, and says what it holds:
  - the pages as written and the original photos and documents, unchanged, with their
    details embedded, as the nightly export already lays them out;
  - `tree.json`, the same information as structured data (people, relationships and
    their qualifiers, events with dates, places and sources, and each file's details),
    with ids matching the file names, so another system can read it back completely;
  - a README describing each file and field, the fact syntax and the date grammar;
  - a copy of the site as plain HTML that works offline, for reading.
- GEDCOM export, for moving into other genealogy software, as a GEDZIP (`.gdz`) file:
  GEDCOM 7 with the media in one zip. Not needed soon.

### Views

- Fuller family tree and descendant charts, beyond milestone 23's view.
- A 3D view of the whole tree, as a spike with three.js (or `3d-force-graph` on it):
  people as points, parent and partner links as lines, and height set by birth year. It
  might show the shape of the family at a glance (its branches, where research is thin,
  who was alive at the same time) and untangle remarriages and cousin marriages that
  cross in 2D. Against it: names are hard to read in 3D, orbiting and zooming are hard
  for less technical relatives and on phones, and it gives nothing to screen readers or
  print. Worth a day to find out; a 2D chart that tilts into depth may keep the best of
  it.
- Every page readable on a phone (left open from milestone 18). Viewing works; check
  each page on a real phone and fix what does not.
- A "needs source" report.
- Printing: family books and wall charts. Make PDFs for a person or a branch as PDF/A,
  the archival form; PDF/A-3 can also carry the original photos and the data inside the
  file, which makes a book a way to preserve the data as well as to read it.

### Sharing and privacy

Prosapia is in a private preview, shared only with a few trusted testers, so none of
this is needed until a wider preview is chosen. It should be done before then.

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

- **Milestone 26, items and citations.** The tree holds items: photos and documents with
  a file, and sources without one, such as a web obituary with its link and pasted text,
  added from Photos or a person's page, with a file attachable later. Any item is
  referred to with `#` and cited from a fact or the story; its page lists what cites it,
  and a person's page gathers its sources in one section. A PDF with text offers it as
  the transcription when asked rather than filling it in, since a long document would
  surprise. The editor has a Source button, the "+ add" forms ask where it came from,
  and `source: needed` marks a claim for the Sources wanted list.
- **Milestone 25, page format changes.** The decisions of milestone 24 are in practice:
  empty facts are prompts, not problems, and new pages start with them; a fact repeated
  when records disagree shows the others as "also recorded"; `Family name:`, kinds of
  name and four values for sex are read; Format puts facts in the normal order with
  notes last; `#` references link photos and documents, `[source: …]` cites from the
  story with a list at the end, and FamilySearch, WikiTree and Find a Grave ids link
  out; a `Siblings:` line is offered to be recorded through parents; and the writing
  guide explains them. The 46 live pages that differed were brought to the new form as
  one logged change.
- **Milestone 24, page format decisions.** Each open question about the page format was
  decided, weighed against GEDCOM 7 and GEDCOM X on the problems people hit, ease of
  editing and resilience, and recorded in [content-model.md](content-model.md): a normal
  fact order with notes last, no comments, blank fields on new pages, where
  relationships are written, repeated facts when records disagree, names, sex, `#`
  references to anything that is not a person, and citing sources from facts and the
  story.
- **Milestone 23, a family tree view.** **Family tree** in the header, on each person's
  page and on the home page shows an hourglass chart: grandparents and parents above,
  brothers and sisters either side, partners beside, and children and grandchildren
  below, with hints of more family beyond. Choosing anyone recentres it in place, with
  the cards moving to their new places; the home page shows the viewer's own.
- **Milestone 22, notes and transcriptions.** Every photo and document has a
  transcription of what is written on it (for a photo with a back, the back) and notes
  about it, written into the file (`dc:description` and EXIF `UserComment`), shown on
  its page, searched, and given to first drafts. **Claude: Transcribe** works on any
  photo, back or document, when adding or editing, and reads a document a page at a
  time.
- **Milestone 20, dogfooding and polish.** Using the deployed site on the real tree
  brought a new fact syntax with quoted and labelled parts, a Format button and normal
  form, change history with a friendly diff, viewer-local times, paged photos and a
  photo strip, PDF documents, upload progress and undo for deleted pages. Polish items
  are now noted as the site is used, in the [punch list](punchlist.md).
- **Milestone 18, the first visit.** Invited relatives get an email saying who invited
  them and what Prosapia is; people's pages have readable addresses; and a home page
  welcomes a newcomer with the latest changes and where to go next. Problems with first
  sign-in are logged as bugs; checking every page on a phone is in Known future work.
- **Milestone 17, more help from the model.** **Claude: Draft…** takes a request and
  notes to work in and marks the lines it changed; a first draft is given what the tree
  says about the person elsewhere and lists where it drew from; and **Claude: Research**
  suggests records to look for and where, as advice only.
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
