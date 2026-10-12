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

The format is undecided and is settled by the image-format spike, milestone 1 in the [plan](plan.md). Any choice must meet three requirements:

1. **Preserve the original data.** No real quality is lost: the photo keeps its intent and the memories it holds. This is not archival preservation, so exact pixels need not be recoverable. No text is lost.
2. **Readable in 20 or more years.** An open, widely implemented format that software will still open without Loom.
3. **Packaged together.** The front, the back and the information about them are hard to separate by accident.

Two kinds of input are expected. Recent photos arrive as JPEGs, already compressed. Older photos arrive as scans, and Loom's choice of format can guide how people scan them.

These pull against each other. The oldest and safest formats are large or single-image; the formats that compress well and hold several images are young. An earlier working assumption, lossy storage in a TIFF container, is now only one candidate.

| Candidate | For | Against |
| --- | --- | --- |
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

## Also open

- Do documents (letters, certificates, census pages) follow the same rules as photos?
- Audio and video recordings of relatives: in scope, and with what metadata?
- Should face regions be suggested automatically, and if so, does that run locally only?
