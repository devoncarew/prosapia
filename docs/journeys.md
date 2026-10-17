# User journeys

The tasks people come to Prosapia to do, described from their side. Each says who is
doing it, what they want, and what a forgiving, streamlined version looks like. The
[plan](plan.md) builds towards these; each journey names the milestones that deliver it.

## Who

- **The family historian.** Knows the tree well, spends hours in it, wants speed and
  precision. Comfortable with forms; will occasionally edit the text directly.
- **A relative.** Knows a few people and a few stories. Visits now and then, often from
  a phone. Has never heard of GEDCOM and should never need to.
- **A reader.** Wants to look someone up, see photos, follow a line back.

## What forgiving means

These apply to every journey that adds or changes something.

- **Type it the way you would say it.** "About 1925", "spring of 1925", "the 1880s", "14
  March 1887", "3/14/1887" are all dates. Prosapia shows how it understood the input
  ("recorded as: about 1925") and asks only when it is truly ambiguous, such as whether
  3/4/1887 is March or April.
- **Suggest, don't demand.** Places and people complete from what the tree already
  holds, but free text is always accepted. A new place is just a new place.
- **Warn, don't block.** A child born after their mother's death, or a parent aged
  eight, produces a gentle question, not an error. Real records are messy, and the
  editor may know something the checks do not.
- **Nothing typed is lost.** Unsaved input survives a closed tab or a dropped
  connection. Every save can be undone.
- **Plain text, lightly marked.** A page is "Name: value" fact lines and prose, with `@`
  for people and `[date: …]` and `[place: …]` where marking helps. No YAML or GEDCOM
  tags. Ids appear only after `@` in the editor, inserted by completion; readers see
  names.
- **Help, with consent.** A language model may turn a sentence into fields or draft a
  paragraph, but its work is always shown for the person to accept or change before
  anything is saved.

## The journeys

### 1. Add a significant event to someone's life

_A relative remembers that Margaret moved to Chicago with her sister in the spring
of 1925._

From Margaret's page they choose **Add an event**. They pick "moved" (or just type the
sentence and let Prosapia fill the fields), enter "spring 1925" and start typing "Chi…",
picking Chicago, Illinois from the places already in the tree. They add her sister by
name from the people in the tree, and optionally a sentence or two and a photo. The
event appears on Margaret's timeline, and on her sister's.

Milestones: 15 (events), 13 (forgiving dates and places), 17 (from a sentence). All
after opening to the family.

### 2. Add a child to someone's page

_The historian finds a baptism record for a fourth child of Thomas and Ann._

They edit Thomas's page and add the name to his `Children:` line: `Mary Hughes`. Typing
`@` and part of a name would instead offer people already in the tree, in case she is
there already. Saved, she appears among Thomas's and Ann's children and among her
siblings, as a name without a page. When there is something to say about her, they use
**Create a page** on her name; Prosapia checks for a similar person already in the tree,
then creates her page with her parents filled in and turns the name into a link.

Milestones: 14 (relationships in the text), 13 (the page syntax).

### 3. Add a parent, partner or sibling

The same as adding a child, typed in the `Parents:`, `Partner:` or `Siblings:` line of
either person's page. A partner line can carry a marriage date and place:
`Partner: @price-ann-9c4e2b, married [date: 1884]`.

Milestone: 14.

### 4. Correct a fact

_A cousin knows Margaret's birth year is wrong: 1887, not 1888._

They choose Edit on Margaret's page, change the `Born:` line, and say briefly why. If
the change contradicts a cited source, Prosapia mentions it. The old value stays in the
history.

Milestone: 13.

### 5. Write or expand a biography

_Margaret's page has dates, an occupation, two memories and five captioned photos, but
no story._

In the editor, the historian chooses **Claude: Draft…**, which suggests "Write a short
biography from the facts, memories and photo captions." The model writes a few
paragraphs from what the tree holds, adding nothing it was not given, and they appear in
place of the empty story; undo would take them away again. The historian edits them and
saves, and the history records that the revision had help.

Later, the historian learns about Margaret's teaching years. They choose **Claude:
Draft…** again, ask it to "add her years in Hartford", and paste their notes. The model
works them into the story, keeping its wording elsewhere, and marks the lines it wrote
or changed.

To find out more, the historian chooses **Claude: Research ideas** on Margaret's page,
and gets a short list of records to look for and where, such as the 1900 census in
Scranton on FamilySearch.

Milestone: 16; 17 (weaving memories into an existing biography).

### 6. Add a photo with its back

_A relative scans a photo and the handwriting on its back._

They upload both sides, and Prosapia offers a transcription of the back for them to
check. They tag who is in it by typing names, and add a rough date ("about 1949"). The
names, date and transcription are written into the image files, and the photo appears on
each tagged person's page.

Milestone: 6.

### 7. Share a memory from a phone

_At a family gathering, someone remembers a story about their grandfather._

On their phone they open his page, choose **Add a memory**, type or dictate it, and
save. Date and place are optional. It appears at once, attributed to them.

Milestones: 15 (memories with dates, places and people), 19 (editing on a phone). Both
after opening to the family; until then, memories are added from a desktop.

### 8. Find someone

Typing a name in the search box offers matching people as you type, with their years and
parents, so two John Carews can be told apart.

Milestone: 13 (people completion, reused by search).

### 9. Undo a mistake

Someone's edit removed a paragraph. Any editor opens the page's change history, chooses
the version before it to see what it changed, and restores it. A page created by mistake
is deleted; a page deleted by mistake is brought back from its address, with the links
to it on other pages. This works today.

### 10. Join the family's tree

_An aunt receives an invitation._

She follows the link, signs in with her Google account, and lands on the home page. It
welcomes her, shows her own page and close family with a button to add a memory, and
lists the latest changes and where to go next, including a short guide to researching
the family.

Milestones: 5 (invitations), 18 (first visit).
