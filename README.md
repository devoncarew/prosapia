# Prosapia

_Genealogy, in prose._

Prosapia is a family-history wiki. Each person in a family has a page: their story
written as prose, with the facts that matter (dates, places, parents, partners), their
photos, and the sources behind what is known. Relatives sign in with a Google account to
read and edit. Every change is recorded and can be undone, and the whole tree is kept
exportable as plain files that need no special software to read.

_Prosapia_ is Latin for lineage, or family line.

## Status

Early development. Prosapia is not yet ready for a family to use: it runs on a
developer's machine, against Firebase's local emulators, with a sample tree. Putting it
on the internet is the next milestone; see [the plan](docs/plan.md).

Working today:

- Person pages with an infobox of facts, a timeline, photos and full-text search.
- Sign-in with Google, limited to a tree's invited members, with owner, editor and
  viewer roles.
- Editing a page as text with a live preview; every save is kept, with page history,
  comparison and restore.
- "Add a memory": a quick way to add a dated story to someone's page.
- Loading an existing tree exported from other genealogy software (GEDCOM), with its
  photos, using command-line tools.

## Principles

- **A family's history outlives the software.** The whole tree is exported as plain
  markdown files and photos that need no Prosapia to read. (The export is not built
  yet.)
- **Prose first, structure where it pays.** A relative can add a story without filling
  in a form.
- **Information travels with its artifact.** What is known about a photo, including who
  is in it and what is written on the back, is stored inside the photo file.
- **Every change is attributed, logged and reversible.**
- **Private by default.** Only invited members can sign in.
- **Every claim can cite its source.**
- **Standards at the edges.** GEDCOM for exchanging trees with other software; XMP and
  IPTC for photo metadata.

## Learn more

<!-- prettier-ignore -->
| Document | Covers |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | How it is built: the system, the technology, storage and versioning, editing, derived views |
| [docs/content-model.md](docs/content-model.md) | What a person's page holds, sources and citations, GEDCOM import and export |
| [docs/media.md](docs/media.md) | Photos: storage formats, embedded metadata, fronts and backs, rolls |
| [docs/sharing.md](docs/sharing.md) | Privacy, sharing and trust (not yet designed in full) |
| [docs/design.md](docs/design.md) | The main decisions and why, and the questions still open |
| [docs/journeys.md](docs/journeys.md) | The tasks people come to Prosapia to do, and what a forgiving version looks like |
| [docs/plan.md](docs/plan.md) | What is being built next, known future work, and a changelog |

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers running Prosapia locally, the checks a change
must pass, and how work is organised.

## License

BSD 3-Clause; see [LICENSE](LICENSE).
