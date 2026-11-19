---
name: genealogy-research
description: Research a person in the Prosapia family tree - find records of their birth, marriage, death, census entries, immigration, military service or burial, and add what is found to their page with sources. Use when asked to research someone, find records or sources for a person (often given as a person id such as carew-michael-k3m9qa), fill gaps in a page, check a fact, or read the findings saved for a task or the open searches.
---

# Genealogy research

You are researching one person, or one question about them, for a family's Prosapia
tree. The work happens here in Claude Code. You search the sources you may search
yourself, write down the searches a person has to run, and turn what is found into
changes to the tree, each with its source.

Read these before starting a task:

- [method.md](method.md): how to research, and which records to look for.
- [sites.md](sites.md): which sites you may search, which a person searches, and how to
  build their search links.
- [docs/content-model.md](../../../docs/content-model.md), the "Decided in milestone 24"
  section: the page syntax, `@` and `#` references, and how sources are cited.
- [docs/writing.md](../../../docs/writing.md): how story text and change summaries read.

## Where things are

- **The tree.** Read and write the live tree with the research command. Reading prints
  JSON:

  ```
  dart run prosapia:research --project prosapia-ea818 --tree carew show <id>
  dart run prosapia:research --project prosapia-ea818 --tree carew gaps <id>
  dart run prosapia:research --project prosapia-ea818 --tree carew find <name> [--born <year>] [--place <text>]
  ```

  `<id>` is a page's id or reference: `carew-michael-k3m9qa`, `@carew-michael-k3m9qa` or
  `p-k3m9qa`. `show` gives the page's text and revision, its facts with their sources,
  its parents, partners, children and siblings (whichever page states them), relatives
  named without a page, the items that show it or that it cites (with each item's
  details and transcription), and the pages that mention it. `gaps` lists the empty
  facts, the facts without a source, those marked `source: needed`, contradictions with
  other pages, and dates worth checking. `find` lists people whose names match, to tell
  whether a record's people are already in the tree.

  It needs Google credentials that can read the project
  (`gcloud auth application-default login`). Without them, read the nightly export with
  `--files data/export` instead (clone `git@github.com:devoncarew/prosapia-carew.git`
  there once, and `git -C data/export pull`); it can be a day behind the site. An item's
  file is in the export's `media/` folder, such as `m-5t1q8z.jpg`.

- **Task logs, inboxes and open searches** are under `data/research/`, which is never
  committed. Task names are the person's id and a word or two:
  `carew-michael-k3m9qa-birth`.

  ```
  data/research/
    carew-michael-k3m9qa-birth.md     the task's log (templates/task-log.md)
    carew-michael-k3m9qa-birth/       its inbox: what a person saved for it
    open.md                           searches worth running later (templates/open.md)
  ```

## A task, step by step

1. **Set up.** Create the task's log from
   [templates/task-log.md](templates/task-log.md), or open it if the task is already
   under way: read it first, and carry on from where it stopped.
2. **Read what is known.** `show` and `gaps` for the person, then `show` for their
   parents, partners and children; the items that name them; any `Note:` lines recording
   searches already run. Write down in the log what is known, with each fact's source or
   "no source".
3. **Frame the question.** One specific question: "When and where was Michael born, and
   who were his parents?" not "Research Michael". If the owner's request is broad, pick
   the gap that would unlock the most (usually an event that names parents or a place)
   and say why in the log.
4. **Plan the searches.** From [method.md](method.md), list the records that would
   answer the question, for the person's time and place, and where each is held.
   Siblings, parents and neighbours are often how a record is found.
5. **Search what you may.** Run the searches on the free sources in [sites.md](sites.md)
   with `lookup`, and read a hit with `text`:

   ```
   dart run prosapia:research lookup newspapers <words> [--years 1890-1900] [--place <US state>]
   dart run prosapia:research lookup books <query> [--years 1880-1920]
   dart run prosapia:research lookup wikitree <given> <family> [--born <year>]
   dart run prosapia:research text <link> <words> [--context <lines>]
   ```

   Each newspaper page or book comes with an `item`: details `add-item` takes as they
   are, once you add the people and a transcription of the passage. A newspaper page's
   words need not be near each other: `together` says whether the passage has them
   within a few words, and those pages come first. Log every search, with the query and
   what it found, including "nothing".

6. **Write the searches for a person.** Each search a person must run gets its own
   section in the log, headed with the site first ("### FamilySearch: 1880 census"): a
   search link with the fields filled in, what a matching record should show, and an
   empty Results list. Aim for searches that take a person under fifteen minutes in all.
   A search on a paid site (Ancestry, MyHeritage, Newspapers.com) is optional: head it
   "(account needed)", after the free ones, and propose it only when it is the best
   place for the record.
