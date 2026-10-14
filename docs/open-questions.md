# Open questions

## Where each area stands

"Direction set" means the area is decided. "Proposed" is a design written up but not yet
confirmed. "Open" has no answer yet; "deferred" marks an open item set aside on purpose.

<!-- prettier-ignore -->
| Area | Status | Where it stands |
| --- | --- | --- |
| Viewing and editing | Direction set | Wikipedia-like pages: text, light formatting, images |
| Backing store | Direction set | Firestore for records, Cloud Storage for photos. Every save is kept as a revision and logged. A nightly export writes the tree as markdown files to a private GitHub repository |
| Interchange | Direction set | GEDCOM 7.0 for import and export |
| Photo information | Direction set | Names, dates and transcriptions embedded in the image file |
| Content model | Direction set | One markdown file per person, in the person's own directory; structured facts on top, free-form entries below |
| Sources and citations | Proposed | A record per source, cited from individual claims |
| Privacy tiers | Open | Deferred. The sharing model is to be decided; four levels are sketched below as a starting point |
| Editing | Direction set | Members with write access edit directly, with no review step. Every edit is logged, attributed and reversible |
| Access enforcement | Open | Deferred with the sharing model. Members are invited by email and sign in with Google; roles are owner, editor and viewer |
| Photo storage | Direction set | JPEGs and HEICs kept as they are; uncompressed scans become JPEG. A front and back are two files paired by name and embedded id |
| Hosting and technology stack | Direction set | A Dart server on Cloud Run behind Firebase Hosting; TypeScript in the browser; Firebase sign-in. Fallback: TypeScript for the server too |
| Merging new entries | Open | An update is kept as a dated entry first; how it is woven into the biography is undecided |

## Open questions

The questions that blocked other decisions are settled. The rest can wait until the area
they belong to is built; each is listed in its own document.

### Settled

<!-- prettier-ignore -->
| Question | Answer |
| --- | --- |
| Where does Prosapia run, and on what stack? | A hosted web app: a Dart server on Cloud Run behind Firebase Hosting, Firestore for records, Cloud Storage for photos, sign-in with Google, TypeScript in the browser |
| Who is the first user? | One family, one tree, a handful of invited relatives. The simplifications this allows are removed step by step so the tool becomes general purpose |
| How is per-page visibility enforced? | By the server, which is the only thing that reads the database. Designing the levels themselves is deferred |

### Why not git

The first design kept each tree in a GitHub repository and made changes through pull
requests. It was dropped because most relatives have a Google account and no GitHub
account, so Prosapia needed its own sign-in and editing screens anyway, and per-person
visibility is hard on a store that is copied whole. Git survives as the export: a
nightly copy of the tree as files in a private GitHub repository.

Alternatives considered: a git repository owned by the server, a self-hosted forge,
PostgreSQL, an existing wiki engine, and Google Drive. PostgreSQL fits family
relationships better than Firestore and remains the fallback; Firestore was chosen for
having no running cost and nothing to operate at one family's size.

### Can wait

- Shared events, places and household pages (Content model).
- GEDCOM 5.5.1 support and re-import matching (GEDCOM 7.0 interchange).
- Which research sites permit automated capture (Sources and citations).
- The editing surface (Editing).
- Generated summaries (Derived views).
- Consent and legal duties for living people (Privacy, sharing and trust).
- Merging updates into the biography (Content model).
- The sharing model: privacy tiers and access enforcement (Privacy, sharing and trust).

## Next steps

Scheduled work, and work known but not yet scheduled, is in the [plan](plan.md).
