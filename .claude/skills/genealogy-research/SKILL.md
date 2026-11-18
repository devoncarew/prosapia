---
name: genealogy-research
description: Research a person in the Prosapia family tree - find records of their birth, marriage, death, census entries, immigration, military service or burial, and add what is found to their page with sources. Use when asked to research someone, find records or sources for a person (often given as a person id such as carew-michael-k3m9qa), fill gaps in a page, check a fact, or work through the research queue or a task's inbox.
---

# Genealogy research

You are researching one person, or one question about them, for a family's Prosapia
tree. The work happens here in Claude Code. You search the sources you may search
yourself, write a brief for the searches a person has to run, and turn what is found
into changes to the tree, each with its source.

Read these before starting a task:

- [method.md](method.md): how to research, and which records to look for.
- [sites.md](sites.md): which sites you may search, which a person searches, and how
  to build their search links.
- [docs/content-model.md](../../../docs/content-model.md), the "Decided in milestone 24"
  section: the page syntax, `@` and `#` references, and how sources are cited.
- [docs/writing.md](../../../docs/writing.md): how story text and change summaries read.

## Where things are

- **The tree.** Read it from the nightly export, a git repository of the tree in plain
  files. Clone it once into `data/export` and pull it at the start of each task:

  ```
  git clone git@github.com:devoncarew/prosapia-carew.git data/export   # once
  git -C data/export pull
  ```

  It can be up to a day behind the site; if a page looks out of date, ask. A person's
  page is `people/<id>/index.md`; a page about a family is `pages/<id>/index.md`; items
  are in `media/`, a file such as `m-5t1q8z.jpg`, or `m-5t1q8z.json` for an item with
  no file. `grep` the `people/` directory to find a person's relatives and the pages that
  mention them.
- **Task logs, the queue and inboxes** are under `data/research/`, which is never
  committed. Task names are the person's id and a word or two:
  `carew-michael-k3m9qa-birth`.

  ```
  data/research/
    carew-michael-k3m9qa-birth.md     the task's log (templates/task-log.md)
    carew-michael-k3m9qa-birth/       its inbox: what a person saved for it
    queue.md                          every search waiting for a person (templates/queue.md)
  ```

## A task, step by step

1. **Set up.** Pull the export. Create the task's log from
   [templates/task-log.md](templates/task-log.md), or open it if the task is already
   under way: read it first, and carry on from where it stopped.
2. **Read what is known.** The person's page; their parents', partners' and children's
   pages; the items that name them; any `Note:` lines recording searches already run.
   Write down in the log what is known, with each fact's source or "no source".
3. **Frame the question.** One specific question: "When and where was Michael born, and
   who were his parents?" not "Research Michael". If the owner's request is broad, pick
   the gap that would unlock the most (usually an event that names parents or a place)
   and say why in the log.
4. **Plan the searches.** From [method.md](method.md), list the records that would answer
   the question, for the person's time and place, and where each is held. Siblings,
   parents and neighbours are often how a record is found.
5. **Search what you may.** Run the searches on the free sources in
   [sites.md](sites.md). Log every one, with the query, the link and what it found,
   including "nothing". Keep requests few and slow.
6. **Write the brief.** Every search a person must run goes in the log's brief as a
   checklist line: the site, the collection, a search link with the fields filled in,
   and what a matching record should show. Add each line to the right site's section of
   `data/research/queue.md` too, linking back to the log. Aim for a brief that takes a
   person under fifteen minutes.
7. **Stop and hand over.** Tell the owner what is in the brief and the queue, and that
   findings go in the task's inbox folder: a saved image or PDF, the record's link, a
   pasted transcription, or a line saying "not found".
8. **Read the inbox.** When the owner says findings are in, read each one. Transcribe
   images and PDFs. Weigh each record against what is known (see "Evidence" in
   [method.md](method.md)) and record in the log whether it is the right person, and
   why.
9. **Propose changes.** For each finding worth keeping, write the exact text for the
   owner to enter in the website:
   - an item, with its details from [templates/items.md](templates/items.md), and the
     file to upload with it;
   - the fact lines to add or change on the page, each with `source: #…` citing the
     item;
   - a short dated `##` section for the story, only when the record tells part of the
     life (an emigration, a court case), in the style of
     [docs/writing.md](../../../docs/writing.md);
   - a change summary for each page, in the style of
     [docs/writing.md](../../../docs/writing.md).

   Show each change as a diff against the current page. Nothing is written until the
   owner has entered it.
10. **Close.** Record in the log what was written, what is still open, and any search
    that found nothing worth keeping on the page as a `Note:`. Mark the queue lines
    done.

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
  the same town is a question for the owner, with the evidence for each, not a choice
  to make silently.
