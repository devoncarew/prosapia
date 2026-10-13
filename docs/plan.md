# Plan

## How to use this document

This is the working list of what Loom is building, what it might build, and what it has
built. It has three parts:

- **Planned milestones** are scheduled and detailed: each says what will be built and
  how we will know it is done. They are listed in the order they will be worked; the
  numbers are labels, not the order.
- **Known future work** is everything we know is needed or wanted but have not scheduled
  or detailed. One line each.
- **Completed milestones** is a changelog: about one sentence per finished milestone,
  newest first.

Keeping it current:

- **When work is discovered** that is not part of the milestone in hand, add a line to
  Known future work. Do not widen the current milestone.
- **When work is scheduled**, move it out of Known future work into a new planned
  milestone, with its tasks and a "Done when".
- **When a milestone is completed**, delete its section and add a summary line to
  Completed milestones. Anything it left unfinished goes to Known future work.
- **Milestone numbers are never reused**, so a number in a commit message or another
  document always means the same thing.

Design decisions and their reasons live in the other documents, not here:
[architecture.md](architecture.md), [content-model.md](content-model.md),
[media.md](media.md), [sharing.md](sharing.md) and
[open-questions.md](open-questions.md).

## Planned milestones

### Milestone 9: project name

Chosen: **Prosapia**, Latin for lineage or family line, with a short subtitle to give
context. "Loom" was a working title and is widely used by other products. The name needs
settling before it is baked into a repository, a Firebase project and a web address,
since the last two cannot be renamed.

Checked on 13 October 2026:

<!-- prettier-ignore -->
| What | Result |
| --- | --- |
| Domains | `prosapia.app`, `.dev`, `.family` and `.wiki` are not registered. `.com` (since 1999), `.net` and `.org` are taken; `.io` appears to be in use |
| GitHub | The `prosapia` organization was created in February 2026 by someone else and holds one repository. `prosapia-app`, `prosapiaapp` and `getprosapia` are free |
| Package names | `prosapia` is free on pub.dev |
| Other uses | Prosapia Genetics, LLC, a Delaware company, sold DNA ancestry reports from about 2014. Whether it still trades is unknown. *Prosapia* is also a genus of insects, and still a word for lineage in Spanish, Italian and Portuguese |

Still to do:

- Search the trademark registers (the US Patent and Trademark Office, and the European
  and international ones) for "Prosapia", and find out whether Prosapia Genetics is
  still active. It is the one earlier use in the same field.
- Choose the subtitle.
- Register the domain and the GitHub name.
- Rename where the working title appears: the Dart package, the commands, the documents.

Done when: the checks above are complete and recorded here, and the name is in use in
the repository.

### Milestone 10: GitHub project and continuous integration

Depends on milestone 9 for the repository's name.

- Create the GitHub repository and push the history. From then on, work happens on
  branches and merges through pull requests.
- Confirm nothing private is in the history first: the sample photo and its text are
  committed today.
- Continuous integration on every pull request: Dart formatting, analysis and tests; the
  TypeScript type check and build; the markdown check, `npm run check:md`.
- Linting standards: a stricter Dart analysis configuration, and a linter and formatter
  for the TypeScript.
- Decide whether the emulator-based checks, such as the Firebase spike, run in
  continuous integration.
- A licence and a short contributing note, if the repository is to be public.

Done when: a pull request that breaks formatting, analysis or a test is marked as
failing, and the main branch is green.

### Milestone 11: Firebase project

Depends on milestone 9, because a project's id is permanent. Needed before milestone 5.

- Create the Firebase project and attach a billing account on the pay-as-you-go plan,
  with a budget alert.
- Choose the region for Firestore and Cloud Storage. This cannot be changed later.
- Switch on Firestore, Cloud Storage and sign-in with Google.
- Register the web app and record its settings where the server reads them.
- Decide how the deployed server and a developer's machine each get credentials, without
  a long-lived key file if possible.
- Deploy the database and storage rules already in the repository, which deny all direct
  access.

Done when: the server, run locally, serves a small test tree from the real project to a
member who signed in with a real Google account.

### Milestone 5: deploy and backup

Put the site on the internet for one family, in the Firebase project from milestone 11.

- The server in a container on Cloud Run, behind Firebase Hosting, with real Google
  sign-in.
- Confirm that a sign-in with a forged signature is refused. The emulators cannot test
  this.
