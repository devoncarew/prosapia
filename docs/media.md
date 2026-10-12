# Photos and media

What is known about a photo is written into the photo file, using existing metadata standards, so a copy emailed to a cousin still says who is in it. The repository keeps the same facts in its index, but the file is the authority.

The field names below are from memory and should be checked against the current specifications during the image-format spike.

| What we know | Where it goes in the file |
| --- | --- |
| When it was taken, possibly only a year | XMP `photoshop:DateCreated`, which accepts a year or year and month; EXIF `DateTimeOriginal` only when the full date is known |
| Who is in it | IPTC `Person Shown`, one entry per name |
| Where each person is in the frame | IPTC Image Regions, one named region per face |
| Text written on the back | XMP `dc:description`, transcribed as written |
| Caption or title | XMP `dc:title` |
| Where it was taken | IPTC `Location Shown` |
| Who holds the original, who scanned it | XMP `dc:source` and `dc:rights` |
| Link back to Loom | A custom XMP namespace holding the media id and person ids |

## Decided by the brief

- Information should be hard to separate from the photo.
- A scan of the front and the back belongs together as one item.

## Proposed

- **Embedded metadata is canonical for facts about the image.** The page that uses the photo holds the story around it.
- **Names are written as text and as ids.** Text survives outside Loom; ids let Loom link a face to a person page.
- **Loom writes metadata on save and reads it on import.** A photo tagged elsewhere arrives with its people already named.
- **Metadata edits never re-encode the image.** They rewrite the metadata block only.

## Open: how a photo is stored

