# Items for records

A record found becomes an item: its details, and its file when there is one (the image
of the record, a PDF, a photo of a stone). An item with no file, such as an index entry
or a web page, is known by its details alone. These are the fields the website asks for
when an item is added.

| Field         | What goes in it                                                                                                                                                 |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Title         | What the record is, specific enough to tell it from others: "1901 Irish census, Carew household, Kilkenny"                                                      |
| Date          | The date of the event or record, as written: "31 March 1901"                                                                                                    |
| Place         | Where, smallest to largest: "Patrick Street, Kilkenny, Ireland"                                                                                                 |
| People        | The people in the tree it names, by page                                                                                                                        |
| Transcription | What the record says, as written, including spellings that look wrong. For a long record, the relevant entry                                                    |
| Notes         | Where the original is held and how to find it again: the collection, volume, page, line, certificate number; who found it; anything uncertain about the reading |
| Link          | The record's address: a FamilySearch ARK, an Ancestry record link, a newspaper page                                                                             |
| Found         | The date it was found, and the site: "17 November 2026, FamilySearch"                                                                                           |

## By kind of record

**Census entry.**

- Title: "<year> <country> census, <head of household> household, <place>".
- Transcription: each member of the household as listed: name, relationship, age, sex,
  occupation, birthplace, and other columns that matter.
- Notes: the enumeration district or townland, sheet or page, and line or household
  number.

**Birth, marriage or death registration.**

- Title: "Birth of <name>, <date>, <place>" (or Marriage, Death).
- Transcription: every field of the entry, including the informant and witnesses.
- Notes: the register (civil or parish), the district, volume and page, or certificate
  number; whether this is the original image, a certified copy, or only an index.

**Baptism or burial in a parish register.** As for a registration; Notes give the
parish, the denomination, the register's dates and the page. Note when the entry is in
Latin, and give the translation as well as the text.

**Gravestone or cemetery record.**

- Title: "Grave of <name>, <cemetery>, <place>".
- Transcription: the inscription, line by line as carved.
- Notes: the section and plot if known; the Find a Grave memorial number, and who took
  the photo.

**Newspaper item.**

- Title: "<Kind: obituary, death notice, wedding> of <name>, <newspaper>, <date>".
- Transcription: the item, or the paragraph about the person.
- Notes: the newspaper, its town, the date, page and column.

**Passenger list or naturalization.**

- Title: "<Name> arrives at <port> on the <ship>, <date>" or "Naturalization of <name>,
  <court>, <date>".
- Transcription: the line for the person, with every column (age, last residence,
  relative left behind, destination, relative joined).
- Notes: the list's or court's archive reference, page and line.

**Military record.**

- Title: "<Record: draft card, service record> of <name>, <war or year>".
- Transcription: every field of the card or entry.

**Index entry only** (no image seen): say so in the Title ("Index of …") and the Notes,
and add the search for the original to the brief. An index is a lead to the record.

## Citing an item from the page

Once the item exists, cite it by its `#` id. A fact names it with `source:`:

```
Born: 12 March 1882, Kilkenny, Ireland, source: #m-xxxxxx
Died: 4 June 1941, Scranton, Pennsylvania, source: #m-yyyyyy
Note: Not found in the 1901 Irish census, searched by name and county, 2026
```

The story cites with a mark: `He sailed for New York in 1903 [source: #m-zzzzzz].`

When records disagree, keep both, each with its source:

```
Born: 12 March 1882, Kilkenny, Ireland, source: #m-xxxxxx
Born: about 1884, Ireland, source: #m-yyyyyy
```

An id in another system is a fact of its own: `FamilySearch: LZ5X-QRT`,
`WikiTree: Carew-123`, `Find a Grave: 12345678`.