- Invite members by email address, and change or remove them, from the site.
- A nightly export of the tree, in the file layout, to a private GitHub repository: one
  commit per logged change, with its author.
- Firestore's scheduled backups switched on.

Done when: invited relatives can sign in at a real address and edit, and the exported
repository, loaded by the server in file mode, renders the same site.

### Milestone 12: loading a large existing tree

A family arrives with a GEDCOM file and a backup holding its media; the sample backup is
about 1 GB. Locally this is easy: the import spike reads both from disk. Once the site
is hosted, a file that size cannot simply be uploaded through a web form and unpacked by
the server.

- Decide the process. The simplest is that a privileged person runs the existing tools
  on their own machine, pointed at the production project, before the site is opened to
  the family. Alternatives are uploading the backup to a storage bucket for a one-off
  job to unpack, or selecting only the referenced media in the browser.
- Whichever is chosen, write it down as steps someone else could follow, including the
  credentials it needs.
- Make the loader safe to rerun: skip media already uploaded, and say clearly that it
  replaces the tree's records.
- Apply the media rules on the way in: files over the size limit are skipped and listed,
  and the file types the backup mislabels are handled.

Done when: the real family tree, with its photos, is loaded into the production project
by following the written steps.

This is separate from milestone 7, which is about importing a GEDCOM file through the
browser into a tree that is already in use.

### Milestone 6: photos in the app

- Upload a front, an optional back and the related text, from the browser straight to
  Cloud Storage. The server stores JPEGs and HEICs as they are, encodes uncompressed
  scans to JPEG, names the pair, and writes the metadata into each file.
- Verify the XMP and IPTC field names in [media.md](media.md) against the
  specifications, and define Loom's own field for which side a file is.
- Choose the JPEG quality for scans using a real full-resolution scanner output.
- Front and back shown together wherever the photo appears.
- Rolls: create one, add photos in order, and suggest a frame's date or place to the
  rest.
- Tag the people in a photo; the names are written into the file.

Done when: a photo added through the app shows on the right people's pages with its
back, and both files downloaded from storage still carry their names, date,
transcription and pairing.

### Milestone 7: GEDCOM import

The spike in [spikes/gedcom_import](../spikes/gedcom_import/README.md) already converts
a real GEDCOM 5.5.1 export into the file layout. This milestone makes it part of the
app.

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

- Add a person: a child, a parent, a partner, or someone unconnected.
- Remove a person, and merge two records that turn out to be the same person.
- Edit partnerships, which are separate records with no editor yet.
- A page for a shared event (a wedding, a reunion) or a household, if the content model
  adopts them.
- Places as records with coordinates and historical names.
- Record ids from other systems (FamilySearch, WikiTree) on a person, and link out to
  them.

### Editing

- A friendlier editor for the facts at the top of a page, which are raw text today.
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

Loom can call a language model, Claude or Gemini, to help write the record. Three rules
shape every use:

- **Never when serving a page.** A model runs when a member asks for it, or in a batch
  an owner starts, never as part of showing content. This keeps cost bounded and pages
  fast.
- **Nothing a model writes enters the record without a person choosing it.** The model
  produces a draft; a member reads it, edits it if they wish, and saves it as an edit
  under their own name.
- **The record says so.** A revision that began as a model's draft is marked as such,
  with the model's name, so anyone reading the history can tell.

Possible uses, none scheduled:

- Authoring: draft a biography from a person's facts, memories and photo captions.
- Integrating: weave loose memories into the biography, as discussed in
  [content-model.md](content-model.md).
- Rewriting: tidy or shorten a passage, or make an imported note read as prose.
- Structuring: suggest facts, dates and people from a story someone has typed.
- Transcribing: read the handwriting on the back of a photo, or a scanned letter or
  certificate.
- Describing: suggest a caption, a rough date or a place for a photo.
- Checking: point out conflicts, such as a child born after a parent's death.

Open: which model for which job, what it costs per tree, and whether an owner must
switch the feature on, since using it sends family data to the model's provider.

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
- More than one tree on one server.
- Decide when a tree is too large to hold in memory, and what replaces that.

## Completed milestones

Newest first.

- **Milestone 8, markdown formatter.** `npm run format:md` wraps the repository's
  markdown at 88 columns using Prettier, and `npm run check:md` verifies it; tables too
  wide for the line are marked `<!-- prettier-ignore -->` and kept compact, and tree
  content is left alone.
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
