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
- **Never show the plumbing.** No YAML, ids or GEDCOM tags in the normal path. Editing
  the page as text stays available for the historian who wants it.
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

Milestones: 15 (events), 13 (forgiving dates and places), 16 (from a sentence).

### 2. Add a child to someone's page

_The historian finds a baptism record for a fourth child of Thomas and Ann._

From Thomas's page they choose **Add a child**. Ann is offered as the other parent,
since she is Thomas's only partner; they could pick "unknown" instead. They type the
child's name and "bapt. 1891" as the birth. If someone with a similar name and dates is
already in the tree, Prosapia asks whether it is the same person before creating
another. The new child appears among Thomas's and Ann's children and the siblings, and
their new page invites a few more details.

Milestones: 14 (adding people), 13 (dates).

### 3. Add a parent, partner or sibling

The same as adding a child, from the other direction. Adding a second partner asks for
the order and any marriage date. Adding a sibling places the new person under the same
parents, creating unknown parents if none are recorded.

Milestone: 14.

### 4. Correct a fact

_A cousin knows Margaret's birth year is wrong: 1887, not 1888._

They click the birth date in Margaret's infobox, change it, and say briefly why. If the
change contradicts a cited source, Prosapia mentions it. The old value stays in the
history.

Milestones: 13 (editing facts directly).

### 5. Write or expand a biography

_Margaret's page has dates, an occupation, two memories and five captioned photos, but
no story._

The historian chooses **Draft a biography**. A language model writes a few paragraphs
from what the tree holds, citing nothing it was not given. The draft is shown beside the
current page; the historian edits it and saves. The history records that the text began
as a model's draft. The same flow tidies a passage, or weaves loose memories into an
existing biography.

Milestone: 17.

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

Milestones: 15 (memories with dates, places and people), 18 (phone-friendly).

### 8. Find someone

Typing a name in the search box offers matching people as you type, with their years and
parents, so two John Carews can be told apart.

Milestone: 13 (people completion, reused by search).

### 9. Undo a mistake

Someone's edit removed a paragraph. Any editor opens the page's history, sees who
changed what, and restores the earlier version. This works today.

### 10. Join the family's tree

_An aunt receives an invitation._

She follows the link, signs in with her Google account, and lands on a page that
explains what Prosapia is, shows her own page or the nearest relative's, and suggests
one easy thing to do, such as adding a memory.

Milestones: 5 (invitations), 18 (first visit).