A format is proposed in [Spike results](#spike-results) below, from the image-format spike (milestone 1 in the [plan](plan.md)). Any choice must meet three requirements:

1. **Preserve the original data.** No real quality is lost: the photo keeps its intent and the memories it holds. This is not archival preservation, so exact pixels need not be recoverable. No text is lost.
2. **Readable in 20 or more years.** An open, widely implemented format that software will still open without Loom.
3. **Packaged together.** The front, the back and the information about them are hard to separate by accident.

Two kinds of input are expected. Recent photos arrive as JPEGs, already compressed. Older photos arrive as scans, and Loom's choice of format can guide how people scan them.

These pull against each other. The oldest and safest formats are large or single-image; the formats that compress well and hold several images are young. An earlier working assumption, lossy storage in a TIFF container, is now only one candidate.

| Candidate | For | Against |
| --- | --- | --- |
| JPEG with the back appended (Multi-Picture Format) | A plain JPEG to every viewer; a JPEG input is kept untouched; the mechanism phones use for a second image | Viewers show only the front; a re-save drops the back |
| Multi-page TIFF, lossless or JPEG-compressed | Decades old; archives use it; carries XMP; two pages in one file | Browsers do not display it; many viewers show page one only; large when lossless |
| HEIF collection (HEIC) | One file, several images; the front as primary item is what single-image viewers show | HEVC carries patent terms; viewers show only the primary item; no standard marker for "back of"; uneven tool support |
| AVIF (HEIF container, AV1 codec) | Royalty-free; displays in all major browsers; can hold several images | Young; browsers show only the primary item; multi-image tool support is thin |
| JPEG XL | Lossless and lossy; can repack an existing JPEG and restore the original file exactly; an ISO standard | Young; browser and viewer support is uneven; multi-image handling to be checked |
| WebP | Displays everywhere; small | One image per file, so needs side-by-side or two files; lossy mode caps quality |
| Two-page PDF | Opens everywhere, both sides visible; an archival profile exists | Treated as a document, not a photo; photo tools ignore it |
| One image, front and back side by side | Works in every viewer and cannot be split | The photo is no longer a clean image; cropping is needed for display |
| Zip bundle: the original files plus a metadata file | Keeps the original bytes untouched; zip is decades old | Not an image; nothing previews it; metadata is beside the images, not in them |
| Two files plus embedded cross-references | Simple; each side is a normal image | The two can still be separated, which is the problem to solve |

Whatever is stored, the server generates display copies in a web format, so the stored format does not need to display in a browser.

## Spike results

The image-format spike packaged one photo sixteen ways: a 1949 snapshot supplied as two JPEGs (front and back, 214 kB together) plus the text from its back. The script and full measurements are in [spikes/image_format](../spikes/image_format/README.md).

| Candidate | One file | Size vs input | Pixels | Back survives a metadata edit | Back survives a macOS re-save | Displays in browsers |
| --- | --- | --- | --- | --- | --- | --- |
| JPEG with the back appended (MPF) | Yes | 103% | Unchanged | Yes | No | Yes, the front |
| Two-page PDF, JPEGs embedded | Yes | 102% | Unchanged | Yes | Not tested | As a document |
| Zip bundle | Yes | 104% | Unchanged | Yes | Does not open | No |
| Multi-page TIFF, lossless | Yes | 472% | Unchanged | Yes | Yes | No |
| Multi-page TIFF, JPEG quality 90 / 75 | Yes | 265% / 156% | Re-compressed | Yes | Yes | No |
| HEIC collection, quality 90 / 75 | Yes | 168% / 111% | Re-compressed | Yes | No | Safari only |
| AVIF collection, quality 90 / 75 | Yes | 80% / 51% | Re-compressed | Yes | No | Yes, the front |
| Side by side: JPEG, WebP, AVIF, JPEG XL | Yes | 106%, 61%, 79%, 65% | Re-compressed | Yes | Yes | Yes, except JPEG XL |
| Two JPEG XL files, repacked | No | 84% | Original JPEG restorable exactly | Two files | Cannot save | Safari only |
| Two JPEGs (baseline) | No | 103% | Unchanged | Two files | Two files | Yes |

The browser column is from general knowledge, not tested here. "macOS re-save" used `sips`, the system converter that shares its image code with Preview.

### Findings

- **The text survived everywhere.** XMP written by `exiftool` read back correctly from every image format, stayed findable as plain text in the raw bytes, and survived every re-save that could be tested.
- **Re-compressing a JPEG costs size or quality, usually both.** TIFF and HEIC came out larger than the input. Only AVIF and WebP came out smaller, and they are the youngest formats.
- **Three candidates keep the input JPEGs untouched in one file:** the JPEG with the back appended, the PDF and the zip. Only the first is still a photo that every viewer opens.
- **No multi-image format keeps the back through a re-save, except TIFF.** HEIC, AVIF and the appended JPEG all came back as the front alone. The text was kept in each case.
- **JPEG XL has no page concept**, only animation frames, so a front and back stay two files. Its exact JPEG repacking works and saves 16%.
- **The appended-JPEG index must come after the metadata.** Placed before it, a later `exiftool` edit silently broke the pointer to the back. Placed last, the back survived edits.

### Proposed decision

Store each photo as a JPEG with the back appended: the front is an ordinary JPEG, and the back is a second JPEG added after it and indexed by a Multi-Picture Format segment. This is the mechanism current phone cameras use to attach a second image to a JPEG.

- **Preserve the original data:** a JPEG input is kept as it is, with no second compression. A scan is encoded to JPEG once, at high quality.
- **Readable in 20+ years:** it is a JPEG. Every viewer, browser and GitHub show the front with no extra software, so display copies are needed only for resizing.
- **Packaged together:** one file holds the front, the back and the text. The text is written into both images, so even a back that is extracted on its own says what it is.

The known weakness: ordinary viewers show only the front, and an editor that re-saves the file drops the back. The transcription of the back survives in the text. Multi-page TIFF is the alternative if showing both sides in ordinary viewers matters more than size, browser display and leaving JPEGs untouched.

### Still to check

- [ ] A real scanner output at full resolution. The test input was a small JPEG, so the scan path and the JPEG quality for scans are untested.
- [ ] Round trips by hand: email, a photo service (upload then download), and messaging apps. Check whether the back and the text come back.
- [ ] Opening the file on Windows, iOS and Android.
- [ ] A second reader for the appended back. So far only `exiftool` has extracted it.

## Also open

- Do documents (letters, certificates, census pages) follow the same rules as photos?
- Audio and video recordings of relatives: in scope, and with what metadata?
- Should face regions be suggested automatically, and if so, does that run locally only?
