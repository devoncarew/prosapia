# Plan

Six milestones settle the open decisions and end with a working edit loop. Milestones 0 and 1 need no product code and can run in parallel; the rest build on each other.

| # | Milestone | Settles | Depends on |
| --- | --- | --- | --- |
| 0 | Sample tree | The content model and directory layout | Nothing |
| 1 | Image-format spike | How a photo is stored | Nothing |
| 2 | Read-only server | Dart for rendering, the index, display copies | 0 |
| 3 | Edit loop | Dart with GitHub; minimal diffs; the TypeScript editor | 2 |
| 4 | GEDCOM import | The GEDCOM mapping; older-version support | 0, 3 |
| 5 | Photos in the app | Upload, packaging and tagging | 1, 3 |

Not planned yet: the sharing model, weaving entries into biographies, research capture and generated summaries.

## Milestone 0: sample tree

Hand-write a small real tree as files, with no code, to find where the content model does not fit.

- Create a private GitHub repository in the layout from [architecture.md](architecture.md).
- Write ten real people across three generations, their partnerships, and three or four sources.
- Add a few loose updates, like the trip example, as dated entries.
- Read the result on GitHub's own markdown view.

Done when: the tree exists, and [content-model.md](content-model.md) is updated with whatever did not fit. This is the place to answer the open questions on shared events, places and conflicting claims, at least provisionally.

## Milestone 1: image-format spike

Package one real photo in every candidate format and measure each against the three requirements in [media.md](media.md): preserve the original data, readable in 20 or more years, packaged together.

### Input

One photograph, supplied by you:

- the front scan and the back scan, as they came from the scanner;
- the related text: who is in it, when and where it was taken, what is written on the back, a caption.

The first input is in `spikes/image_format/input/`: a JPEG front and back of a 1949 snapshot, with the text from its back. A second photo of a different kind (for example a small snapshot and a large studio portrait) would make the size results more trustworthy, but one is enough to start.

### Candidates

| # | Package | Encodings to try |
| --- | --- | --- |
| 1 | Multi-page TIFF | Lossless; JPEG-compressed at two quality levels |
| 2 | HEIF collection | HEIC (HEVC), lossy at two quality levels |
| 3 | AVIF, two images | Lossless; lossy at two quality levels |
| 4 | JPEG XL | Lossless; lossy at two quality levels; exact JPEG repacking if the input is JPEG |
| 5 | Two-page PDF | Original images embedded unchanged |
| 6 | One side-by-side image | JPEG, WebP, AVIF, JPEG XL |
| 7 | Zip bundle | Original files plus a metadata file |
| 8 | Two files with cross-references | Baseline for comparison: JPEG, WebP |

### What is measured

| Requirement | Test |
| --- | --- |
| Preserve the original data | Decode each package and compare with the input: a measured difference, checked by eye. The bar is no real quality loss, not identical pixels. Note where a JPEG input is re-compressed, since that loses quality a second time. Record file size |
| Preserve the original data | Write every text field into the package, read it back with a second tool, and compare |
| Packaged together | Does one file hold both sides and all the text? |
| Packaged together | Does the package survive being copied, emailed, uploaded to and downloaded from a photo service, and opened and re-saved in a common editor? Check that the back and the text are still there |
| Packaged together | After a metadata edit by a standard tool, is the second image still present? |
| Readable in 20+ years | Age of the format; whether the specification is open and free of patent fees; how many independent programs can read it; whether archives recommend it |
| Readable in 20+ years | What opens it today with no extra software: macOS, Windows, iOS, Android, the major browsers, GitHub. Record whether each shows both sides, the front only, or nothing |
| Practical | Can the server produce and read it with command-line tools called from Dart? |

### Output

- Scripts under `spikes/image_format/` that build every package from the inputs, so the comparison can be rerun on more photos.
- A results table in [media.md](media.md): one row per candidate, one column per test.
- A decision recorded in [media.md](media.md): the package, the encoding, whether storage is lossless, and the display-copy format.

Done when: the decision is recorded, or the table shows that no candidate meets all three requirements and names the trade-off to choose between.

Tools: this machine has ImageMagick, `heif-enc`, `cwebp` and `tiffcp`. The spike also needs `exiftool`, `libvips`, `cjxl` (JPEG XL) and `avifenc`, all available from Homebrew.

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

- Upload a front, a back and the related text; the server packages them in the format milestone 1 chose and writes the metadata into the file.
- Verify the XMP and IPTC field names in [media.md](media.md) against the specifications.
- A per-person photo gallery built from the names embedded in the files.
- Decide where image bytes live: in git, Git LFS, or a store beside the repository.

Done when: a photo added through the app shows on the right people's pages, and the file copied out of the repository still carries its names, date and transcription.
