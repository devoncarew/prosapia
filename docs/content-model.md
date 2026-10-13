# Content model, sources and interchange

## Content model

Direction set: each person is one page: in the database a document, in the exported
files one markdown file in a directory of its own, with a small block of structured
facts on top and free-form prose below. The structured block holds only what tools must
compute with. Everything else is prose a relative can write.

```markdown
---
id: p-7k2m9x
name: Margaret Ellen Hughes
born: { date: 1887-03-14, place: "Scranton, Pennsylvania", source: s-1900-census }
died: { date: ABT 1961 }
parents: [p-3f8d1a, p-9c4e2b]
---

Margaret grew up above her father's hardware store...

## 1923: Trip to Wales

She sailed from New York in June with her cousin [Owen Price](../price-owen-4h8w2r/index.md) to visit her mother's family. [^s-ship-manifest]

![On the dock at Liverpool](../../media/m-5t1q8z.jpg)
```

### Decided by the brief

- Pages are text with light formatting and images, conceptually markdown.
- An edit may simply add to a person's record: a dated entry with a description and
  photos. It does not have to update structured fields.
- Folding such entries into timelines or summaries is the job of the viewing layer, not
  the contributor.

### Proposed

- **Stable opaque ids** (`p-7k2m9x`) name people, sources and media. Names change and
  collide; ids do not. Each person gets a directory of their own, so notes, transcripts
  or split-out entries can sit beside the page later.
- **A person's directory is a readable name ending in the id**:
  `people/hughes-margaret-ellen-7k2m9x/index.md`, surname first so a listing groups
  families. Only the trailing id identifies the person. The readable part is set when
  the person is created and is never renamed automatically; if a name is later
  corrected, the old directory name still works, and a tidy-up rename is an ordinary
  edit. Structured references use the bare id (`parents: [p-3f8d1a]`) and never break.
- **Ids from other systems are extra links, not Loom's ids.** A person may record a
  FamilySearch or WikiTree id, which identify one person in a shared tree, to link
  outward and to match people on re-import. Ancestry ids identify a row in one member's
  tree, so they are weaker. Most people in a family tree are in none of these systems.
- **Entries are sections** in the person's page: a heading with an optional date, then
  prose and images. The date-in-heading convention is all a timeline generator needs.
- **Relationships are stored once.** A child lists its parents; a partnership is its own
  small record. Siblings, children and descendants are derived. This avoids two files
  that must be edited in step.
- **Uncertain dates use the GEDCOM 7.0 date grammar** (`ABT 1961`, `BET 1880 AND 1885`),
  so import and export need no translation.
- **Places are free text** in the first version, as written in the source.
- **Links between people are relative markdown links**
  (`[Owen Price](../price-owen-4h8w2r/index.md)`), not bare ids or wiki syntax. They
  work when the exported files are read on GitHub, and Loom resolves them to the
  person's current name.
- **The file reads well raw; Loom renders on top.** GitHub's own markdown view of the
  exported files is a plain fallback reader. The Loom server adds the infobox from the
  structured facts, citation markers and derived views. It does not reorder the page
  body: the authored order stands, and chronological ordering lives in the separate
  timeline view. One gap: GitHub does not display HEIC images inline, so those show
  there as links.

### Open

- Do events shared by several people (a wedding, a reunion) get their own page, or live
  on one person's page and get linked from the others?
- Are places first-class records with coordinates and historical names, or do they stay
  text?
- Does a couple or household get its own page, as Wikipedia would give a notable family?
- How are conflicting claims shown, for example two sources with different birth years?

### What the sample import showed

A real export was converted into this layout by the script in
[spikes/gedcom_import](../spikes/gedcom_import/README.md): 203 people, 58 partnerships
and 136 media files, from Family Tree Maker's GEDCOM 5.5.1.

- **Most pages are nearly empty.** 132 of 203 people have no birth event and 37 have
  nothing but a name. Pages and views must read well with almost no data.
- **People have facts beyond birth and death**: occupations, education, residences,
  burials, titles. Proposed: a `facts` list in the structured block, each with a type, a
  value, a date and a place. Whether these belong there or in the prose is open.
- **A person can have more than two parents.** One child is listed with both adoptive
  and birth parents. Proposed: an entry in `parents` may carry a `relationship`, such as
  `adopted`.
- **Other names are common.** Nicknames arrive as extra names. Proposed: an
  `also_known_as` list.
- **Exact dates are written as ISO** (`1950-05-17`, `1987-11`, `1972`). Qualified dates
  and ranges stay in GEDCOM's grammar. One real value, `BET FEB AND JUL 1934`, is not
  valid GEDCOM and is kept as written.
- **There are no sources** in this export, so citations are untested.
- **Each record keeps its GEDCOM reference** (`gedcom_id`) so a later re-import can
  match it.
- **Opaque ids made the files hard to browse by hand**, which led to readable directory
  names ending in the id.

### Open: merging an update into the biography

A typical update is a short story from a relative: a trip the person took, when it
happened, who went, and a few photos. The writer rarely knows where it belongs in a long
biography and should not have to decide.

