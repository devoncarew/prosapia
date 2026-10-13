# Plan

Eight milestones take Loom from design to a deployed site a family can edit. Milestones 0, 1 and 2 are done. The rest build on each other.

| # | Milestone | Settles | Depends on |
| --- | --- | --- | --- |
| 0 | Sample tree (done, generated) | The content model and file layout | Nothing |
| 1 | Image-format spike (done) | How a photo is stored | Nothing |
| 2 | Read-only server (done) | Dart for rendering, the index, display copies | 0 |
| 3 | Firebase foundation | Dart with Firebase; the store interface; sign-in and members | 2 |
| 4 | Editing | The TypeScript editor; revisions, history and restore | 3 |
| 5 | Deploy and backup | Hosting on Cloud Run; the nightly export to GitHub | 4 |
| 6 | Photos in the app | Upload, pairing, tagging and rolls | 1, 4 |
| 7 | GEDCOM import | The GEDCOM mapping; older-version support | 4 |

Not planned yet: the sharing model, weaving entries into biographies, research capture and generated summaries.

## Milestone 0: sample tree

Status: a sample tree of 203 people is generated from a real GEDCOM export by the script in [spikes/gedcom_import](../spikes/gedcom_import/README.md). It is sample data only, kept out of the repository in `data/tree/`. Findings are in [content-model.md](content-model.md#what-the-sample-import-showed). The export already holds all the prose the source tree has, so no hand enrichment is planned; sources and loose updates get sample content when later milestones need them.

The original aim: a small real tree as files, to find where the content model does not fit.

- Create a tree in the file layout from [architecture.md](architecture.md).
- Write ten real people across three generations, their partnerships, and three or four sources.
- Add a few loose updates, like the trip example, as dated entries.
- Read the result as plain files.

Done when: the tree exists, and [content-model.md](content-model.md) is updated with whatever did not fit. This is the place to answer the open questions on shared events, places and conflicting claims, at least provisionally.

## Milestone 1: image-format spike

Done. One photo was packaged sixteen ways with the script in [spikes/image_format](../spikes/image_format/README.md) and measured for size, quality, and whether the back and the text survived.

Outcome, recorded in [media.md](media.md): JPEGs and HEICs are stored as they are, uncompressed scans become JPEG, and a front and back are two files paired by name and embedded id rather than one combined file.

## Milestone 2: read-only server

Status: done. `dart run loom data/tree` serves the sample tree: person pages with infobox, timeline and photos, a people list, a photo gallery, media pages and full-text search. The index and display copies live in `.loom_cache/` and are rebuilt after deletion. It loads 203 people and 136 media files in under a second. No browser-side code was needed yet; TypeScript starts with the editor in milestone 4.

A Dart server that reads the sample tree from files and serves it as a website.

- Person pages rendered from markdown, with an infobox from the structured facts, working links between people, and footnote citations.
- A SQLite index built from the tree: names, relationships, full-text search.
- One derived view beyond the page: a timeline from structured events and dated entry headings.
- Display copies of images, made on the fly when a page is served.

Done when: the sample tree can be browsed and searched locally, and deleting the index and cache then restarting rebuilds both.

## Milestone 3: Firebase foundation

Move the working site from files onto Firebase, running locally against Firebase's emulators. This is where the choice of Dart is most at risk, so it starts with a spike.

- **Spike first:** from Dart, read and write Firestore, verify a Google sign-in, and read a file from Cloud Storage, all against the emulators. Note which packages are official and which are community. If this is impractical, switch the server to TypeScript here.
- A store interface in the server with two implementations: files, as today, and Firestore.
- A loader that puts a tree in the file layout into Firestore and Cloud Storage. The sample tree goes in this way.
- Sign in with Google, a session, and a member list with the roles owner, editor and viewer.
- The server caches the tree in memory and reloads when the tree's version number changes.
- Display copies served without a local disk.

Done when: the milestone 2 site serves the sample tree from the emulators to a signed-in member, and refuses anyone who is not a member.

## Milestone 4: editing

- A TypeScript editor for a page: raw markdown with a live preview. A formatted editor can replace it later.
- Saving writes a revision and a change-log entry; the page updates at once.
- A save is refused if the page changed underneath, and the editor is shown the other change.
- Page history: list revisions, compare any two, restore an earlier one.
- Recent changes across the tree.
- "Add a memory" appends a dated entry without touching the rest of the page.

Done when: an edit made under one account appears at once, shows in the page history with its author and summary, and can be restored by another editor.

## Milestone 5: deploy and backup

- The server in a container on Cloud Run, behind Firebase Hosting, with real Google sign-in.
- Invite members by email address.
- A nightly export of the tree, in the file layout, to a private GitHub repository: one commit per logged change, with its author.
- Firestore's scheduled backups switched on.

Done when: invited relatives can sign in at a real address and edit, and the exported repository, loaded by the server in file mode, renders the same site.

## Milestone 6: photos in the app

- Upload a front, an optional back and the related text, from the browser straight to Cloud Storage. The server stores JPEGs and HEICs as they are, encodes uncompressed scans to JPEG, names the pair, and writes the metadata into each file.
- Verify the XMP and IPTC field names in [media.md](media.md) against the specifications, and define Loom's own fields for photo id and side.
- Choose the JPEG quality for scans using a real full-resolution scanner output.
- Front and back shown together wherever the photo appears.
- Rolls: create one, add photos in order, and suggest a frame's date or place to the rest.
- Tag the people in a photo; the names are written into the file.

Done when: a photo added through the app shows on the right people's pages with its back, and both files downloaded from storage still carry their names, date, transcription and pairing.

## Milestone 7: GEDCOM import

The spike in [spikes/gedcom_import](../spikes/gedcom_import/README.md) already converts a real GEDCOM 5.5.1 export into the file layout. This milestone makes it part of the app.

- Import from the browser: upload a GEDCOM file, preview what it will add, apply it as one logged change that can be undone as a whole.
- Read GEDCOM 7.0 as well as 5.5.1, and verify the tags listed in [content-model.md](content-model.md) against the specification.
- Re-import: match people already in the tree by their GEDCOM reference instead of duplicating them.
- GEDCOM export.

Done when: a real export imports through the app, a second import of the same file changes nothing, and the mapping table is confirmed or corrected.
