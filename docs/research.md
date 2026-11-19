# Research with Claude Code

How a tree's owner researches the family with Claude Code: give it a task such as "find
birth records for @carew-michael-k3m9qa", and it searches what it may, writes down what
a person needs to look up, and adds what it finds to the tree. This is separate from
[plan.md](plan.md) because none of it is part of the website and general members never
see it. The milestones below are numbered R1, R2 and so on, apart from that plan's.

## Where the records are

- **FamilySearch** is the main source. It is free but has no public API, and its record
  search needs a signed-in person. Claude writes the searches and a person runs them.
- **Ancestry** is for a limited time, with a subscription taken out while there is a
  batch of searches worth running. Its terms forbid automated access, so all of it is
  done by a person. Anything found is saved into Prosapia then, so nothing depends on
  the subscription afterwards.
- **Free sources with open APIs** Claude can search itself: newspapers (loc.gov's
  Chronicling America; Trove and Papers Past if a branch leads there), books and
  directories (Internet Archive, HathiTrust), and WikiTree for spot checks.
- **Find a Grave and MyHeritage** forbid automated access, so a person searches them
  too. Find a Grave is free; MyHeritage, like Ancestry, is for a limited time if at all.

## How a task runs

1. **Start.** The owner asks for a task in Claude Code. The research skill loads.
2. **Read.** Claude reads the person's page, their close family, their items and what is
   still unsourced, using the commands in R2.
3. **Search.** Claude searches the free sources (R4) and records each search in the task
   log, including the ones that found nothing.
4. **Searches for a person.** Searches it may not run are written into the log, one
   section each, headed with the site, with a search link with the fields already filled
   in and what a match should show.
