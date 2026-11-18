# Sites

Two kinds: sites you may search yourself, with `curl` or a web fetch, and sites only a
person may search, for which you write a brief. The line between them is each site's
terms of use, not what is technically possible. When a site is not listed here, ask the
owner before fetching anything from it.

The search links below have been worked out from each site's own search pages and may
drift. When the owner says a link opened the wrong search, correct it here.

## Sites you may search

Fetch a few results at a time, a second or more apart, and log each query.

**Library of Congress newspapers (Chronicling America).** US newspapers, about 1770 to
1963, full text.

- API:
  `https://www.loc.gov/collections/chronicling-america/?q=<words>&dates=<yyyy>/<yyyy>&fo=json`.
  Add `&fa=location_state:<state>` to narrow by state, such as
  `location_state:new+york`. Results give a title, a date, a link to the page, and its
  text.
- Quotes do not force an exact phrase: `"m. f. carew"` matched 638 pages, most of them
  unrelated. Check each hit's text before treating it as a lead. The text is OCR and has
  errors.
- To read a hit, fetch its page with `fo=json`; `resource.fulltext_file` is the page's
  text. Search that text for the name rather than reading the whole page.
- Coverage is thin for the Bronx and for New York after 1922, so a later death notice
  usually goes in the brief (the Brooklyn Daily Eagle is free through the Brooklyn
  Public Library; others are on Newspapers.com).
- A finding is an item with no file: the newspaper, date, page and the link, with a
  transcription of the relevant paragraph.

**Internet Archive.** County histories, city directories, yearbooks, church histories.

- API:
  `https://archive.org/advancedsearch.php?q=<query>&fl[]=identifier&fl[]=title&fl[]=date&rows=20&output=json`.
  Narrow with `mediatype:texts`, and terms such as
  `title:(directory) AND title:(scranton)`.
- Reclaim the Records' free indexes are here (`collection:reclaimtherecords`). Its New
  York City marriage indexes start in 1908.
- A book's full text is at
  `https://archive.org/stream/<identifier>/<identifier>_djvu.txt`; search it for the
  name rather than reading it whole.

**HathiTrust.** Digitized books, many of them the same as the Internet Archive's, with
better full-text search.

- Full-text search:
  `https://babel.hathitrust.org/cgi/ls?q1=<words>&anyall1=phrase&lmt=ft`. Only
  public-domain books (`lmt=ft`) can be read in full.
- It refuses most automated requests (403). When it does, put the search in the brief
  rather than retrying.

**WikiTree.** A shared tree, for spot checks only: a profile is a lead to the records it
cites, not a source.

- API:
  `https://api.wikitree.com/api.php?appId=prosapia&action=searchPerson&FirstName=<first>&LastName=<last>&BirthDate=<yyyy-mm-dd>`
  to find a profile (with only the year known, use `<yyyy>-01-01`; results are loose, so
  check each name), and
  `appId=prosapia&action=getProfile&key=<WikiTree-ID>&fields=Name,FirstName,LastNameAtBirth,BirthDate,BirthLocation,DeathDate,DeathLocation,Father,Mother&bioFormat=text`
  to read one. Public profiles need no sign-in. Without `appId` every request is refused
  with "Limit exceeded".
- When a profile is the same person, propose `WikiTree: <id>` as a fact, and follow its
  sources.

**Free national indexes.** Free and public, but with search pages rather than APIs:
fetch a results page only when the site's terms allow it, and otherwise put the search
in the brief.

- irishgenealogy.ie (Irish civil and some church records), the National Archives of
  Ireland's 1901 and 1911 census, FreeBMD and FreeCEN (England and Wales).

## Sites a person searches

These forbid automated access, or need a person signed in. Never fetch them, even a
single page. Write the search into the brief and the queue, with a link that opens it
with the fields filled in.

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

**Ancestry** (paid; searched in batches during a subscription). Strongest for US and UK
census, immigration, military records and newspapers (Newspapers.com).

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
  inscription as text. Propose `Find a Grave: <number>` as a fact. The memorial's
  biography and family links are someone's work, not a record: only the stone is
  evidence.

**MyHeritage** (paid; only if there is a subscription). Strong for Europe and
Scandinavia. Write the name, dates and place for the person to enter; its search links
are not reliable to build.

**Newspapers.com, GenealogyBank, Findmypast, Fold3** (paid): the same as Ancestry.
Mention them in a brief only when the owner has an account.
