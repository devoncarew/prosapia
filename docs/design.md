# Design

The decisions that shape Prosapia, the reasons for the larger ones, and the questions
still open. The details of each area are in their own documents:

| Document                             | Covers                                              |
| ------------------------------------ | --------------------------------------------------- |
| [architecture.md](architecture.md)   | The system, the technology, storage, editing, views |
| [content-model.md](content-model.md) | Person pages, sources, GEDCOM                       |
| [media.md](media.md)                 | Photos and other files                              |
| [sharing.md](sharing.md)             | Privacy, sharing and trust                          |

Work that is scheduled, and work known but not yet scheduled, is in the [plan](plan.md).

## Settled

<!-- prettier-ignore -->
| Question | Answer |
| --- | --- |
| Where does Prosapia run, and on what stack? | A hosted web app: a Dart server on Cloud Run behind Firebase Hosting, Firestore for records, Cloud Storage for photos, sign-in with Google, TypeScript in the browser |
| Who is the first user? | One family, one tree, a handful of invited relatives. The simplifications this allows are removed step by step so the tool becomes general purpose |
| How are edits reviewed? | They are not: members with write access edit directly. Every edit is logged, attributed and reversible instead |
| How is per-page visibility enforced? | By the server, which is the only thing that reads the database. Designing the levels themselves is deferred |
| How are photos stored? | JPEGs and HEICs as they are; uncompressed scans as JPEG; a front and back as two files paired by name and embedded id |

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

## Open questions

None of these blocks current work. Each is discussed in the document named after it.

- How a loose memory is woven into a person's biography (content model).
- Pages for shared events, places and households (content model).
- How formal citations should be, and whether DNA evidence is in scope (content model).
- How far to support older GEDCOM versions and other tools' extensions, and how a
  re-import matches people already present (content model).
- The editing surface for relatives who will not write markdown (architecture).
- Whether some families will want review of edits back (architecture).
- Removing something from the record for good (architecture).
- The sharing model: visibility levels, consent of living people, legal duties
  (sharing).
- Documents, audio and the exact limit for stored video (media).
- Which research sites permit automated capture (content model).
- Generated text: which model for which job, its cost, and whether an owner must switch
  it on (plan).
