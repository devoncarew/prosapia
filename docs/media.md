# Photos and media

What is known about a photo is written into the photo file, using existing metadata
standards, so a copy emailed to a cousin still says who is in it. Prosapia keeps the
same facts in its database for searching, but the file is the authority.

The field names below were checked with exiftool 13.55 in milestone 6.

<!-- prettier-ignore -->
| What we know | Where it goes in the file |
| --- | --- |
| When it was taken, possibly only a year | XMP `photoshop:DateCreated`, which accepts a year or year and month. A date such as "about 1949" is written as its year; the words as typed are kept in Prosapia's record. A camera's EXIF `DateTimeOriginal` is left as it is |
| Who is in it | IPTC `Person Shown` (XMP `iptcExt:PersonInImage`), one entry per name |
| Where each person is in the frame | IPTC Image Regions, one named region per face |
| Text written on the back | XMP `dc:description`, transcribed as written, in both the front and the back file |
| Caption or title | XMP `dc:title` |
| Where it was taken | IPTC `Location Shown`, as its location name (XMP `iptcExt:LocationShown/LocationName`) |
| Who holds the original, who scanned it | XMP `dc:source` and `dc:rights` |
| Link back to Prosapia | The file's id in XMP `dc:identifier`: `prosapia:m-5t1q8z` for a front, `prosapia:m-5t1q8z-back` for its back, so the side needs no field of its own. Each person's id in IPTC `Person Shown with Details` (XMP `iptcExt:PersonInImageWDetails`) |
| The set it was added with | XMP `dc:relation`: `prosapia:set:s-4h8k2m#3`, the set and the photo's place in it |

## How a photo is stored

Direction set: every image is one ordinary file in a long-lived format, with its
information embedded. A front and a back are two files tied together by name and by
embedded id.

<!-- prettier-ignore -->
| What arrives | Stored as |
| --- | --- |
| A JPEG, from a camera, phone or scanner | That file as it is. The pixels are never re-compressed; Prosapia adds metadata beside what the camera wrote |
| An uncompressed scan, such as TIFF or PNG | A JPEG, encoded once at high quality. The uncompressed file is not kept |
| A HEIC, the default from iPhones | That file as it is |
| A PDF that only wraps one scanned JPEG | That JPEG, extracted unchanged. The PDF wrapper adds nothing, and photo tools read a JPEG better |
| A front and a back | Two files, each handled by the rules above |

JPEG is the archival format: it dates from 1992 and everything opens it. This is not
archival preservation of exact pixels; the aim is that no real quality is lost and the
memories are kept.

### Front and back

The two sides share an id and differ by a suffix:

```
media/
  m-5t1q8z.jpg        (front)
  m-5t1q8z-back.jpg   (back)
```

- **The file names pair them.** Anyone can see the pairing; no software is needed.
- **Each file embeds the photo id and its side**, so a renamed or separated file can be
  matched again.
- **The front carries the transcription of the back**, so the words survive even if the
  back is lost.
- **Prosapia keeps them together** when viewing, exporting and moving. The association
  is read from the names and the embedded ids, so the pairing can always be rebuilt from
  the files alone.

This replaces the earlier requirement that the two sides be physically one file. The
spike showed that every single-file option was either large, young, or lost the back
when re-saved, while embedded text survived everywhere.

### Sets

Settled in milestone 6: photos added together are a set, such as the photos of one trip,
one film or one album page. A set is not a record of its own and owns nothing.

- **Each file records its set and its place in it** in XMP `dc:relation`, as
  `prosapia:set:s-4h8k2m#3`, so the grouping and order survive outside Prosapia.
- **A date, place and people typed once apply to the whole set** when the photos are
  added, and can then be changed for any one photo.
- **A photo's page shows the others in its set**, in order.

This replaces rolls, which were to be small records of their own. A set does the same
work without anything to create or manage.

### Who a photo belongs to

No one: a photo belongs to the tree. It names the people in it, and shows on each of
their pages; a page can also show it as the main photo or place it in the story. Adding
a photo from someone's page only tags them to start with.

### Where the files live

Photos and other large files are stored in Cloud Storage, as they are, with their
metadata embedded. The browser uploads each file to the server, which applies the rules
above, writes the metadata into the file and stores it. Files over Cloud Run's 32 MB
request limit will need a signed upload straight to storage; see the plan. The database
keeps a small record per file so photos can be searched and listed without opening them.

The nightly export copies photos into the exported repository under `media/`, using the
names above. Very large files, such as video, are listed there but not copied.

### Video

Proposed: Prosapia stores short clips and links to long videos.

- **A short clip is stored like a photo**, up to a size limit. The working limit is 50
  MB, roughly a minute of phone video.
- **A longer video is a link** to wherever it is hosted, such as YouTube or a shared
  drive, with a title, a date and the people in it recorded in Prosapia.
- **Common video formats cannot carry embedded text reliably**, so for video the
  database record is the authority, not the file.

The sample tree's one video is 259 MB and was skipped on load under this rule. Open: the
exact limit, and whether Prosapia should offer to make a short excerpt of a long video.

### Display copies

Display copies are never stored as originals. The server makes them on demand when
serving a page: resized versions, and a JPEG version of each HEIC, since most browsers
do not display HEIC. They are cached, and the cache can be deleted at any time.

## Other decisions

- **Embedded metadata is canonical for facts about the image.** The page that uses the
  photo holds the story around it.
- **Names are written as text and as ids.** Text survives outside Prosapia; ids let
  Prosapia link a face to a person page.
- **Prosapia writes metadata on save and reads it on import.** A photo tagged elsewhere
  arrives with its people already named.
- **Metadata edits never re-encode the image.** They rewrite the metadata block only.

## What the spike showed

The image-format spike packaged one photo, a 1949 snapshot with a written back, sixteen
ways. The script and full measurements are in
[spikes/image_format](../spikes/image_format/README.md).

- **The text survived everywhere.** Metadata written by `exiftool` read back correctly
  from every image format, stayed findable as plain text in the raw bytes, and survived
  every re-save that could be tested.
- **Re-compressing a JPEG costs size or quality, usually both.** Multi-page TIFF came
  out at 1.5 to 4.7 times the input and HEIC at 1.1 to 1.7 times. Only AVIF and WebP
  came out smaller, and they are the youngest formats.
- **Single-file packaging is fragile.** Of the formats that hold two images, only TIFF
  kept the back through a re-save by macOS. HEIC, AVIF and a JPEG with the back appended
  all came back as the front alone.
- **JPEG XL has no page concept**, so it cannot hold a front and back as one file.

## Still to check

- [ ] The JPEG quality setting for uncompressed scans, tested on a real scanner output
      at full resolution.
- [ ] Whether embedded text survives email, a photo service (upload then download) and
      messaging apps.
- [ ] Which HEIC metadata fields common tools read and keep.

## Open

- Do documents (letters, certificates, census pages) follow the same rules as photos?
  The sample import brought in 13 PDFs alongside 122 JPEGs. Metadata could be written
  into the PDFs too.
- Size. The 122 sample JPEGs total 244 MB, about 2 MB each. That is no problem for Cloud
  Storage, but it may be too much to copy into the GitHub export in full.
- Audio recordings of relatives: in scope, and with what metadata?
- Should face regions be suggested automatically, and if so, does that run locally only?
