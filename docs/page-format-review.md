# Page format review

Recommendations for [milestone 24](plan.md#milestone-24-page-format-decisions): each
open question about the page format, and a comparison with other genealogy models. Once
agreed, the decisions and their reasons move into [content-model.md](content-model.md)
and this document is deleted.

## How the recommendations are judged

Each one is weighed on three things:

- **Problems people actually hit**: in the Carew tree so far, and in family trees
  generally. A change has to fix one.
- **Editing**: the page stays plain text that a relative can read and change without
  training. New syntax has to look like syntax they already know.
- **Resilience**: real records are incomplete and contradict each other. A page with
  half the facts, or two that disagree, must still save, read and show.

GEDCOM 7 (2021) and GEDCOM X (FamilySearch's newer, JSON-based model) are the models
compared. Both carry long experience. GEDCOM also carries legacy: it was designed for
exchange between programs, not for people typing.

## Summary

<!-- prettier-ignore -->
| Question | Recommendation | Effort |
| --- | --- | --- |
| Fact order | Adopt a fixed order for the first lines, and notes last; Format applies it | Small |
| Citing sources | `[source: …]` in the story and `source:` in facts; the value is text, or a `#` reference to a source record or a document | Medium, with milestone 26 |
| `#` references | `#` refers to anything that is not a person: a source, a photo, a document | Small |
| Comments | Do not add them; blank fields and `Note:` cover the need | None |
| Blank fields on new pages | Adopt: `Sex:`, `Born:`, `Died:`, `Parents:`; empty facts are never problems | Small |
| Where relationships are written | Read every form; promote siblings to parents when known; flag disagreements | Small |
| Several values for one fact | Adopt GEDCOM's: repeat the line, first is preferred, others shown as "also recorded" | Small |
| Names | Keep whole names; add a rarely needed `Family name:` and a kind on `Also known as:`, in parentheses | Small |
| Places | Keep free text; document smallest-to-largest; places as records stay future work | None now |
| Other ids (FamilySearch, WikiTree) | Adopt: a fact per system, shown as a link | Small |
| Dates | Keep; also read `1861 or 1862` | Small |
| Sex | Format writes recognised spellings as male, female, intersex or unknown; anything else is kept | Small |
| Families, shared events, associations | Keep person-to-person lines; shared events stay future work | None now |

## Fact order

**Problem.** Pages are written in many orders, so the facts a reader looks for first
move around, and a `Note:` often ends up between relationships.

**Others.** GEDCOM has no required order; programs write their own.

**Recommendation.** Format puts the facts in this order, moving whole lines and never
changing what they say:

1. `Name`, `Nickname`, `Also known as`, `Family name`, `Sex`
2. `Born`, `Christened`, `Died`, `Buried`
3. `Parents`, `Siblings`
4. `Partner`, `Married`, `Divorced` and other couple events, in the order written
5. `Children`
6. `Photo`
7. Every other fact, in the order written
8. `Note` last

Sources and other ids (below) sit with the other facts. Lines with the same label, and
the couple lines, keep the order they were written in; nothing is sorted by date. The
value is that the first few lines are predictable and notes come last.

## Citing sources

**Problem.** Today a fact can carry `source: 1920 census`, but the story has no way to
cite, and the same source is retyped wherever it is used.

**Others.** GEDCOM has source records (title, author, publication, the repository that
holds it) and citations that point at them with the detail: page, entry, a quality
rating, a transcription, scans. GEDCOM X is the same idea. Genealogists cite in the
style of _Evidence Explained_; few family members do.

**Recommendation.** One form in both places, with three levels, so a family can start
simple and grow:

- **Text.** `source: 1920 census, Hartford` in a fact, `[source: 1920 census, Hartford]`
  in the story, the same mark as `[date: …]` and `[place: …]`. It shows as a small
  "source" mark, and the story's sources are listed at the end of the page.
- **A document.** Often the source is a document already in the tree, such as a
  certificate. It is cited directly with a `#` reference (below): `source: #m-gdcade`.
  Joseph Carew's page already names that certificate this way, as plain text.
- **A source record** (milestone 26), for a source with no scan, or one used in many
  places, such as a census: `source: #census-1920-hartford-k3m9qa`, followed by the
  detail of this citation: `[source: #census-1920-hartford-k3m9qa, sheet 4B, line 37]`.
  The source's page lists every citation of it, and names the photos and documents that
  show it.

A source record is a record of its own, not a kind of photo: many sources (a census, a
book, a conversation) have no image, and one source may have several scans. A document
that is its own source needs no record; it is cited directly.

Not recommended: markdown footnotes (`[^1]` with definitions at the end). They are
standard, but unfamiliar to most editors, and a page-local definition list adds a third
way to cite without solving anything source records do not. Not recommended for now:
GEDCOM's quality rating, which few people fill in consistently.

## `#` references

**Problem.** A photo or document can only be named where Prosapia expects one, as in
`Photo: m-qymrdd`. A story cannot link to a letter, and a fact cannot cite a document
except as text.

**Recommendation.** `#` refers to anything in the tree that is not a person, as GitHub
uses `#` for issues and pull requests and `@` for people: a source record, a photo or a
document. As with people, the reference may be readable, and only the id at its end is
relied on: `#census-1920-hartford-k3m9qa`, or `#m-qymrdd` for a photo. Ids are unique
across photos, documents and sources, so the end alone says what is meant.

- In the story, `#m-gdcade` shows as a link with the item's title.
- In a fact, `source: #…` cites it, and `Photo: #m-qymrdd` is read as well as today's
  `Photo: m-qymrdd`.
- Typing `#` offers completion from the tree's photos, documents and sources, as `@`
  does for people.

`#` followed by a space, at the start of a line, is still a markdown heading; a
reference has no space.

## Comments ([#53](https://github.com/devoncarew/prosapia/issues/53))

**Problem.** Editors want prompts on a new page, and somewhere for notes to each other.

**Others.** GEDCOM has notes, which every program shows; it has no hidden comments.

**Recommendation.** Do not add comments. Blank fields (below) are the prompts. A `Note:`
line, which readers see, holds a remark; anything meant for other editors can go in the
change summary, or later in a discussion per page. Hidden text is unfamiliar, invisible
to readers by design, and tends to collect facts that belong on the page. If a real need
appears later, an HTML comment (`<!-- … -->`) is the form markdown already defines.

## Blank fields on new pages

**Problem.** A new page starts with only a name, and the editor has to know which labels
exist.

**Recommendation.** A new page starts with the labels most often filled in, empty unless
something is known:

```
Name: John Smith
Sex:
Born:
Died:
Parents:
```

An empty fact is never a problem, never shown, and does not count as a value. Format
keeps empty facts, so the prompts stay until they are filled in or deleted. `Children:`
and partners are left off: the "+ add" actions are the easier way to add those.

## Where relationships are written

**Problem.** A relationship may be written on either page, or both, and the two drift
apart. Items to correct now catches the disagreements, but nothing says where a
relationship should go.

**Others.** GEDCOM keeps each couple and their children in one family record, so there
is one place for each fact and nothing to disagree. GEDCOM X instead records each pair
(a couple; a parent and child) as its own relationship, much as Prosapia's lines do. The
pair model handles single parents, unknown partners and blended families more easily;
the family record avoids duplication.

**Recommendation.** Keep person-to-person lines, read from either side, as GEDCOM X
does, but give each kind a default home that the actions and the guide use:

Every form is read, wherever it is written, and a page never fails because of where a
relationship is. Beyond that, the kinds differ:

- **Where one form is preferred, Prosapia promotes it when it can.** Siblings are best
  expressed through their parents: `Siblings:` is read while the parents are unknown,
  and once they are recorded, Prosapia offers to replace the sibling line with the
  parents. Likewise a child is best recorded with `Parents:` on the child's page, which
  says which couple they belong to; this is where the "+ add" actions write.
- **Where no form is preferred, either page will do, and disagreement is shown.**
  `Children:`, `Married:`, `Partner:` and other couple events may be written on either
  page or both. Where two pages disagree, the pages and Items to correct say so, and the
  editor decides.

Pages are not rewritten to move existing lines.

## Several values for one fact

**Problem.** Records disagree: a census says 1911, a certificate 1912. Today an editor
must choose one and lose the other, or put it in a note. A repeated `Born:` line is
read, but the last one silently wins.

**Others.** GEDCOM allows several events of the same kind, each with its own sources;
the first is preferred.

**Recommendation.** Adopt it. A life event may be repeated; the first is the one used
for the infobox, the timeline and sorting, and the others are shown beside it as "also
recorded: 1912 (certificate)" with their sources. This is not a problem to correct; an
editor removes a line once the question is settled.

## Names

**Problem.** The family name is guessed from the words of the name, which went wrong for
"Rudolph H. Wilhelm Jr." and will go wrong for names such as "Maria de la Cruz García".
Married and birth names are both `Also known as:`, without saying which.

**Others.** GEDCOM marks the family name with slashes (`Maria /de la Cruz/ García`) and
has fields for given name, prefix, suffix and nickname, and a type for each name: birth,
married, also known as.

**Recommendation.** Keep the name whole, as written. Add `Family name:` for the rare
name the guess gets wrong; the writing guide says it is optional and seldom needed. Let
`Also known as:` say what kind of name it is, in parentheses as relationships are
qualified: `Also known as: Margaret Price (married name)`. Slashes and separate name
fields would fix rare cases at the cost of every page.

## Places

**Problem.** The same place is written several ways ("Hartford, CT", "Hartford,
Connecticut, USA"), which splits search and any future map.

**Others.** GEDCOM writes a place as a list from smallest to largest, optionally with
coordinates; GEDCOM X has place records with ids.

**Recommendation.** Keep free text. Say in the guide to write places smallest to
largest, as people mostly do, and let place completion steer toward the forms already in
the tree. Places as records, with other names and coordinates, stay in Known future
work.

## Ids in other systems

**Problem.** Relatives research on FamilySearch, WikiTree and Find a Grave, and want to
link a person to their record there.

**Others.** GEDCOM 7 has external ids (`EXID`) with the system named.

**Recommendation.** Adopt it as facts: `FamilySearch: LZ5X-QRT`, `WikiTree: Carew-123`,
`Find a Grave: 12345678`, each shown as a link to the record. This is the "Record ids
from other systems" item in Known future work, and cheap to do with the other format
changes.

## Dates

**Problem.** Small: forms such as `1861 or 1862` are reported as unreadable.

**Others.** GEDCOM's date grammar has the same ideas as ours (about, before, after,
between, from–to), and other calendars.

**Recommendation.** Keep forgiving dates as typed. Read `A or B` as between A and B.
Other calendars are not needed for this family.

## Sex

**Problem.** Small: written as `male`, `M`, `female`, `f`.

**Others.** GEDCOM has M, F, X and U (unknown).

**Recommendation.** Use four values: `male`, `female`, `intersex` and `unknown`. Format
writes recognised spellings as one of them (`M` and `Male` as `male`, `F` as `female`,
`U` or `?` as `unknown`, `X` as `intersex`). Anything else is kept as written, read as
unknown, and not reported as a problem.

## Families, shared events and associations

Families are covered above. In GEDCOM 7 an event belongs to one person or to one family
record: a marriage is the family's, a birth the person's, and anyone else present is
linked to it as an association with a role, such as witness or godparent. A census that
lists a household is recorded once per person. GEDCOM X adds events as records of their
own, with each person given a role in them, so one event can be shared.

Shared events are the "events and memories" item in Known future work, and need their
own decision when it is scheduled; GEDCOM X's event with roles is the model to start
from. Until then a fact can name the others involved (`Godparent: @…`), as facts already
may.
