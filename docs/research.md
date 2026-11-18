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
4. **Brief.** Searches it may not run are written into the log as a brief for a person,
   with the site, the collection, a search link with the fields already filled in, and
   what a match should show. Each search also goes into one shared queue, by site, so a
   person can run a site's searches together, Ancestry's during a subscription.
5. **Hand back.** The person runs the brief and saves what they find (an image, a PDF, a
   pasted transcription, the record's link) into the task's inbox folder.
6. **Write.** Claude turns the findings into changes: a new item for the record, a fact
   with a `source:` citing it, or a dated section in the story. Each change is shown as
   a diff and applied only when the owner agrees.
7. **Close.** The log records what was written, with the change ids, and what is still
   open.

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
- Templates for the task log, a brief, and an item for each common kind of record.

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
  queue.md                          every search waiting for a person, by site
```

The queue has a section per site (FamilySearch, Ancestry, Find a Grave, MyHeritage), and
each search in it links back to its task's log, where its result is written when it has
been run. One queue, rather than one per site, means a person sees everything waiting in
one place, and a site that needs a subscription is simply a section left until there is
one.

A log has: the question, what was already known, each search (site, query, link, what it
found), the brief for a person as a checklist, the findings, and the changes written.
What lasts goes into the tree as items and facts, not in the log. A search that found
nothing can be kept on the page as a `Note:`, where it stops the next researcher
repeating it.

## Milestones

### R1: The skill and the task log

- Write the skill, its templates, and the list of sites and what each allows.
- Run one real task from start to finish, reading the tree from an export and writing
  changes by hand in the website.

Done when one task produces a log, a brief that a person can run in under fifteen
minutes, and a sourced change to a page.

### R2: Reading commands

- `show`, `gaps` and `find`, against both Firestore and a local tree.
- The skill uses them in place of reading an export.

Done when Claude can start a task from a person's id alone, without a fresh export.

### R3: Writing commands

- `append`, `edit` and `add-item`, with a diff by default and `--apply`.
- Attribution through `--by` and `helpedBy`, and tests against a local tree.

Done when a task's findings reach the tree without using the website, and show in a
page's history as helped by Claude.

### R4: Free-source search

- `lookup` for loc.gov newspapers, Internet Archive and WikiTree, then HathiTrust.
- Results that `add-item` takes as they are.

Done when a task finds and cites a newspaper item without a person searching.

### R5: The inbox

- Claude reads a task's inbox: transcribes images and PDFs, proposes items and facts
  from them, and files each one.
- A session at one site: work through that site's section of `queue.md`, saving each
  find to its task's inbox.

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