5. **Hand back.** The person runs them, saves what they find (an image or PDF, and the
   record's link) into the task's inbox folder, and writes under each search what it
   turned up, including related finds and "not found". They may edit pages as they go.
6. **Write.** Claude turns the findings into changes: items first, then a section per
   person with the facts citing them and any dated section for the story. Each is shown
   as a diff, which the owner reviews in the log, and applied only when they agree.
7. **Close.** The log records what was written, with the change ids, and what is still
   open. Searches worth running later move to one file of open searches.

## Parts

### The research skill

A project skill at `.claude/skills/genealogy-research/`. It holds method, not access:

- The Genealogical Proof Standard in short: search reasonably widely, cite every source,
  weigh conflicting evidence, and write down the reasoning.
- Which records to look for by event, era and place: census, civil and parish registers,
  probate, land, military, immigration, city directories, newspapers.
- Which sites Claude may search itself and which go into a brief, as listed above.
- How to cite in Prosapia: items, `source: #…` on facts, `[source: …]` in the story, ids
  in other systems as facts (`FamilySearch: LZ5X-QRT`), and `source: needed`.
- Rules: never state a match as fact without a source; when records disagree, add a
  second value with its source rather than replacing the first; leave a page's prose
  alone unless the task is about it.
- Templates for the task log, the open searches, and an item for each common kind of
  record.

The in-app help in [assist.dart](../lib/src/assist.dart) can later read the same method
file, so that its record suggestions agree with the skill.

### Prosapia commands for agents

A command of its own, `bin/research.dart`, run as `dart run prosapia:research …`. It is
kept apart from the server's entry point, whose options are about serving, but shares
everything in `lib/src`. It works against Firestore (`--tree`) or a local tree
directory, as the server does, through the same store. It prints JSON for reading and a
diff for writing.

- `show <id>`: the page text and its revision, its facts as read, its items, and the ids
  of its parents, partners, children and siblings.
- `gaps <id>`: empty and unsourced facts, `source: needed` marks, and contradictions.
- `find <name> [--born …] [--place …]`: people matching, so that a record can be matched
  to the right person or found to be about someone not yet in the tree.
- `append <id> --file <section.md>`: add a dated section to the story.
- `edit <id> --file <page.md> --based-on <revision>`: replace the page text. The store
  already refuses the write if the page has moved on.
- `add-item --file <image or pdf> --details <json>`: a new item, with or without a file,
  with its title, date, place, people, transcription, link and access date.

Writes show their diff and change nothing without `--apply`. They are saved like any
edit: a revision, a change log entry with a summary, the owner as author (`--by`), and
the model in `helpedBy`, so that history shows Claude helped and any change can be
undone. Prosapia has no review step, and this does not add one; the owner reading the
diff before `--apply` is the review.

[Architecture](architecture.md) says only the server touches the database. These
commands go through the same store code as the server, so the rule that matters (one
store interface, revisions and the log on every write) still holds.

### Free-source search

`dart run prosapia:research lookup <source> <query> [--years …] [--place …]`, with
`newspapers`, `books` and `wikitree` to start. Each result is a candidate in the shape
of an item: title, date, place, link, a snippet of text, and the date it was accessed. A
candidate becomes an item through `add-item`. Requests are slow and few, within each
API's rate limit.

### Task logs and the inbox

Kept on the owner's computer under `data/research/`, which is never committed, since the
logs hold family details:

```
data/research/
  carew-michael-k3m9qa-birth.md     one task's log
  carew-michael-k3m9qa-birth/       its inbox: what a person saved for it
  open.md                           searches worth running later, from closed tasks
```

A search for a person lives in its task's log, as a section headed with the site first
("### Ancestry: 1900 census"), with a Results list below it that the person fills in:
the record's link, the file saved, related finds, or "not found". A search with results
is done; there are no checkboxes to tick, and nothing is kept in two places. One site's
searches across every task are found by searching the logs for its heading, which is how
Ancestry's are batched during a subscription. When a task closes, the one or two
searches still worth running move to `open.md`, each linking back to its log.

Images are kept in preference to links, since an image is self-contained and outlasts a
subscription; the link is still asked for, as the item's citation.

A log has: the question, what was already known, each search Claude ran (site, query,
link, what it found), the searches for a person with their results, the findings, and
the changes proposed and written. What lasts goes into the tree as items and facts, not
in the log. A search that found nothing can be kept on the page as a `Note:`, where it
stops the next researcher repeating it.

## Milestones

### R1: The skill and the task log

- Write the skill, its templates, and the list of sites and what each allows.
- Run one real task from start to finish, reading the tree from an export and writing
  changes by hand in the website.

Done when one task produces a log, searches that a person can run in under fifteen
minutes, and a sourced change to a page.

Run on Michael F. Carew (November 2026): the searches found four censuses, his wife's
death certificate and her parents' gravestone. What it showed: an image matters more
than a link but both are wanted; ticking a brief and a queue was double work, and
searches turn up more than their question, so results are now free-form under each
search; and entering items, then facts that cite them, by hand takes two passes, which
R3 removes. Its changes will be entered with R2 and R3, as their test.

### R2: Reading commands

- `show`, `gaps` and `find`, against both Firestore and a local tree.
- The skill uses them in place of reading an export.

Done when Claude can start a task from a person's id alone, without a fresh export.

Built in November 2026, in [bin/research.dart](../bin/research.dart) and
[lib/src/research.dart](../lib/src/research.dart). `show` also lists the pages that
mention the person and the relatives named without a page; `find` takes `--born`,
`--within` and `--place`.

### R3: Writing commands

- `append`, `edit` and `add-item`, with a diff by default and `--apply`.
- Attribution through `--by` and `helpedBy`, and tests against a local tree.

Done when a task's findings reach the tree without using the website, and show in a
page's history as helped by Claude.

Built in November 2026, in
[lib/src/research_write.dart](../lib/src/research_write.dart). A write refuses new text
that refers to nothing in the tree, so a `#NEW-…` placeholder for an item not yet added
cannot be saved by mistake. The change summary is recorded as written by the model that
helped. Tests use a store in memory; the commands were also run against the emulators.
Items record their author but not `helpedBy`, which the store does not yet keep for
them.

### R4: Free-source search

- `lookup` for loc.gov newspapers, Internet Archive and WikiTree, then HathiTrust.
- Results that `add-item` takes as they are.

Done when a task finds and cites a newspaper item without a person searching.

### R5: The inbox

- Claude reads a task's inbox: transcribes images and PDFs, proposes items and facts
  from them, and files each one.
- A session at one site: work through that site's searches across the open logs and
  `open.md`, saving each find to its task's inbox.

Done when a batch of saved Ancestry records becomes cited items and facts in one
sitting.

## Open

- Whether negative results belong on the page as a `Note:`, in the item, or only in the
  log.
- Copyright and site terms for record images saved from FamilySearch and Ancestry,
  already open in [content-model.md](content-model.md#open-1).
- Whether a cross-task log of searches already run is needed, or whether a page's items
  and notes are enough.
- An MCP server around these commands, if research moves to Claude desktop or the web.