7. **Stop and hand over.** Tell the owner the searches are ready. They save files in the
   task's inbox folder, the image or PDF first and the record's link with it, and write
   under each search's Results what they found: the link, the file, the details,
   anything else turned up along the way, or "not found". They may also edit pages in
   the website as they go, and say so under Results.
8. **Read the results.** When the owner says the searches are run, read each Results
   list and each file in the inbox. Transcribe images and PDFs, and reread any page the
   owner says they edited. Weigh each record against what is known (see "Evidence" in
   [method.md](method.md)) and record in the log whether it is the right person, and
   why.
9. **Propose changes.** For each finding worth keeping, write the exact text for the
   tree, items first (one record can name several people), then a section per person:
   - an item, with its details from [templates/items.md](templates/items.md), and the
     file to upload with it;
   - the fact lines to add or change on the page, each with `source: #…` citing the
     item;
   - a short dated `##` section for the story, only when the record tells part of the
     life (an emigration, a court case), in the style of
     [docs/writing.md](../../../docs/writing.md);
   - a change summary for each page, in the style of
     [docs/writing.md](../../../docs/writing.md).

   Show each change as a diff against the current page. The owner reviews the proposal
   in the log, editing, striking or approving each part. Nothing is written until they
   have approved it.

10. **Write what was approved.** With the research command, as the owner (`--by`, their
    email address, or `PROSAPIA_BY` in `.env`). Each write prints what it would save and
    saves only with `--apply`; run it once without, check the output, then apply.
    - **Items first**, since the facts cite them. Put the item's details in a JSON file
      (`title`, `date`, `place`, `transcription`, `notes`, `link`, `found`, `people`)
      and run `add-item --details <item.json> --file <inbox file> --summary <summary>`.
      It prints the new id, such as `#m-x2k9ab`: replace the `#NEW-…` placeholder with
      it everywhere in the log.
    - **Then each person's page**: `show <id>` again for its text and revision, apply
      the approved changes to that text in a scratch file, and run
      `edit <id> --file <page.md> --based-on <revision> --summary <summary>`. A dated
      story section alone can go through `append <id> --file <section.md>`.
    - It refuses a page that has moved on since `--based-on` (show it again and redo the
      edit), and new text with a reference to nothing, such as a `#NEW-…` placeholder
      left in.
    - **An item already in the tree** (a link or transcription to add or correct):
      `edit-item <item> --details '{"link": "…"}'`. The details given replace what it
      has, `""` clears one, and the rest are kept; `people` replaces the whole list.
    - Record each change id it prints in the log.

11. **Close.** Record in the log what was written, what is still open, and any search
    that found nothing worth keeping on the page as a `Note:`. Move the one or two
    searches worth running later, including paid ones not run, to
    `data/research/open.md` ([templates/open.md](templates/open.md)), dated and linking
    back to the log.

## Open searches

`data/research/open.md` is worked one entry at a time, when the owner asks.

- **Running an entry.** Open its log and carry on there. Run what you may yourself (the
  free sources) and log it in the Searches table; write what only a person can run as a
  new section under "Searches for a person". Read the results, propose and write the
  changes as in steps 8 to 10, and record them under the log's Written list. Remove the
  entry from `open.md` once all of it is run, whatever it found; if only your part is
  run, reword the entry to what is left for a person. A search that found nothing can be
  kept as a `Note:` on the page.
- **Pruning.** When asked to tidy `open.md`, list each entry with its date, its site,
  and what it would settle, and suggest which to drop: ones a later task has answered,
  or that depend on an account the owner does not expect to have. Remove the ones the
  owner agrees to, with a line in each log: "Dropped from open searches, <date>: <why>".

## Rules

- **Nothing is stated without a source.** A record that might be the person is a lead,
  written in the log, not a fact on the page. When a match is likely but not certain,
  say so in the fact or the story ("probably", "about") and cite what it rests on.
- **Records that disagree are both kept.** Add a second line for the fact with its own
  source rather than replacing the first (the page shows it as "also recorded"). Say in
  the log which you think is right and why.
- **Change only what the task is about.** Leave the rest of the page, especially the
  prose, as it is. A problem noticed elsewhere goes in the log for the owner.
- **Trees are not sources.** A FamilySearch, WikiTree or Ancestry tree is a lead to the
  records it cites. Cite the record, not the tree.
- **Ids in other systems are facts.** When the person is found in FamilySearch's tree,
  WikiTree or Find a Grave, propose `FamilySearch: LZ5X-QRT`, `WikiTree: Carew-123` or
  `Find a Grave: 12345678` as a fact line.
- **Respect each site's terms.** Never fetch, scrape or drive a browser on a site that
  [sites.md](sites.md) lists for a person to search, even when it seems quicker.
- **Living people are left alone.** Do not search for anyone who may be living unless
  the owner asks, and never put a living person's details in a query.
- **Ask when the right person is unclear.** Two candidates of the same name and age in
  the same town is a question for the owner, with the evidence for each, not a choice to
  make silently.
