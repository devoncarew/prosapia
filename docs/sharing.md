# Privacy, sharing and trust

Deferred: the sharing model is to be decided later. Until then the GitHub repository is private, signing in requires a GitHub account with access to it, and everyone with access can read everything. Pages carry no visibility field yet. The levels and roles below are a starting sketch for when sharing is designed.

| Level | Who can read | Default for |
| --- | --- | --- |
| Private | The tree's editors only | Living people |
| Family | People invited to this tree | Recently deceased people |
| Extended | Invited people from linked trees, such as in-laws and distant cousins | Nobody by default; chosen per page |
| Public | Anyone with the link; may be linked from other systems | People who died long ago |

| Role | Can do |
| --- | --- |
| Owner | Everything, including membership and visibility rules |
| Editor | Edit directly and review others' proposals |
| Contributor | Propose edits and add entries; an editor accepts them |
| Viewer | Read what their circle allows |

## Decided by the brief

- Private family information must not end up in public places.
- Trust expands in circles: viewing or editing rights for a family can be granted to specific people.
- Pages about people who have died can be shared more widely than pages about the living.
- Pages about people from long ago can be linked from other systems.

## Proposed

- **A person is treated as living** unless a death is recorded or the birth was more than 100 years ago. The threshold is a per-tree setting.
- **Visibility belongs to the page**, with a tree-wide default. An editor can tighten or loosen a single page.
- **Photos inherit the strictest level** of the people tagged in them.
- **A private person still appears as a placeholder** ("living relative") in wider views, so the tree's shape is intact.
- **Public pages link outward** to matching profiles on shared trees such as WikiTree and FamilySearch, rather than copying data in.

## Open: enforcing this on git

Anyone who can clone a git repository gets every file and all of its history. Git has no per-file read permission. Three ways to reconcile that with per-page visibility:

| Approach | How it works | Cost |
| --- | --- | --- |
| Server in front | Only the server holds the repository; readers get rendered pages filtered by their access | No offline clone for viewers; needs a running service |
| A repository per circle | Private, family and public content live in separate repositories | Moving a page between levels moves it between repositories; links cross boundaries |
| Encrypted files | One repository; restricted files encrypted to the keys of those allowed | Key management for non-technical relatives; revocation does not reach old clones |

With the store on GitHub, a server in front is the natural fit when sharing is designed: only the server and editors clone the repository, and readers see filtered, rendered pages. This no longer blocks other work.

## Also open

- Consent: does a living person get a say over their own page, and can they see it?
- What happens to a page's level automatically when a death is recorded.
- Legal obligations for data about living people, which vary by country.
- Whether an invited viewer can re-share, and how an invitation is revoked.
