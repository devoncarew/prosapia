# Loom

Loom is a family-history wiki: pages about people, written as markdown with images, kept in a GitHub repository and changed through reviewed pull requests. Seven directions are set, two designs are proposed for confirmation, and three questions are open. Two of the open questions, privacy tiers and access enforcement, are deferred: early versions require a GitHub account with access to the repository, and everyone with access sees everything.

## Status

"Direction set" means you stated it in the brief. "Proposed" is a design this document suggests and you have not yet confirmed. "Open" has no answer yet. "Deferred" marks an open item set aside on purpose.

| Area | Status | Where it stands |
| --- | --- | --- |
| Viewing and editing | Direction set | Wikipedia-like pages: text, light formatting, images |
| Backing store | Direction set | A GitHub repository. The server and editor run on a clone; changes go upstream as pull requests |
| Interchange | Direction set | GEDCOM 7.0 for import and export |
| Photo information | Direction set | Names, dates and transcriptions embedded in the image file |
| Content model | Direction set | One markdown file per person, in the person's own directory; structured facts on top, free-form entries below |
| Sources and citations | Proposed | A record per source, cited from individual claims |
| Privacy tiers | Open | Deferred. The sharing model is to be decided; four levels are sketched below as a starting point |
| Edit and review flow | Direction set | Changes arrive as GitHub pull requests, are reviewed, then merged |
| Access enforcement | Open | Deferred with the sharing model. Early versions require sign-in with a GitHub account that has access to the private repository |
| Front and back scan format | Proposed | A JPEG with the back appended as a second image and the text embedded in both; from the image-format spike, pending a few manual checks |
| Hosting and technology stack | Direction set | A Dart server on a clone of the GitHub repository; TypeScript in the browser. Fallback: TypeScript for both |
| Merging new entries | Open | An update is kept as a dated entry first; how it is woven into the biography is undecided |

## Principles

- **The repository is the record.** Plain files that outlive the software. Indexes, rendered pages and trees are rebuilt from it.
- **Prose first, structure where it pays.** A contributor can add a story without filling in a form.
- **Information travels with its artifact.** What is known about a photo lives inside the photo file.
- **Every change is attributed, reviewable and reversible.**
- **Private by default.** The repository is private. Wider sharing is designed later, deliberately.
- **Every claim can cite its source.**
- **Standards at the edges.** GEDCOM 7.0 for trees, XMP and IPTC for image metadata.

## Design documents

| File | Covers |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | System overview, storage and versioning, editing and review, derived views |
| [docs/content-model.md](docs/content-model.md) | Person pages, sources and citations, GEDCOM 7.0 interchange |
| [docs/media.md](docs/media.md) | Photos, embedded metadata, front-and-back scan format |
| [docs/sharing.md](docs/sharing.md) | Privacy, sharing and trust (deferred) |
| [docs/open-questions.md](docs/open-questions.md) | Open questions |
| [docs/plan.md](docs/plan.md) | Milestones: the prototypes and spikes that settle the open decisions |
