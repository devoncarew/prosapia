# Open questions

## Open questions

The questions that blocked other decisions are settled. The rest can wait until the area
they belong to is built; each is listed in its own document.

### Settled

| Question | Answer |
| --- | --- |
| Where does Loom run, and on what stack? | A hosted web app: a Dart server on Cloud Run behind Firebase Hosting, Firestore for records, Cloud Storage for photos, sign-in with Google, TypeScript in the browser |
| Who is the first user? | One family, one tree, a handful of invited relatives. The simplifications this allows are removed step by step so the tool becomes general purpose |
| How is per-page visibility enforced? | By the server, which is the only thing that reads the database. Designing the levels themselves is deferred |

### Why not git

The first design kept each tree in a GitHub repository and made changes through pull
requests. It was dropped because most relatives have a Google account and no GitHub
account, so Loom needed its own sign-in and editing screens anyway, and per-person
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
