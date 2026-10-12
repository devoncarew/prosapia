# Open questions

## Open questions

Of the three questions that blocked other decisions, one is deferred, one is settled, and the first user has a working assumption. The rest can wait until the area they belong to is built; each is listed in its own section above.

### Blocking

| Question | Why it blocks | Working assumption |
| --- | --- | --- |
| How is per-page visibility enforced on a git store? | Decides whether Loom needs a server, and what viewers can hold offline | Deferred with the sharing model; the repository is private for now |
| Where does Loom run, and on what stack? | Decides the technology stack, cost, and who can realistically operate it | Settled: a Dart server on a clone of a GitHub repository, TypeScript in the browser |
| Who is the first user: one family's researcher, or many families on a service? | Decides how much of sharing, invitations and multi-tree linking is needed in version one | One family, one tree, a handful of invited relatives |

### Hosting options for the second question

| Option | Suits | Main drawback |
| --- | --- | --- |
| Local-first desktop app, syncing to any git remote | A single researcher; full ownership of the data | Relatives need an install; no fine-grained viewing |
| Self-hosted web app | A technical family member running it for everyone | Someone must operate and back it up |
| Hosted service | Non-technical families | Loom holds private family data; cost and trust |
| Web app over an existing git host | Fast to build; reuses accounts, review and history | Every contributor needs an account there; access is per repository |

Chosen: the last option, a web app over an existing git host, with GitHub as the host. Requiring a GitHub account is accepted for early versions.

### Can wait

- Where image bytes live (Storage and versioning).
- Shared events, places and household pages (Content model).
- GEDCOM 5.5.1 support and re-import matching (GEDCOM 7.0 interchange).
- Which research sites permit automated capture (Sources and citations).
- The editing surface and conflict handling (Editing and review).
- Generated summaries (Derived views).
- Consent and legal duties for living people (Privacy, sharing and trust).
- Merging updates into the biography (Content model).
- The sharing model: privacy tiers and access enforcement (Privacy, sharing and trust).

## Next steps

The prototypes and spikes that settle these questions are laid out as milestones in the [plan](plan.md).