<!-- prettier-ignore -->
| Option | How it works | For | Against |
| --- | --- | --- | --- |
| Separate entry | Appended as its own dated section, exactly as written | Lossless; no judgment needed; easy to review | A long page becomes a pile of fragments that never reads as one story |
| Model places it when saved | A language model picks where it goes and may adjust nearby text; that result is what gets saved | One step covers story and placement; the page stays coherent | Changes text the contributor did not write, with nobody checking the model's edits |
| Merged later | The update lands as an entry; a later process, a model or an editor, weaves entries into the biography | Saving stays simple; weaving can be batched and done with care | Two steps per story; pages look untidy between them |

Working assumption: the options combine rather than compete. Every update is first
stored as a dated entry, as written, so nothing is lost and the timeline view works at
once. Weaving entries into the biography is a later, separate edit, drafted by a model
or a person and saved by an editor under their own name. This follows the Derived views
rule that generated text is offered to an editor, never written directly. Once woven in,
the original entry can move to the person's directory (`entries/1923-trip-to-wales.md`)
rather than be deleted.

The trip also names a companion. Whether it appears on their page too is the
shared-events question above; the working answer is that the entry lives on one page,
links the others, and their pages list it under a derived "appears in" heading.

## Sources and citations

Proposed: a source is a first-class record, and any claim on a page can point at one. A
source record describes the evidence once; pages cite it by id.

```markdown
---
id: s-1900-census
title: 1900 United States Census, Lackawanna County, Pennsylvania
kind: census
repository: National Archives
url: https://example.org/record/123
accessed: 2026-10-12
media: [m-8h3v2k]
---

Sheet 4B, line 62. Lists Margaret, age 13, in the household of Thomas Hughes.
```

### Decided by the brief

- Edits should be able to cite the sources they used, including an image of the record
  itself.
- Gathering information from common research tools should be easy.

### Proposed

- **Two ways to cite.** A structured fact names its source in the fact
  (`source: s-1900-census`). Prose uses a markdown footnote (`[^s-1900-census]`).
- **The evidence image is ordinary media**, stored and tagged like any photo, and linked
  from the source record.
- **A source records where and when it was found**: the site, the URL and the access
  date. Online records move and vanish.
- **Uncited claims are allowed but visible.** Pages can show a "needs source" marker, as
  Wikipedia does, without blocking the edit.

### Getting data in from research tools

<!-- prettier-ignore -->
| Route | What it gives | Notes |
| --- | --- | --- |
| GEDCOM import | A whole tree exported from another tool | Works with any tool that exports GEDCOM; see the next section |
| Capture from the browser | One record: page URL, title, a saved image, a draft source record | Works on any site without that site's cooperation |
| Site APIs | Direct record lookup and linking | Depends on each site's terms and access programme; assume none at first |
| Manual entry with a template | A source record typed in from paper | Templates per kind: census, birth, marriage, death, newspaper, grave |

The sites to design against first are FamilySearch, Ancestry, MyHeritage, Find a Grave,
WikiTree and newspaper archives. Which of them permit automated access is unverified and
belongs in the research spike.

### Open

- How formal should citations be? Genealogists have detailed citation conventions; most
  relatives will paste a link.
- Does Loom record the reasoning behind a conclusion (why two records are the same
  person), or only the conclusion and its sources?
- Copyright and site terms for saved record images, especially once a page is shared
  widely.
- DNA matches as evidence: in scope or not?

## GEDCOM 7.0 interchange

GEDCOM 7.0 is the import and export format, not the storage format. Loom's pages hold
more prose than GEDCOM models well, so the mapping is deliberate and some loss is
accepted.

The tag names below are from memory of the 7.0 specification and should be confirmed
when the importer is built.

<!-- prettier-ignore -->
| Loom | GEDCOM 7.0 | Round-trips? |
| --- | --- | --- |
| Person and structured facts | `INDI` with `NAME`, `BIRT`, `DEAT` and other events | Yes |
| Parents and partnerships | `FAM` with `HUSB`, `WIFE`, `CHIL` | Yes; Loom derives `FAM` records on export |
| Dates, including uncertain ones | Date values (`ABT`, `BET ... AND`, `BEF`, `AFT`) | Yes, same grammar |
| Source records and citations | `SOUR` records and `SOUR` citations on facts | Yes for structured facts |
| Media | `OBJE` with `FILE`; files bundled in a GEDZIP archive | Yes; embedded metadata rides inside the files |
| Visibility | `RESN` (confidential, private, locked) | Deferred with the sharing model |
| Loom ids and links to other systems | `EXID` external identifiers | Yes |
| Page prose and dated entries | `NOTE` text, or a documented extension tag | Lossy; formatting and inline images flatten |

### Decided by the brief

- GEDCOM 7.0 is the route in from existing data and out to other tools.

### Proposed

- **Import is previewed before it is applied**, and lands as one logged change that can
  be undone as a whole.
- **Import keeps the original file** as a source, so every imported fact can cite where
  it came from.
- **Unknown tags are preserved**, not dropped, so a round trip through Loom does not
  destroy another tool's data.

### Open

- **Older files.** Settled in principle: Loom must read GEDCOM 5.5.1. The first real
  input, a 2024 export from Family Tree Maker, is 5.5.1 and uses that tool's own
  extension tags. How far to support 5.5 and other tools' extensions is open.
- **Re-import and merge.** Importing a newer export of the same tree must match people
  already present, not duplicate them. Matching rules are undefined.
- **How much prose to push out.** Whole pages as notes, a summary only, or a link back
  to Loom.
