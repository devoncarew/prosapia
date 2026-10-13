# Privacy, sharing and trust

Deferred: the sharing model is to be decided later. Until then a tree has members,
invited by email and signed in with Google, and every member can read everything. Pages
carry no visibility field yet. The levels below are a starting sketch for when sharing
is designed.

<!-- prettier-ignore -->
| Level | Who can read | Default for |
| --- | --- | --- |
| Private | The tree's editors only | Living people |
| Family | People invited to this tree | Recently deceased people |
| Extended | Invited people from linked trees, such as in-laws and distant cousins | Nobody by default; chosen per page |
| Public | Anyone with the link; may be linked from other systems | People who died long ago |

| Role   | Can do                                                      |
| ------ | ----------------------------------------------------------- |
| Owner  | Everything, including membership and visibility rules       |
| Editor | Edit any page directly; every edit is logged and reversible |
| Viewer | Read what their circle allows                               |

## Decided by the brief

- Private family information must not end up in public places.
- Trust expands in circles: viewing or editing rights for a family can be granted to
  specific people.
- Pages about people who have died can be shared more widely than pages about the
  living.
- Pages about people from long ago can be linked from other systems.

## Proposed

- **A person is treated as living** unless a death is recorded or the birth was more
  than 100 years ago. The threshold is a per-tree setting.
- **Visibility belongs to the page**, with a tree-wide default. An editor can tighten or
  loosen a single page.
- **Photos inherit the strictest level** of the people tagged in them.
- **A private person still appears as a placeholder** ("living relative") in wider
  views, so the tree's shape is intact.
- **Public pages link outward** to matching profiles on shared trees such as WikiTree
  and FamilySearch, rather than copying data in.

## Enforcing it

Only the server reads the database, so visibility is enforced in one place: the server
decides, for each signed-in member, which people and photos they may see, and shows a
placeholder for the rest. This was the hard problem when the store was a git repository
that anyone with access could copy whole. It is now an ordinary feature to build, and it
no longer blocks other work.

The nightly export needs the same care: an exported repository holds everything, so it
stays private to the tree's owners.

## Also open

- Consent: does a living person get a say over their own page, and can they see it?
- What happens to a page's level automatically when a death is recorded.
- Legal obligations for data about living people, which vary by country.
- Whether an invited viewer can re-share, and how an invitation is revoked.
