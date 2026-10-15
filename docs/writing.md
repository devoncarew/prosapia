# Writing

How text in Prosapia should read. It guides the people who write pages, and it becomes
the instructions given to a language model (see [design.md](design.md#language-models)).

## Biographies

A biography reads like a good encyclopedia article written by someone in the family:
plain, warm and exact. It is neither an obituary nor a eulogy.

- **Only what the tree holds.** Do not add detail, motive, feeling or praise that the
  page does not state: no "a devoted mother", no "she must have felt". Do not add
  history the page does not mention. A sparse record gets a short biography; two or
  three sentences are better than padding.
- **Uncertainty stays visible.** "About 1925" stays "about 1925". When the record gives
  two values, say so, rather than choosing one.
- **Order:** one opening sentence on who they were (name, years, where they lived), then
  their life in order: childhood and family, schooling, work, marriage and children,
  later life, death and burial. A paragraph for each stage the record covers.
- **Third person, past tense** for people who have died. For living people, present
  tense for what is still true, and less detail: what a relative would be comfortable
  reading about themselves.
- **People by name, linked.** Introduce someone by their full name, then use their first
  name. Refer to relatives with `@` references so they link, such as
  `her husband, @carew-joseph-j-x4k2ab`.
- **Dates and places as the record gives them,** written naturally in the sentence.
- **Other people's dates only when they matter to this life.** Give the subject's own
  birth and death; for relatives, name them without their years. Mention a relative's
  birth or death only when it shaped the subject's life, such as a parent who died in
  the subject's childhood.
- **Memories are attributed, not absorbed.** A memory is someone's account: "Her niece
  Ann remembers…", not stated as fact.
- **Markdown:** plain paragraphs. Keep any existing dated `##` sections, which feed the
  timeline, and write within them.

## Change summaries

A change summary is one line in Recent changes, beside the pages it touched. It says
what changed in the record, not how.

- **Short:** under 70 characters, starting with a verb, with no full stop: "Add Mary's
  birth date and place", "Correct Thomas's death year to 1919", "Write the story of the
  navy years".
- **Specific about what changed.** Name the fact or section changed. "Update page" and
  "Fix" say nothing.
- **Do not repeat the person's name** when the change touches only their page; the
  page's name is beside it. Use names when the change involves others: "Add Mary as
  Thomas and Ann's daughter".
- **Lead with the main change** when there are several: "Add the teaching years, and two
  smaller fixes".
- **No judgement:** "Rewrite the opening paragraph", not "Improve the opening".
