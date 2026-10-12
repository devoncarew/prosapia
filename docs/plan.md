# Plan

Six milestones settle the open decisions and end with a working edit loop. Milestone 1 is done. Milestone 0 needs no product code; the rest build on each other.

| # | Milestone | Settles | Depends on |
| --- | --- | --- | --- |
| 0 | Sample tree | The content model and directory layout | Nothing |
| 1 | Image-format spike (done) | How a photo is stored | Nothing |
| 2 | Read-only server | Dart for rendering, the index, display copies | 0 |
| 3 | Edit loop | Dart with GitHub; minimal diffs; the TypeScript editor | 2 |
| 4 | GEDCOM import | The GEDCOM mapping; older-version support | 0, 3 |
| 5 | Photos in the app | Upload, pairing, tagging and rolls | 1, 3 |

Not planned yet: the sharing model, weaving entries into biographies, research capture and generated summaries.

## Milestone 0: sample tree

Hand-write a small real tree as files, with no code, to find where the content model does not fit.

- Create a private GitHub repository in the layout from [architecture.md](architecture.md).
- Write ten real people across three generations, their partnerships, and three or four sources.
- Add a few loose updates, like the trip example, as dated entries.
- Read the result on GitHub's own markdown view.

Done when: the tree exists, and [content-model.md](content-model.md) is updated with whatever did not fit. This is the place to answer the open questions on shared events, places and conflicting claims, at least provisionally.

## Milestone 1: image-format spike

Done. One photo was packaged sixteen ways with the script in [spikes/image_format](../spikes/image_format/README.md) and measured for size, quality, and whether the back and the text survived.

Outcome, recorded in [media.md](media.md): JPEGs and HEICs are stored as they are, uncompressed scans become JPEG, and a front and back are two files paired by name and embedded id rather than one combined file.

## Milestone 2: read-only server

A Dart server that reads a clone of the sample tree and serves it as a website.

- Person pages rendered from markdown, with an infobox from the structured facts, working links between people, and footnote citations.
- A SQLite index built from the clone: names, relationships, full-text search.
- One derived view beyond the page: a timeline from structured events and dated entry headings.
- Display copies of images, generated into a cache.

Done when: the sample tree can be browsed and searched locally, and deleting the index and cache then restarting rebuilds both.

## Milestone 3: edit loop

The full path from pressing Edit to a merged change, which is where the stack choice is most at risk.

- Sign in with GitHub.
- A TypeScript editor for a page: raw markdown with a live preview. A formatted editor can replace it later.
- Save creates a branch and a pull request as the signed-in person, with their summary as the title.
- A webhook on merge makes the server pull and rebuild the index.
- "Add a memory" appends a dated entry without touching the rest of the page.

Done when: changing one word in the editor produces a one-line diff in the pull request, and the merged change appears on the site without a manual step. If either GitHub integration or minimal diffs proves impractical in Dart, this is the point to switch the server to TypeScript.

## Milestone 4: GEDCOM import

- Verify the GEDCOM 7.0 tags listed in [content-model.md](content-model.md) against the specification.
- Import one real export from an existing genealogy tool, arriving as a single pull request.
- List what did not fit, and decide whether to read GEDCOM 5.5.1 directly.

Done when: an imported tree browses correctly on the milestone 2 server, and the mapping table is confirmed or corrected.

## Milestone 5: photos in the app

- Upload a front, an optional back and the related text. The server stores JPEGs and HEICs as they are, encodes uncompressed scans to JPEG, names the pair, and writes the metadata into each file.
- Verify the XMP and IPTC field names in [media.md](media.md) against the specifications, and define Loom's own fields for photo id and side.
- Choose the JPEG quality for scans using a real full-resolution scanner output.
- Front and back shown together wherever the photo appears.
- Rolls: create one, add photos in order, and suggest a frame's date or place to the rest.
- A per-person photo gallery built from the names embedded in the files.
- Decide where image bytes live: in git, Git LFS, or a store beside the repository.

Done when: a photo added through the app shows on the right people's pages with its back, and both files copied out of the repository still carry their names, date, transcription and pairing.
