# Privacy, sharing and trust

Not yet designed. This document describes the problem space: the situations sharing has
to handle, the kinds of tool Prosapia could become, and features that might be part of
an answer. It decides very little. The first decision is which tool Prosapia is, and
most of the rest follows from that.

Today a tree has members, invited by email and signed in with Google, with three roles.
Every member can read everything, and owners and editors can edit any page. Pages carry
no visibility field. One server serves one tree.

| Role   | Can do                                                      |
| ------ | ----------------------------------------------------------- |
| Owner  | Everything, including membership and Claude's help          |
| Editor | Edit any page directly; every edit is logged and reversible |
| Viewer | Read everything                                             |

## Decided by the brief

- Private family information must not end up in public places.
- Trust expands in circles: viewing or editing rights for a family can be granted to
  specific people.
- Pages about people who have died can be shared more widely than pages about the
  living.
- Pages about people from long ago can be linked from other systems.

## The situation

Several cousins join the Carew tree and start filling it in. At first they work on the
ancestors they share. Soon each of them is also adding people the others have no
particular interest in: their other set of grandparents, their spouse's family, their
children's in-laws. Some questions follow:

- **Whose page is it?** A member's own page is about them. Should they be the only one
  who can edit it, or have the last word on it?
- **Who looks after a branch?** The cousin who added their spouse's family knows it
  best. Should they be able to edit it, be told about changes, or approve them?
- **Shared ancestors are everyone's.** Two cousins may disagree about a
  great-grandfather. How is that resolved, and who decides?
- **What if a cousin wants their own tree?** For their other side of the family, or to
  carry on without the rest. Do they copy the shared ancestors, or refer to them?
- **What can be public?** Going back far enough, nothing in the tree is private, and
  publishing it may help other researchers. The living, and the recently dead, are
  different.

## Which tool?

Each of these is a reasonable thing to build, and each answers the questions above
differently.

1. **One extended family's tree.** One tree, one group of relatives who mostly know one
   another, and an owner who settles disputes. Sharing is about privacy and about
   stewardship within the family. This is what Prosapia is today.
2. **A service for many family trees.** Each family has its own tree, kept apart from
   the others, on one server. The new questions are the ones between trees: two trees
   that share ancestors, and members who belong to more than one.
3. **An open genealogy platform.** One shared record of who lived and how they were
   related, open to anyone, as FamilySearch and WikiTree are. Disputes are between
   strangers, so it needs policies, sources and moderation, not just permissions.

These can be steps along one path, but each later step adds work that an earlier one
does not need.

## How others do it

- **FamilySearch Family Tree** is one shared tree of the deceased that anyone with an
  account can edit. Living people are private to whoever entered them. It avoids
  duplicate ancestors, at the cost of edits by strangers.
- **WikiTree** is also one shared tree, with each profile looked after by its managers
  and a "trusted list" of people allowed further in. How much of a profile is visible
  depends on the privacy level its managers choose, with older profiles open.
- **Ancestry and MyHeritage** give each user their own tree and suggest matches between
  trees. Copies drift apart, and mistakes spread as people copy each other's trees.
- **Git** is the model of copies that can be merged: fork, change, and propose changes
  back. It merges by file. Genealogy has to decide first whether two records are the
  same person, which is why copied trees are so rarely merged back together.

## Features that could be part of an answer

None of these is decided. They are listed so that a decision can choose among them.

**Within one tree**

- **Stewards.** Each page has one or more stewards: whoever created it, or the person
  themselves for their own page. A steward is told about changes and can restore an
  earlier version. Other editors can still edit.
- **Edit policies per page.** Open to every editor, the default; changes reviewed by a
  steward before they show; or editable only by the steward, as might suit a living
  member's own page. "Optional review of edits" in the plan is one of these.
- **Trusted lists.** A steward names who else may edit, or see, a page or a branch.
- **Branches.** A member's part of the tree worked out from relationships (their
  ancestors, their spouse's ancestors, their descendants), so that policies and
  notifications can be set once for a branch instead of page by page.
- **Watchlists.** Follow a person or a branch and hear about changes. Already in the
  plan.
- **Visibility levels**, below.

**Between trees**

- **References into another tree.** A page in one tree names a person kept in another,
  such as `@carew:carew-howard-joseph-tbczm8`, and shows that person read-only and
  always current. The shared ancestors are kept in one place. This is closer to a git
  submodule than to a fork.
- **Proposed changes.** A member of one tree proposes a change to a person kept in
  another, and that tree's stewards accept or decline it, like a pull request. Pages are
  text with stable ids, so a proposed change is the same kind of diff the change history
  already shows.
- **Forking.** Copying a tree, or a branch of it, to start another. The nightly export
  already allows a complete copy with its history. A fork that later wants to merge back
  has to match people first, so forking suits leaving better than collaborating.
- **Matching and merging people.** Deciding that records in two trees are the same
  person, and combining them. "Merge two records" is in the plan for one tree. Across
  trees it is harder, and it is the problem that the other features try to avoid.

**Publishing**

- **A public, read-only view** of people who died long enough ago, linkable from other
  sites, perhaps with links out to their WikiTree or FamilySearch profiles.

How these features line up with the three kinds of tool:

<!-- prettier-ignore -->
| Feature | One family's tree | Many family trees | Open platform |
| --- | --- | --- | --- |
| Stewards, edit policies, trusted lists | Useful | Useful | Needed |
| Visibility levels | Needed | Needed | Needed |
| References into another tree | — | Central | Not needed: one tree |
| Proposed changes | Optional | Central | Needed |
| Forking | Exit only | Exit only | Exit only |
| Matching and merging people | Rare | Needed | Central |
| Public view of the long dead | Optional | Optional | The point |
| Moderation and dispute policy | The owner decides | Per tree | Needed |

## Visibility

A starting sketch, from before this document described the wider problem:

<!-- prettier-ignore -->
| Level | Who can read | Default for |
| --- | --- | --- |
| Private | The tree's editors only | Living people |
| Family | People invited to this tree | Recently deceased people |
| Extended | Invited people from linked trees, such as in-laws and distant cousins | Nobody by default; chosen per page |
| Public | Anyone with the link; may be linked from other systems | People who died long ago |

- **A person is treated as living** unless a death is recorded or the birth was more
  than 100 years ago. The threshold is a per-tree setting.
- **Visibility belongs to the page**, with a tree-wide default. An editor can tighten or
  loosen a single page.
- **Photos inherit the strictest level** of the people tagged in them.
- **A private person still appears as a placeholder** ("living relative") in wider
  views, so the tree's shape is intact.
- **Public pages link outward** to matching profiles on shared trees such as WikiTree
  and FamilySearch, rather than copying data in.

### Enforcing it

Only the server reads the database, so visibility is enforced in one place: the server
decides, for each signed-in member, which people and photos they may see, and shows a
placeholder for the rest. This was the hard problem when the store was a git repository
that anyone with access could copy whole. It is now an ordinary feature to build, and it
no longer blocks other work.

The nightly export needs the same care: an exported repository holds everything, so it
stays private to the tree's owners.

## Open questions

- Which tool is Prosapia: one family's tree, a service for many, or an open platform? Or
  one now, with room to become another later?
- Does a living person get a say over their own page, and can they always see it?
- What happens to a page's visibility automatically when a death is recorded?
- How are disagreements about shared ancestors settled: by the owner, by stewards, or by
  sources?
- What legal obligations apply to data about living people? They vary by country.
- Can an invited viewer re-share, and how is an invitation revoked?
