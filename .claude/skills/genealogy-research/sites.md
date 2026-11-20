# Sites

Two kinds: sites you may search yourself, with `curl` or a web fetch, and sites only a
person may search, for which you write the search into the task's log. The line between
them is each site's terms of use, not what is technically possible. When a site is not
listed here, ask the owner before fetching anything from it.

The search links below have been worked out from each site's own search pages and may
drift. When the owner says a link opened the wrong search, correct it here.

## Sites you may search

Search these with `dart run prosapia:research lookup` and read a hit with `text` (see
SKILL.md), which keep requests a second apart. Log each query.

**Library of Congress newspapers (Chronicling America).** US newspapers, about 1770 to
1963, full text. `lookup newspapers <words> --years <from>-<to> --place <state>`.

- Each hit gives the page as an item (paper, date, page, place, link), the passage
  around the words, and an image of the page at half size. The passage is OCR and has
  errors; check it names the right person before treating it as a lead.
- Words are not an exact phrase: `michael carew` also finds pages with a Michael and a
  Carew far apart. Read a hit with `text <link> carew --context 20`, which prints the
  lines around each match, to see what it is about (a heading may be 20 or more lines
  above).
- Coverage is thin for the Bronx and for New York after 1922, so a later death notice
  usually goes to a person (the Brooklyn Daily Eagle is free through the Brooklyn Public
  Library; others are on Newspapers.com).
- A finding is an item with no file, or with the page image: the `item` from `lookup`,
  with `people` and a `transcription` of the relevant paragraph added.

**Internet Archive.** County histories, city directories, yearbooks, church histories.
`lookup books <query> --years <from>-<to>`, where the query may use fields:
`title:(directory) AND title:(bronx)`.

- City directories come in parts (`p1`, `p2`), shown after the title; a family's letter
  may be in any of them. `text https://archive.org/details/<id> <surname> <given>`
  searches a book's whole text (kept in the cache once fetched). Directory lines are
  abbreviated (`carp` carpenter, `h` home, `av` avenue) and OCR may split a line.
- Reclaim the Records' free indexes are here (`collection:reclaimtherecords`). Its New
  York City marriage indexes start in 1908.

**HathiTrust.** Digitized books, many the same as the Internet Archive's, with better
full-text search. It refuses automated requests, so it is a search for a person:
`https://babel.hathitrust.org/cgi/ls?q1=<words>&anyall1=phrase&lmt=ft`. Only
public-domain books (`lmt=ft`) can be read in full. The search needs no sign-in; a
member can also download whole books. (This is the public search, not the HathiTrust
Research Center, whose access is ending in 2026.)

**WikiTree.** A shared tree, for spot checks only: a profile is a lead to the records it
cites, not a source. `lookup wikitree <given> <family> --born <year>` lists profiles
with that family name, with `--born` to narrow loosely by birth year.

- When a profile is the same person, propose `WikiTree ID: <id>` as a fact, and follow
  its sources. To read one:
  `https://api.wikitree.com/api.php?appId=prosapia&action=getProfile&key=<WikiTree-ID>&fields=Name,FirstName,LastNameAtBirth,BirthDate,BirthLocation,DeathDate,DeathLocation,Father,Mother&bioFormat=text`.
  Without `appId` every request is refused with "Limit exceeded".

**Free national indexes.** Free and public, but with search pages rather than APIs:
fetch a results page only when the site's terms allow it, and otherwise write the search
for a person.

- irishgenealogy.ie (Irish civil and some church records), the National Archives of
  Ireland's 1901 and 1911 census, FreeBMD and FreeCEN (England and Wales).

## Sites a person searches

These forbid automated access, or need a person signed in. Never fetch them, even a
single page. Write the search into the task's log for a person, with a link that opens
it with the fields filled in.

**FamilySearch** (free, sign-in needed). The most useful site for this family: records
from around the world, many with images, and a shared tree.

- Record search:
  `https://www.familysearch.org/search/record/results?q.givenName=<first>&q.surname=<last>&q.birthLikeDate.from=<yyyy>&q.birthLikeDate.to=<yyyy>&q.birthLikePlace=<place>`.
  Also `q.deathLikeDate.from`, `q.deathLikePlace`, `q.spouseGivenName`,
  `q.spouseSurname`, `q.fatherGivenName`, `q.motherGivenName`.
- One collection only: add `&f.collectionId=<id>`, from the collection's page in the
  FamilySearch catalog, when you know it.
- Full-text search of unindexed documents (deeds, wills, court records):
  `https://www.familysearch.org/search/full-text/results?q.text=<words>`.
- Tree: `https://www.familysearch.org/tree/person/details/<FamilySearch-ID>`. Ask the
  person to note the id when they find the person in the tree, and to follow the sources
  attached there.
- Ask for: the record's link (the ARK, `https://www.familysearch.org/ark:/61903/…`), the
  image where there is one, and the indexed details copied as text.

**Ancestry** (paid; optional). Strongest for US and UK census, immigration, military
records and newspapers (Newspapers.com). Propose a search here when it is the best place
for a record, but head it "(account needed)" and put the free searches first: the owner
may not have an account. Unrun, it moves to `open.md` when the task closes.

- Search:
  `https://www.ancestry.com/search/?name=<first>_<last>&birth=<yyyy>&birth_x=2-0-0`
  (`birth_x=2-0-0` allows two years either way); add `&death=<yyyy>`. Places are easiest
  typed in by the person.
- One collection:
  `https://www.ancestry.com/search/collections/<collection-id>/?name=<first>_<last>`.
- Ask for: the record image, downloaded; the record's details copied as text; the
  collection's name and the record's link. Member trees are leads, never sources.

**Find a Grave** (free; owned by Ancestry).

- Search:
  `https://www.findagrave.com/memorial/search?firstname=<first>&lastname=<last>&birthyear=<yyyy>&deathyear=<yyyy>`.
- Ask for: the memorial's number and link, a photo of the stone if there is one, and the
  inscription as text. Propose `Find a Grave ID: <number>` as a fact. The memorial's
  biography and family links are someone's work, not a record: only the stone is
  evidence.

**MyHeritage** (paid; optional, as Ancestry). Strong for Europe and Scandinavia. Write
the name, dates and place for the person to enter; its search links are not reliable to
build.

**Newspapers.com, GenealogyBank, Findmypast, Fold3** (paid): the same as Ancestry.
Suggest them only when the owner has an account.
