import 'dart:convert';
import 'dart:math';

import 'package:markdown/markdown.dart' as md;

import 'assist.dart';
import 'claude.dart';
import 'completion.dart';
import 'contradictions.dart';
import 'dates.dart';
import 'diff.dart';
import 'family.dart';
import 'index.dart';
import 'page_syntax.dart';
import 'store.dart';
import 'tree.dart';

/// Turns the tree into HTML pages. Nothing here is stored: every page is
/// computed from the repository and the index.
class Renderer {
  Renderer(this.tree, this.index, {this.viewer, this.editable = false});

  final Tree tree;
  final Index index;

  /// The signed-in member the page is for, when the tree requires sign-in.
  final Member? viewer;

  /// Whether the store keeps history and accepts edits.
  final bool editable;

  bool get _canEdit => editable && (viewer?.role.canEdit ?? false);

  static String esc(String? s) => htmlEscape.convert(s ?? '');

  /// A page of the site. A [wide] page has room for a column beside its
  /// text.
  String page(
    String title,
    String body, {
    String query = '',
    bool wide = false,
  }) =>
      '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title == tree.name ? esc(title) : "${esc(title)} · ${esc(tree.name)}"}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Sans+3:ital,wght@0,400;0,500;0,600;0,700;1,400&display=swap">
<link rel="stylesheet" href="/style.css">
</head>
<body>
<header>
  <a class="site" href="/">${esc(tree.name)}</a>
  <nav><a href="/people">People</a> <a href="/family">Family tree</a> <a href="/media">Photos</a> <a href="/research">Research</a>${editable ? ' <a href="/changes">Recent changes</a>' : ''}${_canEdit && viewer!.role == Role.owner ? ' <a href="/settings">Settings</a>' : ''}</nav>
  <form action="/search" class="search"><input type="search" name="q" autocomplete="off" value="${esc(query)}" placeholder="Search" aria-label="Search"></form>
  ${viewer == null ? '' : '<form class="account" method="post" action="/sign-out"><span title="${esc(viewer!.email)} · ${viewer!.role.name}">${esc(viewer!.name ?? viewer!.email)}</span> <button>Sign out</button></form>'}
</header>
<main${wide ? ' class="wide"' : ''}>
$body
</main>
<script type="module" src="/assets/search.js"></script>
<script type="module" src="/assets/times.js"></script>
</body>
</html>
''';

  /// A person's page address, readable: `/people/carew-howard-joseph-tbczm8`.
  /// Only the trailing id is relied on, so older addresses keep working.
  static String pathOf(Person p) => '/people/${p.directory}';

  /// A link to [id]'s page; with [nickname], named as the family knew them.
  String personLink(String id, {bool years = false, bool nickname = false}) {
    final p = tree.people[id];
    if (p == null) {
      final gone = tree.deleted[id];
      return gone == null
          ? '<span class="missing">unknown person ($id)</span>'
          : '<a class="deleted" href="/people/$id">${esc(gone.name)}</a> <span class="years">(page deleted)</span>';
    }
    final suffix = years && p.years.isNotEmpty
        ? ' <span class="years">(${p.years})</span>'
        : '';
    return '<a href="${pathOf(p)}">${esc(nickname ? p.displayName : p.name)}</a>$suffix';
  }

  // ------------------------------------------------------------------ home

  /// The first page: a welcome, the viewer's own place in the tree, the
  /// latest changes, and where to go next.
  String home(List<Change> recent) {
    final me = viewer;
    final first = me?.name?.split(' ').first;
    final person = me?.person == null ? null : tree.people[me!.person];
    final photos = tree.media.values.where((m) => !m.isBack).length;
    final sb = StringBuffer(
      '<h1>${esc(tree.name)}</h1>'
      '<p class="lead">${first == null ? 'Welcome' : 'Welcome, ${esc(first)}'}. '
      'This is the family\'s history, kept together by the family: '
      '<a href="/people">${tree.people.length} people</a> and '
      '<a href="/media">$photos photos and documents</a>.</p>',
    );
    if (person != null) {
      final photo = person.photo == null ? null : tree.media[person.photo];
      sb.write('<section class="start">');
      if (photo != null && photo.isImage) {
        sb.write(
          '<a href="${pathOf(person)}"><img src="/media/${photo.key}/display?w=240" alt=""></a>',
        );
      }
      sb.write(
        '<div><h2>${esc(person.displayName)}</h2>'
        '${person.years.isEmpty ? '' : '<p class="years">${person.years}</p>'}'
        '<p><a class="button primary" href="${pathOf(person)}">Go to your page</a>'
        '${_canEdit ? ' <a class="button" href="/people/${person.id}/memory">Add a memory</a>' : ''}</p>',
      );
      sb.write('</div></section>');
      final chart = family(person, embedded: true);
      if (chart.isNotEmpty) {
        sb.write(
          '<h2>Your family</h2>$chart'
          '<p class="meta">Choose anyone to see their family, or '
          '<a href="${pathOf(person)}/family">open your family tree</a>.</p>'
          '<script type="module" src="/assets/family.js"></script>',
        );
      }
    }
    sb.write(
      '<h2>Find your way around</h2><ul class="try">'
      '<li><a href="/people">Everyone in the tree</a>, grouped by family name. Or type a name in the search box at the top of any page.</li>'
      '<li><a href="/family">The family tree</a>: anyone with their parents, grandparents, children and grandchildren.</li>'
      '<li><a href="/media">Photos and documents</a>.</li>'
      '<li><a href="/research">Research</a>: where to look for more about the family.</li>'
      '${_canEdit ? '<li><a href="/help/writing">How to write a page</a>: an example, and answers to common questions.</li>' : ''}'
      '${_canEdit ? switch (correctionCount()) {
              0 => '',
              final n => '<li><a href="/corrections">${n == 1 ? 'One item' : '$n items'} to correct</a>: pages that disagree, or facts that cannot be right.</li>',
            } : ''}'
      '${_canEdit ? '<li>Anything can be corrected: choose Edit on a page. Every change is kept, so nothing can be lost.</li>' : ''}'
      '</ul>',
    );
    if (recent.isNotEmpty) {
      sb.write('<h2>Recent changes</h2><ul class="recent">');
      for (final c in recent) {
        final (items, summary) = _changeParts(c);
        sb.write(
          '<li>$summary <span class="meta">· $items · ${esc(c.by)}, '
          '<span class="when">${time(c.at)}</span></span></li>',
        );
      }
      sb.write('</ul><p><a href="/changes">All recent changes</a></p>');
    }
    return page(tree.name, sb.toString());
  }

  /// Everyone in the tree, grouped by family name.
  String people() {
    final groups = <String, List<Person>>{};
    final people = index.peopleByName().map((id) => tree.people[id]!).toList()
      ..sort((a, b) {
        final c = surnameOf(a).compareTo(surnameOf(b));
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    for (final p in people) {
      groups.putIfAbsent(surnameOf(p), () => []).add(p);
    }
    final sb = StringBuffer()
      ..write('<h1>People</h1>')
      ..write(
        '<p class="lead">${tree.people.length} people, grouped by family name.</p>',
      );
    if (tree.problems.isNotEmpty) {
      sb.write(
        '<details class="problems"><summary>${tree.problems.length} files could not be read</summary><ul>',
      );
      for (final problem in tree.problems) {
        sb.write('<li>${esc(problem)}</li>');
      }
      sb.write('</ul></details>');
    }
    sb.write('<div class="surnames">');
    groups.forEach((surname, people) {
      sb.write('<section><h2>${esc(surname)}</h2><ul>');
      for (final p in people) {
        sb.write('<li>${personLink(p.id, years: true, nickname: true)}</li>');
      }
      sb.write('</ul></section>');
    });
    sb.write('</div>');
    return page('People', sb.toString());
  }

  /// Where to look for more about the family: a short guide for a member
  /// who has not done genealogy research before.
  String research() {
    String link(String url, String name) =>
        '<a href="$url" target="_blank" rel="noopener">$name</a>';
    return page('Research', '''
<h1>Research</h1>
<p class="lead">Genealogy techniques and research resources.</p>
<div class="research">
<h2>How to start</h2>
<ul>
<li><strong>Start from someone already here.</strong> Pick a person with gaps and note what is known: dates, places, and the names of their parents, partner and children. A name alone finds thousands of people; a name with a place and a span of years finds a few.</li>
<li><strong>Work back one generation at a time,</strong> and be sure of each link before going further.</li>
<li><strong>Expect records to disagree.</strong> Names are spelled many ways, ages drift from one census to the next, and indexes have transcription errors. Search for variants, and look at the image of the original record, not just the index entry.</li>
<li><strong>Other people's online family trees copy each other's mistakes.</strong> Use them to find records, not as records.</li>
<li><strong>Write down where each fact came from,</strong> on the person's page: in a <code>Note:</code> line or in the story, such as “1920 census, Hartford, CT, on FamilySearch”.</li>
</ul>

<h2>Free</h2>
<p><strong>${link('https://www.familysearch.org', 'FamilySearch')}.</strong> The largest free collection: censuses, births, marriages, deaths, church and immigration records from around the world, many with images. Needs a free account. Its ${link('https://www.familysearch.org/en/wiki/', 'Research Wiki')} explains which records exist for a given place and time.</p>
<p><strong>US censuses.</strong> Taken every ten years and opened after 72, so 1790 to 1950 can be searched, free on FamilySearch. They list everyone in a household, with ages, birthplaces and often occupations.</p>
<p><strong>${link('https://www.findagrave.com', 'Find a Grave')} and ${link('https://billiongraves.com', 'BillionGraves')}.</strong> Cemetery records and photographs of headstones, gathered by volunteers. Often the quickest way to dates of birth and death, and to who is buried together.</p>
<p><strong>${link('https://chroniclingamerica.loc.gov', 'Chronicling America')}.</strong> The Library of Congress's historic American newspapers, searchable by name and place.</p>
<p><strong>${link('https://www.archives.gov/research/genealogy', 'US National Archives')} and ${link('https://www.statueofliberty.org/discover/passenger-ship-search/', 'Ellis Island passenger lists')}.</strong> Immigration, naturalization and military service records; ships' lists of arrivals in New York.</p>
<p><strong>${link('https://library-archives.canada.ca', 'Library and Archives Canada')} and ${link('https://www.freebmd.org.uk', 'FreeBMD')}.</strong> Canadian censuses, immigration and military records; an index of births, marriages and deaths in England and Wales from 1837.</p>
<p><strong>${link('https://archive.org', 'Internet Archive')} and ${link('https://books.google.com', 'Google Books')}.</strong> Old county histories, city directories, school yearbooks and published family histories.</p>
<p><strong>Your public library.</strong> Many libraries offer Ancestry Library Edition free at the library, and some offer HeritageQuest or newspaper archives from home with a library card. Ask before paying for anything.</p>

<h2>Paid</h2>
<p>Most offer a free trial: plan what to search for first, then subscribe for a month.</p>
<p><strong>${link('https://www.ancestry.com', 'Ancestry')}.</strong> The largest paid collection, strongest for the US and Britain. Its “hints” from other people's trees need checking like any other tree.</p>
<p><strong>${link('https://www.newspapers.com', 'Newspapers.com')} and ${link('https://www.genealogybank.com', 'GenealogyBank')}.</strong> Newspaper archives. Obituaries, wedding announcements and local news are often the richest sources for the last 150 years.</p>
<p><strong>${link('https://www.fold3.com', 'Fold3')}.</strong> US military records: service files, draft cards, pensions.</p>
<p><strong>${link('https://www.myheritage.com', 'MyHeritage')} and ${link('https://www.findmypast.com', 'Findmypast')}.</strong> Stronger for Europe, and for Britain and Ireland.</p>

<h2>Using an AI assistant</h2>
<p>Claude, ChatGPT and similar assistants are useful research partners, if you check their work.</p>
<p><strong>What works well.</strong> Asking where to look: “My great-grandfather was born about 1852 in Scranton, Pennsylvania, and died there in 1919. What records should I search, and where?” Explaining what you have found: old handwriting, abbreviations, occupations, and places that have since changed name. Reading a photo or scan of a record and transcribing it. With web search turned on, an assistant can also search open sites such as Find a Grave, Chronicling America and the Internet Archive for you.</p>
<p><strong>What it can't reach.</strong> Anything behind a paywall (Ancestry, Newspapers.com, Fold3) or a sign-in (FamilySearch), records that exist only as unindexed images, and anything still on paper or microfilm in an archive. For these, it can tell you where to look, but you have to look.</p>
<p><strong>What to be careful about.</strong> An assistant can state a plausible date or relationship with confidence and be wrong, and it easily mixes up two people with the same name. Ask it for a link to the record behind each fact, open it yourself, and cite the record, not the assistant. Leave out details of living relatives when you ask.</p>

</div>''');
  }

  /// The last word of a person's name, for grouping the list of people.
  // ---------------------------------------------------------------- family

  /// How many brothers and sisters show on each side of the person; more
  /// are counted, and reached through a parent.
  static const _siblingsShown = 4;

  /// How many of a child's children show under them.
  static const _grandchildrenShown = 6;

  /// [p]'s family tree, two generations each way. Choosing anyone in it
  /// centres it on them. A [fragment] is the chart alone, for the page's
  /// script to put in place of the one shown; an [embedded] one is the
  /// chart without its title, for another page to show.
  String family(Person p, {bool fragment = false, bool embedded = false}) {
    final h = Hourglass.of(p, tree, index);
    var count = 0;
    final named = <String>{};
    final unions = <Map<String, Object>>[];
    final couples = <List<String>>[];

    String plural(int n, String one, String many) =>
        '$n ${n == 1 ? one : many}';

    ({String key, String html}) card(
      String id, {
      String? hint,
      String? partner,
      bool center = false,
    }) {
      final person = tree.people[id]!;
      final key = 'k${count++}';
      // The same person shown twice moves as one only from the first.
      final moves = named.add(id)
          ? ' style="view-transition-name: f-${person.id}"'
          : '';
      final photo = person.photo == null ? null : tree.media[person.photo];
      final image = photo != null && photo.isImage
          ? '<img src="/media/${photo.key}/display?w=96" alt="" loading="lazy">'
          : '<span class="no-photo" aria-hidden="true"></span>';
      final href = center ? pathOf(person) : '${pathOf(person)}/family';
      final title = center
          ? 'Go to ${person.name}\'s page'
          : 'Centre the tree on ${person.name}';
      return (
        key: key,
        html:
            '<a class="card${center ? ' center' : ''}" href="$href" data-key="$key" title="${esc(title)}"$moves>'
            '$image<span class="who"><span class="name">${esc(person.displayName)}</span>'
            '${person.years.isEmpty ? '' : '<span class="years">${person.years}</span>'}'
            '${partner == null ? '' : '<span class="partner">&amp; ${esc(tree.people[partner]?.name)}</span>'}'
            '${hint == null ? '' : '<span class="hint">${esc(hint)}</span>'}'
            '</span></a>',
      );
    }

    String more(int n, String what, String? id) {
      final label = '+$n $what';
      final person = id == null ? null : tree.people[id];
      return person == null
          ? '<span class="more">$label</span>'
          : '<a class="more" href="${pathOf(person)}/family" title="Centre the tree on ${esc(person.name)}">$label</a>';
    }

    String? childrenHint(String id) {
      final n = index.childrenOf(id).length;
      return n == 0 ? null : plural(n, 'child', 'children');
    }

    // Grandparents and parents.
    final up = StringBuffer();
    final parentKeys = <String, String>{};
    for (final parent in h.parents) {
      final grand = [
        for (final g in parent.parents)
          card(g, hint: index.parentsOf(g).isEmpty ? null : 'parents ↑'),
      ];
      final aunts = index.siblingsOf(parent.id).length;
      final c = card(
        parent.id,
        hint: aunts == 0
            ? null
            : plural(aunts, 'brother or sister', 'brothers and sisters'),
      );
      parentKeys[parent.id] = c.key;
      if (grand.isNotEmpty) {
        unions.add({
          'p': [for (final g in grand) g.key],
          'c': [c.key],
        });
        if (grand.length == 2) couples.add([grand[0].key, grand[1].key]);
      }
      up.write(
        '<div class="anc">'
        '<div class="row">${grand.map((g) => g.html).join()}</div>'
        '${c.html}</div>',
      );
    }
    // Parents side by side who are a couple: the two the line comes down
    // from, or any others recorded as partners.
    final shownParents = parentKeys.keys.toList();
    for (var i = 0; i + 1 < shownParents.length; i++) {
      final a = shownParents[i], b = shownParents[i + 1];
      if ((h.descent.contains(a) && h.descent.contains(b)) ||
          index.partnersOf(a).contains(b)) {
        couples.add([parentKeys[a]!, parentKeys[b]!]);
      }
    }

    // The person, their partners, and their brothers and sisters.
    final me = card(p.id, center: true);
    final partnerCards = <String, ({String key, String html})>{};
    for (final id in h.partners) {
      partnerCards[id] = card(id);
      couples.add([me.key, partnerCards[id]!.key]);
    }
    final left = [for (final id in h.leftPartners) partnerCards[id]!];
    final right = [for (final id in h.rightPartners) partnerCards[id]!];
    final mother = h.parents.isEmpty ? null : h.parents.last.id;
    // Brothers and sisters, by the parents shown that they share: those
    // who share the couple come down from it with the person, and a half
    // brother or sister from the one parent they share.
    final siblingKeys = <String, List<String>>{};
    String sibling(String id) {
      final partners = index.partnersOf(id);
      final c = card(id, partner: partners.firstOrNull, hint: childrenHint(id));
      final theirs = index.parentsOf(id);
      final shared = h.descent.every(theirs.contains)
          ? h.descent
          : [
              for (final p in shownParents)
                if (theirs.contains(p)) p,
            ];
      siblingKeys.putIfAbsent(shared.join(' '), () => []).add(c.key);
      return c.html;
    }

    final olderShown = h.older.length > _siblingsShown
        ? h.older.sublist(h.older.length - _siblingsShown)
        : h.older;
    final youngerShown = h.younger.take(_siblingsShown).toList();
    final before = [
      if (olderShown.length < h.older.length)
        more(h.older.length - olderShown.length, 'older', mother),
      ...olderShown.map(sibling),
    ];
    final after = [
      ...youngerShown.map(sibling),
      if (youngerShown.length < h.younger.length)
        more(h.younger.length - youngerShown.length, 'younger', mother),
    ];
    if (h.descent.isNotEmpty) {
      unions.add({
        'p': [for (final id in h.descent) parentKeys[id]!],
        'c': [me.key, ...?siblingKeys.remove(h.descent.join(' '))],
      });
    }
    siblingKeys.forEach((shared, keys) {
      if (shared.isEmpty) return;
      unions.add({
        'p': [for (final id in shared.split(' ')) parentKeys[id]!],
        'c': keys,
      });
    });

    // Children and grandchildren. With children by more than one partner,
    // each family is named under it.
    final down = StringBuffer();
    final several = h.children.length > 1;
    for (final group in h.children) {
      final childKeys = <String>[];
      down.write('<div class="group">');
      for (final child in group.children) {
        final c = card(child.id, partner: child.partners.firstOrNull);
        childKeys.add(c.key);
        final shown = child.children.take(_grandchildrenShown);
        final grand = [for (final g in shown) card(g, hint: childrenHint(g))];
        if (grand.isNotEmpty) {
          unions.add({
            'p': [c.key],
            'c': [for (final g in grand) g.key],
          });
        }
        final hidden = child.children.length - grand.length;
        down.write(
          '<div class="desc">${c.html}'
          '${grand.isEmpty ? '' : '<div class="row">${grand.map((g) => g.html).join()}'
                    '${hidden > 0 ? more(hidden, 'more', child.id) : ''}</div>'}'
          '</div>',
        );
      }
      if (several) {
        final other = tree.people[group.other];
        final years = other == null ? '' : _coupleYears(p, other);
        down.write(
          '<p class="family-of">${other == null ? 'other parent not recorded' : 'with ${esc(other.name)}${years.isEmpty ? '' : ', $years'}'}</p>',
        );
      }
      down.write('</div>');
      final other = partnerCards[group.other]?.key;
      unions.add({
        'p': [me.key, ?other],
        'c': childKeys,
      });
    }

    final alone = h.size == 0;
    if (embedded && alone) return '';
    final chart = StringBuffer(
      '<section class="family-view${embedded ? ' embedded' : ''}" data-title="${esc('${p.name}\'s family')}">',
    );
    if (!embedded) {
      chart.write(
        '<div class="person-head"><div class="title"><div class="name">'
        '<h1>${esc(p.displayName)}\'s family</h1>'
        '${p.years.isEmpty ? '' : '<span class="lead">${p.years}</span>'}</div>'
        '<div class="actions"><a class="button" href="${pathOf(p)}">Go to ${esc(p.name)}\'s page</a></div>'
        '</div></div>',
      );
    }
    if (alone) {
      chart.write(
        '<p class="empty">No family is recorded for ${esc(p.name)} yet. '
        'Parents, partners, brothers and sisters, and children written on their page show here.</p>',
      );
    }
    chart.write(
      '<div class="family-scroll"><div class="family" '
      'data-unions="${esc(jsonEncode(unions))}" data-couples="${esc(jsonEncode(couples))}">'
      '${up.isEmpty ? '' : '<div class="gen up">$up</div>'}'
      '<div class="gen self"><div class="side before">${before.join()}</div>'
      '<div class="row couple">${left.map((c) => c.html).join()}${me.html}${right.map((c) => c.html).join()}</div>'
      '<div class="side after">${after.join()}</div></div>'
      '${down.isEmpty ? '' : '<div class="gen down">$down</div>'}'
      '</div></div>'
      '${alone || embedded ? '' : '<p class="meta">Choose anyone to centre the tree on them.</p>'}'
      '</section>',
    );
    if (fragment || embedded) return chart.toString();
    return page(
      '${p.name}\'s family',
      '$chart<script type="module" src="/assets/family.js"></script>',
      wide: true,
    );
  }

  // ----------------------------------------------------------------- guide

  /// An example page, for the writing guide. Its people are invented, and
  /// have no pages, so their names show as written.
  static const examplePage = '''Name: Margaret Ellen Hughes
Nickname: Peggy
Also known as: Margaret Ellen Price
Sex: female
Born: 14 March 1887, "Scranton, PA"
Died: about 1961, "Hartford, CT"
Parents: Thomas Hughes, Ann Price
Siblings: Owen Hughes
Married: Walter Price, 12 June 1910, place: "St. Luke's Church, Scranton, PA",
  source: Pennsylvania marriage records
Children: Ruth Price, John Price (adopted)
Occupation: teacher, 1905 to 1910, place: "Scranton, PA"
Residence: 1930, place: "Hartford, CT", source: 1930 census
Note: Her mother's family came from Wales.

Margaret grew up in Scranton, where her father kept a hardware store. She trained as a
teacher and taught at the Adams Avenue school until she married Walter Price in 1910.

## 1923: The move to Hartford

In [date: spring 1923] the family moved to [place: Hartford, CT], where Walter had found
work with an insurance company. *Peggy* never liked the winters there.
''';

  /// How to write a page: one whole example, then answers to the questions
  /// people ask while editing. Opened from the editor in its own tab.
  String writingGuide() {
    final example = Person.fromSource('p-example', 'example', examplePage);
    String q(String id, String question, String answer, [String? text]) =>
        '<section class="faq" id="$id"><h3><a href="#$id">$question</a></h3>'
        '<p>$answer</p>${text == null ? '' : '<pre><code>${esc(text)}</code></pre>'}</section>';
    return page('How to write a page', '''
<h1>How to write a page</h1>
<p class="lead">A page is plain text: facts first, one per line, then a blank line and the story. Here is a whole page, as you would type it and as it looks. Below are answers to common questions.</p>
<h2>An example</h2>
<div class="guide-example">
  <div><h3>What you type</h3><pre class="source"><code>${esc(examplePage)}</code></pre></div>
  <div><h3>How it looks</h3><div class="preview">${personArticle(example, preview: true)}</div></div>
</div>
<h2>Questions</h2>
${q('child', 'How do I add a child?', 'Add a <code>Children:</code> line, or add to the one there, with names separated by commas. Type <code>@</code> and part of a name to link someone who already has a page. A plain name is someone without a page yet; on the page it gets a button to give them one, which fills in what is known, such as both parents.', 'Children: @hughes-margaret-ellen-x2k9ab, Ruth Price')}
${q('parents', 'How do I add parents, or brothers and sisters?', 'The same way, with <code>Parents:</code> or <code>Siblings:</code>. A relationship only needs writing on one of the two pages; both show it.', 'Parents: Thomas Hughes, Ann Price\nSiblings: Owen Hughes')}
${q('marriage', 'How do I record a marriage, or a partner?', 'A <code>Married:</code> line gives the partner, the date and the place. For a couple with no marriage recorded, use <code>Partner:</code>. <code>Divorced:</code>, <code>Separated:</code> and <code>Engaged:</code> work like <code>Married:</code>.', 'Married: Walter Price, 12 June 1910, "Scranton, PA"\nPartner: Walter Price')}
${q('dates', 'What if I only roughly know when?', 'Write it as you would say it. These all work: <code>about 1925</code>, <code>spring 1925</code>, <code>June 1949</code>, <code>the 1880s</code>, <code>before 1900</code>, <code>between 1880 and 1885</code>, <code>14 March 1887</code>, <code>March 14, 1887</code>, and <code>1861?</code> for a year you are unsure of. A date the page cannot read is listed at the top of the page, so you can fix it.')}
${q('places', 'How do I write a place with a comma in it?', 'Put it in quotes, as in <code>"Hartford, CT"</code>. If you forget, Format and Publish add them when it is clear what you meant.', 'Born: 14 March 1887, "Scranton, PA"')}
${q('labels', 'How do I say which part is which?', 'Most of the time Prosapia can tell: a date reads as a date, and for <code>Born:</code>, <code>Died:</code> and the like the rest is the place. When it might be unclear, say what a part is with <code>date:</code>, <code>place:</code> or <code>source:</code>; then the parts can come in any order.', 'Occupation: teacher, 1905 to 1910, place: "Scranton, PA"')}
${q('source', 'How do I say where a fact came from?', 'Add a <code>source:</code> part: a record, a book, a letter, or who told you. It shows on the page as a small “source” mark.', 'Residence: 1930, place: "Hartford, CT", source: 1930 census')}
${q('names', 'How do I add a nickname, a maiden name or another spelling?', '<code>Nickname:</code> is what the family called them; it shows in quotes in their name. <code>Also known as:</code> is any other full name: a maiden or married name, a changed name, another spelling.', 'Nickname: Peggy\nAlso known as: Margaret Ellen Price')}
${q('adopted', 'What about adopted, step or foster relations?', 'Put the kind in parentheses after the name.', 'Children: John Price (adopted)\nParents: @hughes-thomas-3f8d1a (step)')}
${q('facts', 'Where do jobs, schools, military service or homes go?', 'Any label works, one fact per line: <code>Occupation:</code>, <code>Education:</code>, <code>Military:</code>, <code>Residence:</code>, <code>Religion:</code>, or whatever fits. Repeat a label for more than one. Each shows in the timeline when it has a date.', 'Occupation: teacher, 1905 to 1910\nEducation: "Scranton High School", 1904')}
${q('note', 'Where does something go that is not a fact?', 'A <code>Note:</code> line holds a short remark as written. Anything longer belongs in the story, below the facts.', "Note: Her mother's family came from Wales.")}
${q('story', 'How do I write the story?', 'Below the facts, after a blank line, write as you would anywhere: paragraphs separated by blank lines. Start a line with <code>##</code> for a section heading. <code>*Italics*</code>, <code>**bold**</code> and lists work too; the buttons above the editor add them.', '## 1923: The move to Hartford')}
${q('link', 'How do I mention a person in the story?', 'Type <code>@</code> and part of their name, and choose them. The page shows their name as a link.', 'She married @price-walter-7k2m9x in 1910.')}
${q('marks', 'What are [date: …] and [place: …]?', 'Marks for a date or a place in the story, so Prosapia reads them reliably. They show as ordinary text. The Date and Place buttons add them.', 'In [date: spring 1923] the family moved to [place: Hartford, CT].')}
${q('long', 'A fact is too long for one line.', 'Carry it on to the next line, indented by two spaces. Format does this for you.', 'Married: Walter Price, 12 June 1910, place: "St. Luke\'s Church, Scranton, PA",\n  source: Pennsylvania marriage records')}
${q('format', 'What does the Format button do?', 'It tidies the text the way Publish will save it: single spaces, quotes and labels where they make the meaning clear, and long lines wrapped. It never changes what the page says; a line it cannot be sure of is left as you wrote it.')}
${q('photos', 'How do I add photos?', 'Not in the text: choose <strong>Add photos</strong> on the person\'s page, or go to Photos. A photo names the people in it, and shows on each of their pages. To choose the one at the top of a page, open the photo and choose “Use as … main photo”.')}
${q('mistake', 'What if I make a mistake?', 'Nothing is lost. Every version of a page is kept: choose ⋯ then <strong>View changes</strong> on the page to see them, and restore any one. A deleted page can be brought back from its address.')}
${q('problems', 'What is the list of problems at the top of a page?', 'Lines Prosapia could not read, such as a date it does not understand or a fact without a label. The page still saves; the list says what to fix.')}
${q('claude', 'Can Claude help?', 'If your family has it switched on, <strong>Claude: Draft…</strong> above the editor writes or revises the story from the facts, or works in something new you give it. You see what it changed before anything is saved.')}
''');
  }

  /// The years of [a] and [b]'s marriage, as either page records it:
  /// `1985–1995`, `married 1985`, `until 1995`, or empty.
  String _coupleYears(Person a, Person b) {
    int? year(String kind) => [
      for (final (x, y) in [(a, b), (b, a)])
        for (final c in x.couples)
          if (c.partner?.id == y.id && c.kind.toLowerCase() == kind)
            c.event.date?.year,
    ].nonNulls.firstOrNull;
    final married = year('married'), ended = year('divorced');
    if (married != null && ended != null) return '$married–$ended';
    if (married != null) return 'married $married';
    if (ended != null) return 'until $ended';
    return '';
  }

  static String surnameOf(Person p) {
    return nameParts(p.name).surname ?? 'Other';
  }

  // ---------------------------------------------------------------- person

  /// A person's page: its title, then the story beside the facts. With an
  /// [editor], the editor takes the story's place and the title stays, as
  /// when editing an issue on GitHub.
  String person(Person p, {String? editor}) {
    final buttons = [
      if (_canEdit)
        '<a class="button primary edit" href="${pathOf(p)}?edit" data-edit="/people/${p.id}/edit?fragment">Edit</a>',
      if (_canEdit)
        '<a class="button" href="/people/${p.id}/memory" title="A story, a trip, something you remember about ${esc(p.name)}, added as its own section at the end of the page">Add a memory</a>',
      if (_canEdit)
        '<button type="button" class="button" data-research="/people/${p.id}/research" title="Claude suggests records to look for about ${esc(p.name)}, and where to find them. Nothing is saved.">Claude: Research</button>',
      '<a class="button" href="${pathOf(p)}/family" title="${esc(p.name)}\'s parents, grandparents, brothers and sisters, children and grandchildren">Family tree</a>',
    ];
    final more = [
      if (editable) '<a href="/people/${p.id}/history">View changes</a>',
      '<a href="/people/${p.id}/text">View text</a>',
      if (editable && viewer != null && viewer!.person != p.id)
        '<form method="post" action="/people/${p.id}/me"><button title="Make this your page: your home page and family tree start here">This is me</button></form>',
      if (_canEdit) '<a href="/people/${p.id}/delete">Delete page</a>',
    ];
    final actions = [
      ...buttons,
      if (more.isNotEmpty)
        '<details class="more"><summary class="button" aria-label="More actions" title="More actions">⋯</summary><div class="menu">${more.join()}</div></details>',
    ];
    final head = StringBuffer('<div class="person-head">');
    head.write(
      '<div class="title"><div class="name"><h1>${esc(p.displayName)}</h1>'
      '${p.years.isEmpty ? '' : '<span class="lead">${p.years}</span>'}</div>',
    );
    if (actions.isNotEmpty) {
      head.write(
        '<div class="actions"${editor == null ? '' : ' hidden'}>${actions.join()}</div>',
      );
    }
    head.write('</div>');
    head.write('</div>');
    final edited = editable && p.editedBy != null && p.editedAt != null
        ? '<p class="edited">Edited by ${esc(p.editedBy)} ${ago(p.editedAt!)} · <a href="/people/${p.id}/history">View changes</a></p>'
        : '';
    return page(
      editor == null ? p.displayName : 'Editing ${p.name}',
      '$head${editor == null && _canEdit ? '<section class="research-ideas" id="research" hidden aria-live="polite"></section>' : ''}'
      '${personArticle(p, editor: editor)}${editor == null ? edited : ''}'
      '${editor != null
          ? '<script type="module" src="/assets/editor.js"></script>'
          : _canEdit
          ? '<script type="module" src="/assets/page.js"></script>'
          : ''}',
      wide: true,
    );
  }

  /// The facts and the story of a person's page, below its title. Also
  /// used for the editor's preview, where [p] is the text being typed and
  /// not yet part of the tree; a [preview] leaves out photos and actions.
  /// An [editor] takes the story's place.
  String personArticle(Person p, {bool preview = false, String? editor}) {
    final sb = StringBuffer();
    final actions = _canEdit && !preview;
    sb.write(
      '<article class="person${editor == null ? '' : ' editing-on'}">'
      '${_infobox(p, actions: actions)}',
    );
    if (editor != null) {
      sb.write('<div class="editing">$editor</div></article>');
      return sb.toString();
    }
    sb.write('<div class="person-body">');
    if (_canEdit || !requiresViewer) {
      sb.write(_contradictions(p, actions: actions));
      for (final (items, what) in [
        (issuesOf(p), 'could not be read'),
        (checksOf(p), 'may be worth checking'),
      ]) {
        if (items.isEmpty) continue;
        sb.write(
          '<details class="issues"><summary>${items.length == 1 ? 'One thing' : '${items.length} things'} on this page $what</summary><ul>',
        );
        for (final item in items) {
          sb.write('<li>${esc(item)}</li>');
        }
        sb.write('</ul></details>');
      }
    }

    if (p.body.isNotEmpty) {
      sb.write('<div class="prose">${markdown(p.body)}</div>');
    } else {
      sb.write(
        '<p class="empty">Nothing has been written about ${esc(p.name)} yet.</p>',
      );
    }

    final (dated, undated) = _timeline(p);
    if (dated.isNotEmpty) {
      sb.write('<h2>Timeline</h2><table class="timeline">');
      for (final e in dated) {
        sb.write('<tr><th>${date(e.date)}</th><td>${e.html}</td></tr>');
      }
      sb.write('</table>');
    }
    if (undated.isNotEmpty) {
      sb.write('<h2>Also recorded</h2><ul>');
      for (final html in undated) {
        sb.write('<li>$html</li>');
      }
      sb.write('</ul>');
    }

    final media = preview
        ? const <Media>[]
        : [
            for (final key in index.mediaOf(p.id))
              if (!tree.media[key]!.isBack) tree.media[key]!,
          ];
    final adding = actions
        ? '<a class="button add-photos" href="/media/add?person=${p.id}">Add photos</a>'
        : '';
    if (media.isNotEmpty || adding.isNotEmpty) {
      sb.write(
        '<h2 class="with-action"><span>Photos and documents${media.isEmpty ? '' : ' <span class="years">(${media.length})</span>'}</span>$adding</h2>'
        '${media.isEmpty ? '<p class="empty">No photos or documents name ${esc(p.name)} yet.</p>' : strip(media)}',
      );
    }
    sb.write('</div></article>');
    return sb.toString();
  }

  /// Whether pages are only for signed-in members (otherwise the tree is a
  /// local set of files, and its reader is its editor).
  bool get requiresViewer => viewer != null;

  /// Everything on [p]'s page that could not be read, including references
  /// to people who are not in the tree.
  List<String> issuesOf(Person p) => [
    ...p.issues,
    for (final r in [...p.parents, ...p.children, ...p.siblings, ...p.partners])
      if (r.id != null && !tree.people.containsKey(r.id))
        'No one in the tree has the id ${r.id}.',
    for (final c in p.couples)
      if (c.partner?.id != null && !tree.people.containsKey(c.partner!.id))
        'No one in the tree has the id ${c.partner!.id}.',
    for (final m in proseRef.allMatches(p.body))
      if (!tree.people.containsKey('p-${m[1]!.split('-').last}'))
        'No one in the tree matches @${m[1]}.',
  ];

  /// Dates that look unlikely. These are questions, never errors: real
  /// records are messy, and the editor may know better.
  List<String> checksOf(Person p) {
    int? year(Event? e) => e?.date?.understood == true ? e!.date!.year : null;
    final born = year(p.born), died = year(p.died), buried = year(p.buried);
    final now = DateTime.now().year;
    return [
      if (born != null && born > now) 'Born in $born, which is in the future.',
      if (born != null && died != null && died < born)
        'Died in $died, before being born in $born.',
      if (died != null && buried != null && buried < died)
        'Buried in $buried, before dying in $died.',
      if (born != null && died != null && died - born > 110)
        'Lived ${died - born} years.',
      for (final id in index.parentsOf(p.id))
        ...() {
          final parent = tree.people[id]!;
          final pb = year(parent.born), pd = year(parent.died);
          return [
            if (born != null && pb != null && born - pb < 12)
              '${parent.name} was ${born - pb} when ${p.name} was born.',
            if (born != null && pb != null && born - pb > 60)
              '${parent.name} was ${born - pb} when ${p.name} was born.',
            if (born != null && pd != null && born > pd + 1)
              'Born in $born, after ${parent.name} died in $pd.',
          ];
        }(),
      for (final c in p.couples)
        if (born != null && year(c.event) != null && year(c.event)! - born < 14)
          '${c.kind} in ${year(c.event)}, at about ${year(c.event)! - born}.',
      // A marriage after one of the two had died.
      for (final c in p.couples)
        if (c.kind.toLowerCase() == 'married' && year(c.event) != null)
          ...() {
            final when = year(c.event)!;
            final partner = tree.people[c.partner?.id];
            final theirs = year(partner?.died);
            return [
              if (died != null && when > died)
                'Married in $when, after dying in $died.',
              if (partner != null && theirs != null && when > theirs)
                'Married ${partner.name} in $when, after ${partner.name} died in $theirs.',
            ];
          }(),
    ];
  }

  /// Contradictions between [p]'s page and others, each with a way to
  /// resolve it by removing one side.
  String _contradictions(Person p, {required bool actions}) {
    final found = contradictionsOf(tree, p);
    if (found.isEmpty) return '';
    final sb = StringBuffer(
      '<details class="issues contradictions" open><summary>${found.length == 1 ? 'One thing' : '${found.length} things'} on this page contradict${found.length == 1 ? 's' : ''} ${found.length == 1 ? 'another statement' : 'other statements'}</summary><ul>',
    );
    for (final c in found) {
      sb.write('<li>${esc(c.message)}');
      final link = c.link;
      if (actions && link != null) {
        final target = tree.people[link.target];
        sb.write(
          '<div class="resolve"><form method="post" action="/people/${link.page}/link">'
          '<input type="hidden" name="kind" value="${esc(link.kind)}">'
          '<input type="hidden" name="name" value="${esc(link.name)}">'
          '<input type="hidden" name="target" value="${link.target}">'
          '<input type="hidden" name="based_on" value="${(link.page == p.id ? p : tree.people[link.page])?.revision}">'
          '<button>Link “${esc(link.name)}” to ${esc(target?.name)}\'s page</button></form></div>',
        );
      } else if (actions) {
        sb.write('<div class="resolve">');
        for (final s in c.statements) {
          final page = s.page == p.id ? p : tree.people[s.page];
          if (page == null) continue;
          final other = tree.people[s.other]?.name ?? s.other;
          final where = s.page == p.id ? 'this page' : '${page.name}\'s page';
          sb.write(
            '<form method="post" action="/people/${p.id}/resolve">'
            '<input type="hidden" name="page" value="${s.page}">'
            '<input type="hidden" name="kind" value="${esc(s.kind)}">'
            '<input type="hidden" name="other" value="${s.other}">'
            '<input type="hidden" name="based_on" value="${page.revision}">'
            '<button>Remove ${esc(other)} from the ${esc(s.label)} line on ${esc(where)}</button></form>',
          );
        }
        sb.write('</div>');
      }
      sb.write('</li>');
    }
    sb.write('</ul></details>');
    return sb.toString();
  }

  /// Where [e] comes from, as small marks with the source on hover.
  String cite(Event e) => [
    for (final source in e.sources)
      ' <span class="cite" title="${esc(source)}" tabindex="0">source</span>',
  ].join();

  /// A date as typed, with how it was read shown on hover.
  String date(TreeDate d) => d.understood
      ? '<span class="date" title="Read as: ${esc(d.meaning)}">${esc(d.display)}</span>'
      : '<span class="unresolved" title="Not read as a date">${esc(d.display)}</span>';

  /// A person named in a fact line: linked when they have a page.
  String ref(PersonRef r, {bool years = false}) {
    final q = r.qualifier == null
        ? ''
        : ' <span class="years">(${esc(r.qualifier)})</span>';
    if (r.id != null) {
      if (tree.people.containsKey(r.id)) {
        return personLink(r.id!, years: years) + q;
      }
      return '<span class="unresolved" title="No one in the tree has this id">${esc(r.id)}</span>$q';
    }
    return '<span class="named" title="No page yet">${esc(r.name)}</span>$q';
  }

  /// The marriage of [a] and [b], stated on either page.
  CoupleEvent? marriageOf(String a, String b) {
    for (final (who, other) in [(a, b), (b, a)]) {
      final p = tree.people[who];
      if (p == null) continue;
      for (final c in p.couples) {
        if (c.partner?.id == other && c.kind.toLowerCase() == 'married') {
          return c;
        }
      }
    }
    return null;
  }

  /// A plain name, with an action to give them a page when [from] is
  /// given: the page whose [kind] line names them.
  String _named(PersonRef r, {String? from, String? kind, bool years = false}) {
    final html = ref(r, years: years);
    if (from == null || kind == null || r.name == null) return html;
    final query = Uri(queryParameters: {'kind': kind, 'name': r.name!}).query;
    return '$html <a class="add" href="/people/$from/add?${esc(query)}" title="Create a page for ${esc(r.name)}">+ page</a>';
  }

  String _infobox(Person p, {bool actions = false}) {
    final rows = <(String, String)>[];
    // An editor can add a relative from a relationship's row, shown even
    // while it is empty.
    void row(String label, Iterable<String> items, {String? add}) {
      final html = items.where((x) => x.isNotEmpty).join('<br>');
      final link = add == null || !actions || !_canEdit
          ? ''
          : '<a class="add-relative" href="/people/${p.id}/relative?kind=${add.split(' ').first}">+ ${add.split(' ').skip(1).join(' ')}</a>';
      if (html.isNotEmpty || link.isNotEmpty) {
        rows.add((label, [html, link].where((x) => x.isNotEmpty).join('<br>')));
      }
    }

    String event(Event? e) => e == null
        ? ''
        : [
                if (e.date != null) date(e.date!),
                if (e.place != null) esc(e.place),
              ].join('<br>') +
              cite(e);

    String qualified(String id, List<PersonRef> stated, {bool years = false}) {
      final q = stated
          .where((r) => r.id == id && r.qualifier != null)
          .firstOrNull
          ?.qualifier;
      return personLink(id, years: years) +
          (q == null ? '' : ' <span class="years">(${esc(q)})</span>');
    }

    Iterable<String> named(
      List<PersonRef> refs,
      String kind, {
      bool years = false,
      String? from,
    }) => [
      for (final r in refs)
        if (r.id == null || !tree.people.containsKey(r.id))
          _named(
            r,
            from: actions ? (from ?? p.id) : null,
            kind: kind,
            years: years,
          ),
    ];

    if (p.alsoKnownAs.isNotEmpty) {
      row('Also known as', [esc(p.alsoKnownAs.join(', '))]);
    }
    row('Born', [event(p.born)]);
    row('Christened', [event(p.christened)]);
    row('Died', [event(p.died)]);
    row('Buried', [event(p.buried)]);
    final parents = [
      for (final id in index.parentsOf(p.id)) qualified(id, p.parents),
      ...named(p.parents, 'parents'),
    ];
    row(
      'Parents',
      parents,
      add: parents.length < 2 ? 'parents add a parent' : null,
    );
    final partners = [
      for (final id in index.partnersOf(p.id))
        personLink(id) +
            switch (marriageOf(p.id, id)?.event.date?.year) {
              null => '',
              final year => ' <span class="years">(married $year)</span>',
            },
      ...named(p.partners, 'partner'),
      for (final c in p.couples)
        if (c.partner != null && c.partner!.id == null)
          _named(
            c.partner!,
            from: actions ? p.id : null,
            kind: c.kind.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
          ),
    ];
    row(
      'Partners',
      partners,
      add: partners.isEmpty ? 'partner add a partner' : null,
    );
    row('Children', [
      for (final id in index.childrenOf(p.id))
        qualified(id, const [], years: true),
      ...named(p.children, 'children'),
    ], add: 'children add a child');
    // Children named on a parent's page without a page of their own are
    // siblings too.
    final siblingNames = <String>{};
    row('Siblings', [
      for (final id in index.siblingsOf(p.id)) personLink(id, years: true),
      ...named(p.siblings, 'siblings'),
      for (final parent in index.parentsOf(p.id))
        for (final r in tree.people[parent]!.children)
          if (r.id == null &&
              !p.siblings.any((s) => s.name == r.name) &&
              siblingNames.add(r.name!))
            ...named([r], 'children', from: parent),
    ]);

    final photo = p.photo == null ? null : tree.media[p.photo];
    if (rows.isEmpty && photo == null) return '';
    final sb = StringBuffer('<aside class="infobox">');
    if (photo != null && photo.isImage) {
      sb.write(
        '<a href="/media/${photo.key}"><img src="/media/${photo.key}/display?w=480" alt="${esc(photo.title ?? p.name)}"></a>',
      );
    }
    sb.write('<table>');
    for (final (label, html) in rows) {
      sb.write('<tr><th>$label</th><td>$html</td></tr>');
    }
    sb.write('</table></aside>');
    return sb.toString();
  }

  /// A life in order: life events, other facts, marriages, children's
  /// births, and dated headings from the prose. Facts with no date, and
  /// notes, are returned separately.
  (List<({TreeDate date, String html})>, List<String>) _timeline(Person p) {
    final dated = <({TreeDate date, String html})>[];
    final undated = <String>[];
    void add(TreeDate? date, String html) => date == null || !date.understood
        ? undated.add(date == null ? html : '$html, ${this.date(date)}')
        : dated.add((date: date, html: html));
    String at(Event e) =>
        '${e.place == null ? '' : ' <span class="place">${esc(e.place)}</span>'}'
        '${cite(e)}';

    if (p.born?.date != null) add(p.born!.date, 'Born${at(p.born!)}');
    if (p.christened != null) {
      add(p.christened!.date, 'Christened${at(p.christened!)}');
    }
    for (final f in p.facts) {
      final people = f.people.map(ref).join(', ');
      add(
        f.event.date,
        '<span class="kind">${esc(f.label)}</span> ${esc(f.description)}'
        '${people.isEmpty ? '' : ' with $people'}${at(f.event)}',
      );
    }
    // Couple events stated on this page, and on partners' pages about this
    // person.
    final couples = <(CoupleEvent, PersonRef?)>[
      for (final c in p.couples) (c, c.partner),
      for (final other in tree.people.values)
        if (other.id != p.id)
          for (final c in other.couples)
            if (c.partner?.id == p.id) (c, PersonRef.page(other.id)),
    ];
    // The same event stated on both pages is shown once.
    final seen = <String>{};
    for (final (c, partner) in couples) {
      final key =
          '${c.kind.toLowerCase()}|${partner?.id ?? partner?.name}|${c.event.date?.sortKey}';
      if (!seen.add(key)) continue;
      add(
        c.event.date,
        '${esc(c.kind)}${partner == null ? '' : ' ${ref(partner)}'}${at(c.event)}',
      );
    }
    for (final id in index.childrenOf(p.id)) {
      final child = tree.people[id]!;
      if (child.born?.date != null) {
        add(child.born!.date, 'Birth of ${personLink(id)}');
      }
    }
    for (final m in RegExp(
      r'^##\s+(.+?)\s*[:–-]\s*(.+)$',
      multiLine: true,
    ).allMatches(p.body)) {
      final d = TreeDate.parse(m[1]!);
      if (d.understood) add(d, esc(m[2]));
    }
    if (p.died?.date != null) add(p.died!.date, 'Died${at(p.died!)}');
    if (p.buried != null) add(p.buried!.date, 'Buried${at(p.buried!)}');
    for (final note in p.notes) {
      undated.add('<span class="kind">Note</span> ${esc(note)}');
    }

    // A stable sort keeps birth first and death last among equal dates.
    final sorted = [for (final (i, e) in dated.indexed) (i, e)]
      ..sort((a, b) {
        final c = a.$2.date.sortKey.compareTo(b.$2.date.sortKey);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return ([for (final (_, e) in sorted) e], undated);
  }

  /// Renders page prose: `@` references become links to people, and
  /// `[date: …]` and `[place: …]` are marked for display.
  String markdown(String source) {
    final marked = source
        .replaceAllMapped(proseRef, (m) {
          final id = 'p-${m[1]!.split('-').last}';
          final person = tree.people[id];
          return person == null
              ? '<span class="unresolved" title="No one in the tree matches this">@${m[1]}</span>'
              : '<a href="${pathOf(person)}">${esc(person.name)}</a>';
        })
        .replaceAllMapped(proseMarked, (m) {
          if (m[1]!.toLowerCase() == 'date') return date(TreeDate.parse(m[2]!));
          return '<span class="place-ref">${esc(m[2])}</span>';
        });
    final html = md.markdownToHtml(
      marked,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    // Links written as relative file paths in older pages still work.
    return html
        .replaceAllMapped(
          RegExp(r'href="[^"]*?([a-z0-9]{6})/index\.md"'),
          (m) => 'href="/people/p-${m[1]}"',
        )
        .replaceAllMapped(
          RegExp(r'src="[^"]*?media/(m-[a-z0-9]+(?:-back)?)\.\w+"'),
          (m) => 'src="/media/${m[1]}/display?w=960"',
        );
  }

  // ----------------------------------------------------------------- media

  /// Photos and documents as a grid of thumbnails, each linking to its page.
  String gallery(Iterable<Media> items) =>
      '<div class="gallery">${items.map(_thumbnail).join()}</div>';

  /// Photos and documents in one row that scrolls sideways, for a page that
  /// may have many. The row keeps its place when the reader comes back.
  String strip(Iterable<Media> items) =>
      // Many photos take two or three rows, so the row is not too long.
      '<div class="strip rows-${items.length <= 6
          ? 1
          : items.length <= 16
          ? 2
          : 3}">'
      '<button type="button" class="prev" aria-label="Earlier" hidden>‹</button>'
      '<div class="gallery">${items.map(_thumbnail).join()}</div>'
      '<button type="button" class="next" aria-label="Later" hidden>›</button>'
      '</div>'
      '<script type="module" src="/assets/strip.js"></script>';

  String _thumbnail(Media m) {
    final caption = esc(m.title ?? 'Untitled');
    return '<a href="/media/${m.key}" title="$caption">'
        '${m.isImage
            ? '<img loading="lazy" src="/media/${m.key}/display?w=240" alt="$caption">'
            : m.isDocument
            ? '<span class="doc"><img loading="lazy" src="/media/${m.key}/display?w=240" alt="$caption"><span class="badge">${m.extension.toUpperCase()}</span></span>'
            : '<span class="file">${m.extension.toUpperCase()}</span>'}'
        '<span class="caption">$caption</span></a>';
  }

  /// A file size for people: `26.7 MB`.
  static String _megabytes(int bytes) => bytes >= 1000 * 1000
      ? '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB'
      : '${(bytes / 1000).ceil()} kB';

  /// How many photos the Photos page shows at a time: three rows of five.
  static const photosPerPage = 15;

  /// One page of every photo and document.
  String mediaIndex({int pageNumber = 1}) {
    final fronts = tree.media.values.where((m) => !m.isBack).toList();
    final pages = max(1, (fronts.length / photosPerPage).ceil());
    final n = pageNumber.clamp(1, pages);
    final shown = fronts.skip((n - 1) * photosPerPage).take(photosPerPage);
    return page(
      n == 1 ? 'Photos' : 'Photos, page $n',
      '<h1>Photos and documents</h1>'
      '${_canEdit ? '<p class="actions"><a href="/media/add">Add photos</a></p>' : ''}'
      '<p class="lead">${fronts.length} files. Titles and names are read from each file\'s embedded metadata.</p>'
      '${gallery(shown)}${_pager(n, pages, (i) => i == 1 ? '/media' : '/media?page=$i')}',
    );
  }

  /// Links to the other pages of a list: Previous, the page numbers
  /// (with gaps far from [current]), and Next.
  String _pager(int current, int pages, String Function(int) href) {
    if (pages < 2) return '';
    final sb = StringBuffer('<nav class="pager" aria-label="Pages">');
    sb.write(
      current > 1
          ? '<a href="${href(current - 1)}" rel="prev">‹ Previous</a>'
          : '<span class="off">‹ Previous</span>',
    );
    var gap = false;
    for (var i = 1; i <= pages; i++) {
      if (i == 1 || i == pages || (i - current).abs() <= 2) {
        gap = false;
        sb.write(
          i == current
              ? '<span aria-current="page">$i</span>'
              : '<a href="${href(i)}">$i</a>',
        );
      } else if (!gap) {
        gap = true;
        sb.write('<span class="gap">…</span>');
      }
    }
    sb.write(
      current < pages
          ? '<a href="${href(current + 1)}" rel="next">Next ›</a>'
          : '<span class="off">Next ›</span>',
    );
    sb.write('</nav>');
    return sb.toString();
  }

  /// A photo, with its back beside it when it has one, what is known about
  /// it, and the others added with it.
  String media(Media m) {
    final front = m.isBack ? tree.media[m.id] ?? m : m;
    final back = tree.media['${front.id}-back'];
    final sb = StringBuffer('<article class="media">');
    if (_canEdit && !front.isBack) {
      sb.write(
        '<p class="actions"><a href="/media/${front.key}/edit">Edit details</a> · <a href="/media/${front.key}/delete">Delete</a></p>',
      );
    }
    sb.write('<h1>${esc(front.title ?? 'Untitled')}</h1>');
    final facts = [
      if (front.date != null) date(TreeDate.parse(front.date!)),
      if (front.place != null)
        '<span class="place-ref">${esc(front.place)}</span>',
    ];
    if (facts.isNotEmpty) sb.write('<p class="lead">${facts.join(' · ')}</p>');
    String image(Media x, String label) => x.isImage
        ? '<figure><a href="/media/${x.key}/file"><img src="/media/${x.key}/display?w=1920" alt="${esc(front.title ?? '')}, $label"></a>${back == null ? '' : '<figcaption>$label</figcaption>'}</figure>'
        : x.isDocument
        ? '<figure class="document"><a href="/media/${x.key}/file"><img src="/media/${x.key}/display?w=960" alt="${esc(front.title ?? '')}, first page"></a>'
              '<figcaption><a class="button primary" href="/media/${x.key}/file">Open the ${x.extension.toUpperCase()}</a>${x.size == null ? '' : ' <span class="years">${_megabytes(x.size!)}</span>'}</figcaption></figure>'
        : '<p><a class="file" href="/media/${x.key}/file">Open the ${x.extension.toUpperCase()} file</a></p>';
    sb.write(
      '<div class="sides${back == null ? '' : ' two'}">${image(front, 'Front')}${back == null ? '' : image(back, 'Back')}</div>',
    );
    final writing = front.transcription ?? back?.transcription;
    if (writing != null) {
      sb.write('<h2>${_writtenOn(front, back)}</h2>${_longText(writing)}');
    }
    if (front.notes != null) {
      sb.write('<h2>Notes</h2>${_longText(front.notes!)}');
    }
    if (_canEdit && writing == null && front.notes == null) {
      sb.write(
        '<p><a href="/media/${front.key}/edit#transcription">Add a transcription or notes</a></p>',
      );
    }
    if (front.people.isNotEmpty) {
      sb.write(
        '<h2>${front.isDocument ? 'People named' : 'People shown'}</h2><ul class="shown">',
      );
      for (final id in front.people) {
        final person = tree.people[id];
        final main =
            _canEdit &&
                person != null &&
                person.photo != front.key &&
                front.isImage
            ? ' <form method="post" action="/media/${front.key}/main"><input type="hidden" name="person" value="$id"><button>Use as ${esc(person.name)}\'s main photo</button></form>'
            : '';
        sb.write('<li>${personLink(id, years: true)}$main</li>');
      }
      sb.write('</ul>');
    }
    if (front.set != null) {
      final set =
          tree.media.values
              .where(
                (x) => x.set == front.set && !x.isBack && x.key != front.key,
              )
              .toList()
            ..sort((a, b) => (a.setIndex ?? 0).compareTo(b.setIndex ?? 0));
      if (set.isNotEmpty) {
        sb.write('<h2>Added with it</h2>${strip(set)}');
      }
    }
    sb.write(
      '<p class="meta">${front.key}.${front.extension}${front.width == null ? '' : ' · ${front.width} × ${front.height}'} · <a href="/media/${front.key}/file">original file</a>${back == null ? '' : ' · <a href="/media/${back.key}/file">back</a>'}</p>',
    );
    sb.write('</article>');
    return page(front.title ?? 'Untitled', sb.toString());
  }

  /// What a transcription is called for [m]: the writing on the back of a
  /// photo that has one, or on the photo or document itself.
  static String _writtenOn(Media m, Media? back) => back != null
      ? 'Written on the back'
      : m.isDocument
      ? 'Transcription'
      : 'Written on it';

  /// Text as written, with its line breaks. A long text shows its start,
  /// with the rest a click away.
  static String _longText(String text) {
    final lines = text.split('\n');
    var cut = 0, length = 0;
    while (cut < lines.length && cut < 15 && length < 1200) {
      length += lines[cut++].length;
    }
    if (lines.length - cut < 3) {
      return '<p class="description">${esc(text)}</p>';
    }
    return '<p class="description">${esc(lines.take(cut).join('\n'))}</p>'
        '<details class="rest"><summary>Show the rest</summary>'
        '<p class="description">${esc(lines.skip(cut).join('\n'))}</p></details>';
  }

  /// The form for adding photos, from [person]'s page when given. The
  /// browser code in photos.ts uploads each file as it is chosen.
  String addPhotos(Person? person, {required bool help}) =>
      page(person == null ? 'Add photos' : 'Add photos of ${person.name}', '''
<h1>Add photos${person == null ? '' : ' of ${esc(person.name)}'}</h1>
<p class="lead">Choose one photo or several, or documents as PDFs. Then say what you know about each: a caption, when and where, and who is in it.</p>
<form class="memory add-photos" data-person="${person?.id ?? ''}" data-help="$help" data-people="${esc(jsonEncode([
        if (person != null) {'id': person.id, 'name': person.name},
      ]))}">
  <label for="files">Photos and documents</label>
  <input id="files" type="file" multiple accept="image/jpeg,image/heic,image/png,image/tiff,application/pdf,.heic,.tif,.tiff,.pdf">
  <div class="photo-list"></div>
  <p class="message" role="alert" hidden></p>
  <div class="save"><button class="primary" disabled>Add the photos</button> <a href="${person == null ? '/media' : '/people/${person.id}'}">Cancel</a></div>
</form>
<script type="module" src="/assets/photos.js"></script>''');

  /// The form for changing what is known about a photo.
  String editPhoto(Media m, {required bool help}) {
    final back = tree.media['${m.id}-back'];
    final people = [
      for (final id in m.people)
        if (tree.people[id] case final p?) {'id': p.id, 'name': p.name},
    ];
    return page('Edit ${m.title ?? 'a photo'}', '''
<h1>Edit: ${esc(m.title ?? 'Untitled')}</h1>
<p class="lead">These details are written into the photo file itself, so a copy that leaves Prosapia still carries them.</p>
<form class="memory edit-photo" method="post" action="/media/${m.key}/edit" data-help="$help">
  ${m.isImage || m.isDocument ? '<img class="thumb large" src="/media/${m.key}/display?w=960" alt="">' : ''}
  <label for="title">Caption</label>
  <input id="title" name="title" value="${esc(m.title ?? '')}" maxlength="200">
  <label for="date">When</label>
  <input id="date" name="date" value="${esc(m.date ?? '')}" maxlength="80" placeholder="about 1949">
  <label for="place">Where</label>
  <input id="place" name="place" value="${esc(m.place ?? '')}" maxlength="200">
  <label>${m.isDocument ? 'People it names' : 'Who is in it'}</label>
  <div class="people-picker" data-name="people" data-initial="${esc(jsonEncode(people))}"></div>
  <label for="transcription">${_writtenOn(m, back)}</label>
  ${back != null && back.isImage ? '<img class="thumb large" src="/media/${back.key}/display?w=960" alt="The back">' : ''}
  <textarea id="transcription" name="transcription" spellcheck="true"${m.isDocument ? ' class="tall"' : ''}>${esc(back?.transcription ?? m.transcription ?? '')}</textarea>
  ${help && (m.isImage || m.isDocument) ? '<div class="help tidy" data-key="${(back ?? m).key}"><button type="button" class="transcribe">Claude: Transcribe</button></div>' : ''}
  <label for="notes">Notes</label>
  <p class="hint">What is known about it, rather than written on it: who has the original, who scanned it, who identified the people.</p>
  <textarea id="notes" name="notes" spellcheck="true">${esc(m.notes ?? '')}</textarea>
  <div class="save"><button class="primary">Save</button> <a href="/media/${m.key}">Cancel</a></div>
</form>
<script type="module" src="/assets/photos.js"></script>''');
  }

  // ---------------------------------------------------------------- search

  String search(String query) {
    final results = index.search(query);
    final sb = StringBuffer('<h1>Search</h1>');
    if (query.trim().isEmpty) {
      sb.write(
        '<p class="lead">Type a name, a place or a word from a page.</p>',
      );
    } else if (results.isEmpty) {
      sb.write('<p class="lead">Nothing found for “${esc(query)}”.</p>');
    } else {
      sb.write(
        '<p class="lead">${results.length} results for “${esc(query)}”.</p><ul class="results">',
      );
      for (final r in results) {
        // The snippet is escaped, then the highlight marks are restored.
        final snippet = esc(r.snippet)
            .replaceAll('&lt;mark&gt;', '<mark>')
            .replaceAll('&lt;&#47;mark&gt;', '</mark>');
        final link = r.kind == 'person'
            ? personLink(r.id, years: true)
            : '<a href="/media/${r.id}">${esc(tree.media[r.id]?.title ?? 'Untitled')}</a> <span class="years">(${tree.media[r.id]?.isImage ?? false ? 'photo' : 'document'})</span>';
        sb.write(
          '<li>$link${snippet.trim().isEmpty ? '' : '<div class="snippet">$snippet</div>'}</li>',
        );
      }
      sb.write('</ul>');
    }
    return page('Search', sb.toString(), query: query);
  }

  // --------------------------------------------------------------- editing

  /// The editor: the page's text on the left, a live preview on the right.
  ///
  /// [conflict] is shown when someone else saved first; it describes their
  /// change so this editor can reapply their own on top of it.
  /// The editor for [p]'s page, which takes the place of the page's content
  /// while editing. [inPlace] marks one opened from the page itself, whose
  /// script starts and stops it.
  String editorForm(
    Person p, {
    required String source,
    required int basedOn,
    bool help = false,
    String? helpOff,
    String? helpedBy,
    bool inPlace = false,
  }) =>
      '''
<form class="editor" method="post" action="/people/${p.id}/edit" data-preview="/people/${p.id}/preview"${inPlace ? ' data-in-place' : ''}>
  <input type="hidden" name="based_on" value="$basedOn">
  <input type="hidden" name="helped_by" value="${esc(helpedBy ?? '')}">
  <div class="tabs" role="tablist">
    <button type="button" role="tab" id="tab-write" aria-selected="true" aria-controls="panel-write">Write</button>
    <button type="button" role="tab" id="tab-preview" aria-selected="false" aria-controls="panel-preview">Preview</button>
    ${help
          ? '''<span class="help" data-url="/people/${p.id}/help">
      <button type="button" data-request="draft" title="Write the story, or work new information into it">Claude: Draft…</button>
    </span>'''
          : helpOff != null && viewer?.role == Role.owner
          ? '<span class="help off">${esc(helpOff)} <a href="/settings">Settings</a></span>'
          : ''}
  </div>
  <div class="help-bar" hidden role="status"></div>
  ${help ? _draftPanel : ''}
  <div class="tab-panel" id="panel-write" role="tabpanel" aria-labelledby="tab-write">
    <div class="format" role="toolbar" aria-label="Formatting">
      <button type="button" data-format="heading" title="Heading">H</button>
      <button type="button" data-format="bold" title="Bold"><b>B</b></button>
      <button type="button" data-format="italic" title="Italic"><i>I</i></button>
      <button type="button" data-format="list" title="List">List</button>
      <button type="button" data-format="link" title="Link">Link</button>
      <span class="sep"></span>
      <button type="button" data-format="person" title="Link a person: type @ and part of a name">@ Person</button>
      <button type="button" data-format="date" title="Mark a date">Date</button>
      <button type="button" data-format="place" title="Mark a place">Place</button>
      <span class="spacer"></span>
      <a class="guide-link" href="/help/writing" target="_blank" rel="noopener" title="A whole example page, and answers to common questions. Opens in a new tab.">Format example and editing FAQ…</a>
      <button type="button" data-tidy="/people/${p.id}/format" title="Tidy the text as it will be saved: spacing, quotes and line lengths">Format</button>
    </div>
    <textarea id="source" name="source" spellcheck="true" required aria-label="Page text">${esc(source)}</textarea>
  </div>
  <div class="tab-panel" id="panel-preview" role="tabpanel" aria-labelledby="tab-preview" hidden>
    <div id="preview" class="preview">${personArticle(p, preview: true)}</div>
  </div>
  <div class="save">
    <a class="button discard" href="${pathOf(p)}">Discard</a>
    <button class="primary" title="Publish (⌘ Enter)">Publish <kbd>⌘ ⏎</kbd></button>
  </div>
</form>
''';

  /// What "Claude: Draft…" opens: what to do, and anything new to work in.
  static const _draftPanel =
      '''
<div class="draft-panel" hidden data-first="${Assistant.firstDraft}">
  <label>What should Claude do?
    <input class="instruction" maxlength="300" placeholder="Work in what we learned about his years in the Navy"></label>
  <label>Notes to work in, if any: notes, a letter, an obituary
    <textarea class="notes" rows="4" spellcheck="true"></textarea></label>
  <p class="hint">Claude rewrites the story, keeping its wording where it can. The lines it changes are marked, and Undo puts the story back.</p>
  <div><button type="button" class="primary go">Draft</button> <button type="button" class="cancel">Cancel</button></div>
</div>''';

  /// [p]'s page with the editor in place of its content: opened directly,
  /// or shown again after a save that could not be made.
  String editPerson(
    Person p, {
    required String source,
    required int basedOn,
    String? error,
    String? conflict,
    bool help = false,
    String? helpOff,
    String? helpedBy,
  }) => person(
    p,
    editor:
        '${conflict ?? ''}${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}'
        '${editorForm(p, source: source, basedOn: basedOn, help: help, helpOff: helpOff, helpedBy: helpedBy)}',
  );

  /// Creating a page for [name], a plain name on [from]'s page in a [kind]
  /// line. Offers the [similar] people already in the tree first. The new
  /// page starts with [relatives], as [field] (`parents` or `partners`):
  /// the [fixed] ones always, the others when ticked.
  String addPerson(
    Person from, {
    required String kind,
    required String name,
    required List<Person> similar,
    required Completion completion,
    required String field,
    List<Person> fixed = const [],
    List<(Person, bool)> optional = const [],
    String born = '',
    String? error,
  }) {
    final hidden =
        '<input type="hidden" name="kind" value="${esc(kind)}">'
        '<input type="hidden" name="name" value="${esc(name)}">'
        '<input type="hidden" name="based_on" value="${from.revision}">';
    final role = switch (kind) {
      'parents' => 'a parent',
      'children' => 'a child',
      'siblings' => 'a sibling',
      'partner' => 'a partner',
      _ => 'in a “${esc(kind)}” line',
    };
    final sb = StringBuffer('''
<h1>A page for ${esc(name)}</h1>
<p class="lead">${personLink(from.id)}'s page names ${esc(name)} as $role, without a page of their own.</p>
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}''');
    if (similar.isNotEmpty) {
      sb.write(
        '<h2>Already in the tree?</h2><p>These people have similar names. If one of them is ${esc(name)}, link to their page instead.</p><ul class="similar">',
      );
      for (final p in similar) {
        final detail = completion.detail(p);
        sb.write(
          '<li><form method="post" action="/people/${from.id}/link">$hidden'
          '<input type="hidden" name="target" value="${p.id}">'
          '${personLink(p.id)}${detail.isEmpty ? '' : ' <span class="years">${esc(detail)}</span>'} '
          '<button>Link to this person</button></form></li>',
        );
      }
      sb.write('</ul><h2>Or create a new page</h2>');
    }
    final relatives = [
      for (final p in fixed)
        '<label><input type="checkbox" checked disabled> ${esc(p.name)}</label>'
            '<input type="hidden" name="$field" value="${p.id}">',
      for (final (p, checked) in optional)
        '<label><input type="checkbox" name="$field" value="${p.id}"${checked ? ' checked' : ''}> ${esc(p.name)}</label>',
    ];
    sb.write('''
<form class="memory add-person" method="post" action="/people/${from.id}/add">
  $hidden
  <label for="new_name">Name</label>
  <input id="new_name" name="new_name" value="${esc(name)}" required maxlength="120">
  <label for="born">Born, if you know: a date, then a place</label>
  <input id="born" name="born" value="${esc(born)}" maxlength="120" placeholder="about 1925, Hartford, CT">
  ${relatives.isEmpty ? '' : '<fieldset><legend>${field == 'parents' ? 'Parents' : 'Partner'}</legend>${relatives.join()}</fieldset>'}
  <p class="hint">The new page starts with these facts, and ${esc(from.name)}'s page links to it in place of the name. Both are saved as one change.</p>
  <div class="save"><button class="primary">Create the page</button> <a href="/people/${from.id}">Cancel</a></div>
</form>''');
    return page('A page for $name', sb.toString());
  }

  /// The form for adding a child, partner or parent to [from]'s page, with
  /// what was typed in [values]. [similar] are people already in the tree
  /// whose names are like the one typed, offered before a new page is made.
  String addRelative(
    Person from,
    String kind, {
    Map<String, String> values = const {},
    List<Person> similar = const [],
    Completion? completion,
    String? error,
  }) {
    String v(String name) => esc(values[name] ?? '');
    String checked(bool on) => on ? ' checked' : '';
    final title = switch (kind) {
      'children' => 'Add a child of ${from.name}',
      'parents' => 'Add a parent of ${from.name}',
      _ => 'Add a partner of ${from.name}',
    };
    final sb = StringBuffer('''
<h1>${esc(title)}</h1>
<p class="lead">Someone already in the tree, or someone new, who gets a page of their own. This is saved as ordinary lines on the pages, which you can change later by editing them.</p>
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}
<form class="memory add-person" method="post" action="/people/${from.id}/relative">
  <input type="hidden" name="kind" value="$kind">
  <input type="hidden" name="based_on" value="${from.revision}">''');
    if (similar.isNotEmpty) {
      sb.write(
        '<h2>Already in the tree?</h2><p>These people have similar names. If one of them is ${v('name')}, choose them.</p><ul class="similar">',
      );
      // Someone already related this way is shown, so a duplicate is
      // noticed, but cannot be added twice.
      final already = switch (kind) {
        'children' => index.childrenOf(from.id),
        'parents' => index.parentsOf(from.id),
        _ => index.partnersOf(from.id),
      };
      final role = switch (kind) {
        'children' => 'child',
        'parents' => 'parent',
        _ => 'partner',
      };
      for (final p in similar) {
        final detail = completion?.detail(p) ?? '';
        sb.write(
          '<li>${personLink(p.id)}${detail.isEmpty ? '' : ' <span class="years">${esc(detail)}</span>'} '
          '${already.contains(p.id) ? '<span class="years">already listed as ${esc(from.name)}\'s $role</span>' : '<button name="target" value="${p.id}">This is them</button>'}</li>',
        );
      }
      sb.write('</ul><h2>Or someone new</h2>');
    }
    sb.write(
      '''
  <label for="name">Name</label>
  <input id="name" name="name" value="${v('name')}" required maxlength="120" autofocus>
  <label for="born">Born, if you know: a date, then a place</label>
  <input id="born" name="born" value="${v('born')}" maxlength="120" placeholder="about 1925, Hartford, CT">''',
    );
    switch (kind) {
      case 'children':
        final partners = index.partnersOf(from.id);
        final chosen =
            values['other'] ?? (partners.length == 1 ? partners.single : '');
        sb.write('<fieldset><legend>The other parent</legend>');
        for (final id in partners) {
          sb.write(
            '<label><input type="radio" name="other" value="$id"${checked(chosen == id)}> ${esc(tree.people[id]!.name)}</label>',
          );
        }
        sb.write(
          '<label><input type="radio" name="other" value=""${checked(chosen.isEmpty)}> Someone else, or not known</label></fieldset>',
        );
      case 'parents':
        final parents = index.parentsOf(from.id);
        if (parents.length == 1) {
          final other = tree.people[parents.single]!;
          final on = values.isEmpty || values['couple'] == other.id;
          sb.write(
            '<label><input type="checkbox" name="couple" value="${other.id}"${checked(on)}> A couple with ${esc(other.name)}</label>',
          );
        }
      default:
        final married = values['married'] != 'no';
        sb.write(
          '''
  <fieldset><legend>Married?</legend>
    <label><input type="radio" name="married" value="yes"${checked(married)}> Married</label>
    <label><input type="radio" name="married" value="no"${checked(!married)}> Partners, not married</label>
  </fieldset>
  <label for="date">Married when, if you know</label>
  <input id="date" name="date" value="${v('date')}" maxlength="80" placeholder="June 1945">
  <label for="place">Where</label>
  <input id="place" name="place" value="${v('place')}" maxlength="200" placeholder="Hartford, CT">
  <label for="ended">Did it end?</label>
  <select id="ended" name="ended">
    <option value="">No, or not known</option>
    <option value="divorced"${values['ended'] == 'divorced' ? ' selected' : ''}>Divorced</option>
    <option value="separated"${values['ended'] == 'separated' ? ' selected' : ''}>Separated</option>
  </select>
  <label for="ended_date">When it ended, if you know</label>
  <input id="ended_date" name="ended_date" value="${v('ended_date')}" maxlength="80" placeholder="1995">''',
        );
    }
    sb.write('''
  <div class="save">${similar.isEmpty ? '<button class="primary">Add</button>' : '<button class="primary" name="create" value="yes">Add as someone new</button>'} <a href="${pathOf(from)}">Cancel</a></div>
</form>''');
    return page(title, sb.toString());
  }

  /// [p]'s page as it is written: its facts and story as text.
  String personText(Person p) => page(
    'Text of ${p.name}',
    '<h1>Text of ${personLink(p.id)}</h1>'
        '<p class="lead">The page as it is written, facts first and then the story.'
        '${_canEdit ? ' <a href="${pathOf(p)}?edit">Edit it</a>' : ''}</p>'
        '<pre class="source">${esc(p.source)}</pre>',
  );

  /// Asks before deleting [p]'s page. [changed] are the other pages that
  /// keep what they say about [p] with the plain name.
  String deletePerson(Person p, Iterable<Person> changed) {
    final mentioning = changed.toList();
    final sb = StringBuffer(
      '''
<h1>Delete ${esc(p.name)}'s page?</h1>
<p class="lead">The page leaves the tree. Its text is kept in its history, and the deletion can be undone from the page's address, which offers to bring it back with its links.</p>''',
    );
    if (mentioning.isNotEmpty) {
      sb.write(
        '<p>${mentioning.length == 1 ? 'One other page names' : '${mentioning.length} other pages name'} ${esc(p.name)}. There, ${esc(p.name)} stays as the plain name “${esc(p.name)}”, so nothing is lost:</p><ul>',
      );
      for (final other in mentioning) {
        sb.write('<li>${personLink(other.id, years: true)}</li>');
      }
      sb.write('</ul>');
    }
    sb.write('''
<form class="memory" method="post" action="/people/${p.id}/delete">
  <input type="hidden" name="based_on" value="${p.revision}">
  <div class="save"><button class="danger">Delete the page</button> <a href="/people/${p.id}">Cancel</a></div>
</form>''');
    return page('Delete ${p.name}', sb.toString());
  }

  /// What is shown at a deleted page's address. [undo] is the change that
  /// deleted it, when it can be undone whole: the page comes back, and so
  /// do the links to it on other pages.
  String deletedPerson(Person p, {Change? undo}) => page(p.name, '''
<h1>${esc(p.name)}</h1>
<p class="lead">This page was deleted. Its earlier versions are in its <a href="/people/${p.id}/history">change history</a>.</p>
${!_canEdit
      ? ''
      : undo != null && undoable(undo)
      ? '<form method="post" action="/changes/${undo.id}/undo"><button>Bring the page back</button></form>'
      : p.revision > 1
      ? '<form method="post" action="/people/${p.id}/restore"><input type="hidden" name="number" value="${p.revision - 1}"><button>Bring the page back</button></form>'
      : ''}''');

  /// Asks before deleting a photo or document.
  String deleteMedia(Media m) {
    final what = m.isDocument ? 'document' : 'photo';
    final main = [
      for (final p in tree.people.values)
        if (p.photo == m.key) p,
    ];
    return page('Delete ${m.title ?? 'a $what'}', '''
<h1>Delete “${esc(m.title ?? 'Untitled')}”?</h1>
<p class="lead">The $what leaves the tree${tree.media.containsKey('${m.id}-back') ? ', with its back' : ''}. Its file is kept, and the deletion can be undone from Recent changes or from the $what's address.</p>
${m.isImage || m.isDocument ? '<img class="thumb large" src="/media/${m.key}/display?w=960" alt="">' : ''}
${main.isEmpty ? '' : '<p>It is the main photo on ${main.map((p) => personLink(p.id)).join(', ')}. ${main.length == 1 ? 'That page' : 'Those pages'} will show no photo until another is chosen.</p>'}
<form class="memory" method="post" action="/media/${m.key}/delete">
  <div class="save"><button class="danger">Delete the $what</button> <a href="/media/${m.key}">Cancel</a></div>
</form>''');
  }

  /// What is shown at a deleted photo's address. [undo] is the change that
  /// deleted it, when it can be undone.
  String deletedMedia(Media m, {Change? undo}) {
    final what = m.isDocument ? 'document' : 'photo';
    return page(
      m.title ?? 'Untitled',
      '''
<h1>${esc(m.title ?? 'Untitled')}</h1>
<p class="lead">This $what was deleted.</p>
${_canEdit && undo != null && undoable(undo) ? '<form method="post" action="/changes/${undo.id}/undo"><button>Bring the $what back</button></form>' : ''}''',
    );
  }

  /// Explains a save that was refused because the page had moved on.
  String conflictNotice(Revision theirs, String before) =>
      '''
<div class="conflict" role="alert">
<p><strong>${esc(theirs.by)} saved a change to this page while you were editing</strong> (“${esc(theirs.summary)}”). Your text is still below and has not been saved.</p>
<p>Their change is shown here. Work it into your text, then save again; saving now will replace their version with yours.</p>
${diff(before, theirs.source)}
</div>''';

  String memoryForm(
    Person p, {
    String title = '',
    String date = '',
    String text = '',
    String? error,
    bool help = false,
  }) => page('Add a memory of ${p.name}', '''
<h1>Add a memory of ${esc(p.name)}</h1>
<p class="lead">A story, a trip, something you remember. It is added to the end of the page as its own section; nothing else on the page changes.</p>
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}
<form class="memory" method="post" action="/people/${p.id}/memory">
  <input type="hidden" name="helped_by" value="">
  <label for="title">Title</label>
  <input id="title" name="title" value="${esc(title)}" required maxlength="120" placeholder="Trip to Wales">
  <label for="date">When, if you know. A year is enough.</label>
  <input id="date" name="date" value="${esc(date)}" maxlength="40" placeholder="1923">
  <label for="text">The memory</label>
  <textarea id="text" name="text" required spellcheck="true">${esc(text)}</textarea>
  ${help ? '<div class="help tidy" data-url="/people/${p.id}/memory/tidy"><button type="button">Claude: Tidy up</button></div><div class="help-bar" hidden role="status"></div>' : ''}
  <div class="save"><button class="primary">Add</button> <a href="/people/${p.id}">Cancel</a></div>
</form>
${help ? '<script type="module" src="/assets/memory.js"></script>' : ''}
''');

  /// A page's change history: every saved version, newest first. Choosing
  /// one shows what it changed below the list, from [panel], and offers to
  /// restore it.
  String history(
    Person p,
    List<Revision> revisions, {
    int? selected,
    String panel = '',
  }) {
    final sb = StringBuffer('<h1>Change history: ${personLink(p.id)}</h1>');
    if (revisions.isEmpty) {
      sb.write(
        '<p class="lead">No versions have been recorded for this page.</p>',
      );
      return page('Change history of ${p.name}', sb.toString());
    }
    sb.write(
      '<p class="lead">${revisions.length} saved ${revisions.length == 1 ? 'version' : 'versions'}, newest first. Choose one to see what it changed.</p>',
    );
    sb.write('<table class="history versions" data-person="${p.id}"><tbody>');
    for (final (i, r) in revisions.indexed) {
      final helped = Model.byId(r.helpedBy);
      final restorable =
          _canEdit && i > 0 && !r.deleted && !r.source.startsWith('---');
      sb.write(
        '<tr data-version="${r.number}" tabindex="0"${r.number == selected ? ' aria-selected="true"' : ''}>'
        '<td class="when">${time(r.at)}</td>'
        '<td>${esc(r.by)}</td>'
        '<td>${esc(r.summary)}'
        '${helped == null ? '' : ' <span class="years">(with ${esc(helped.name)})</span>'}'
        '${r.deleted
            ? ' <span class="years">(page deleted)</span>'
            : i == 0
            ? ' <span class="years">(current)</span>'
            : ''}</td>'
        '<td class="restore">${restorable ? '<form method="post" action="/people/${p.id}/restore"><input type="hidden" name="number" value="${r.number}"><button>Restore this version</button></form>' : ''}</td>'
        '</tr>',
      );
    }
    sb.write('</tbody></table>');
    sb.write(_summaryNote(revisions.map((r) => r.summaryBy)));
    sb.write(
      '<section class="version-panel" aria-live="polite">$panel</section>'
      '<script type="module" src="/assets/history.js"></script>',
    );
    return page('Change history of ${p.name}', sb.toString());
  }

  /// The single note on a page listing changes whose summaries a model
  /// wrote. Entries are not marked one by one.
  String _summaryNote(Iterable<String?> writers) {
    final names = {
      for (final id in writers.nonNulls) Model.byId(id)?.name ?? id,
    };
    return names.isEmpty
        ? ''
        : '<p class="meta">Change summaries by ${esc(names.join(' and '))}.</p>';
  }

  /// What one saved version changed from the version before it, shown below
  /// the change history.
  String versionPanel(Revision r, {Revision? previous}) =>
      '<h2>Version ${r.number}: ${esc(r.summary)}</h2>'
      '${r.deleted
          ? '<p class="meta">This version deleted the page.</p>'
          : r.number == 1
          ? '<p class="meta">The first version of the page.</p>'
          : ''}'
      '<div class="changes-scroll">${diff(previous?.source ?? '', r.source)}</div>'
      '${r.deleted ? '' : '<details class="whole"><summary>The whole page as it was</summary><pre class="source">${esc(r.source)}</pre></details>'}';

  /// A comparison for people to read: each fact line and paragraph that
  /// changed, with the words taken out and put in marked, and a little of
  /// what is around it.
  String diff(String before, String after) {
    final blocks = diffBlocks(before, after);
    bool changed(DiffBlock b) => b.kind != DiffKind.same || b.words != null;
    if (!blocks.any(changed)) {
      return '<p class="lead">The two versions are identical.</p>';
    }
    // Keep one block of context around each change.
    final keep = List.filled(blocks.length, false);
    for (var i = 0; i < blocks.length; i++) {
      if (!changed(blocks[i])) continue;
      for (var j = i - 1; j <= i + 1; j++) {
        if (j >= 0 && j < blocks.length) keep[j] = true;
      }
    }
    final sb = StringBuffer('<div class="diff">');
    var skipping = false;
    for (final (i, block) in blocks.indexed) {
      if (!keep[i]) {
        if (!skipping) sb.write('<div class="skip">⋯</div>');
        skipping = true;
        continue;
      }
      skipping = false;
      if (block.words case final words?) {
        sb.write('<div class="changed">');
        for (final w in words) {
          sb.write(switch (w.kind) {
            DiffKind.same => esc(w.text),
            DiffKind.removed => '<del>${esc(w.text.trimRight())}</del> ',
            DiffKind.added => '<ins>${esc(w.text)}</ins>',
          });
        }
        sb.write('</div>');
        continue;
      }
      final (cls, open, close) = switch (block.kind) {
        DiffKind.same => ('same', '', ''),
        DiffKind.removed => ('removed', '<del>', '</del>'),
        DiffKind.added => ('added', '<ins>', '</ins>'),
      };
      sb.write('<div class="$cls">$open${esc(block.text)}$close</div>');
    }
    sb.write('</div>');
    return sb.toString();
  }

  /// Everything in the tree that needs an editor's eye: pages that
  /// disagree about who is related to whom, facts that cannot be right, and
  /// lines that cannot be read. Small disagreements about dates are left
  /// out; they are shown on the pages themselves.
  ({
    List<(Person, Contradiction)> disagree,
    List<(Person, String)> impossible,
    List<(Person, String)> unreadable,
  })
  correctionItems() {
    final seen = <String>{};
    final disagree = <(Person, Contradiction)>[];
    final impossible = <(Person, String)>[];
    final unreadable = <(Person, String)>[];
    final people = tree.people.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final p in people) {
      for (final c in contradictionsOf(tree, p)) {
        if (!c.minor && seen.add(c.key)) disagree.add((p, c));
      }
      for (final check in checksOf(p)) {
        impossible.add((p, check));
      }
      for (final issue in issuesOf(p)) {
        unreadable.add((p, issue));
      }
    }
    return (disagree: disagree, impossible: impossible, unreadable: unreadable);
  }

  /// How many items [correctionItems] finds.
  int correctionCount() {
    final items = correctionItems();
    return items.disagree.length +
        items.impossible.length +
        items.unreadable.length;
  }

  /// The list of [correctionItems], each linking to the page to fix it on.
  String itemsToCorrect() {
    final items = correctionItems();
    final sb = StringBuffer('<h1>Items to correct</h1>');
    final total =
        items.disagree.length +
        items.impossible.length +
        items.unreadable.length;
    if (total == 0) {
      sb.write(
        '<p class="lead">Nothing needs correcting. The pages agree with each other, and every fact can be read.</p>',
      );
      return page('Items to correct', sb.toString());
    }
    sb.write(
      '<p class="lead">Places where pages disagree, or a fact cannot be right. '
      'Each is also shown on the page it concerns, with a way to fix it there. '
      'Small differences in dates between records are normal, and are not listed.</p>',
    );
    void section(String title, String note, List<(Person, String)> rows) {
      if (rows.isEmpty) return;
      sb.write(
        '<h2>$title <span class="count">${rows.length}</span></h2><p class="meta">$note</p><ul class="corrections">',
      );
      for (final (p, html) in rows) {
        sb.write('<li><a href="${pathOf(p)}">${esc(p.name)}</a>: $html</li>');
      }
      sb.write('</ul>');
    }

    section(
      'Pages that disagree',
      'Two pages say different things about how people are related. Open the page to see both sides and choose which to keep.',
      [for (final (p, c) in items.disagree) (p, esc(c.message))],
    );
    section(
      'Facts that cannot be right',
      'Dates that contradict each other, such as a marriage after a death, or a parent too young or too old.',
      [for (final (p, text) in items.impossible) (p, esc(text))],
    );
    section(
      'Lines that cannot be read',
      'Text in the facts that Prosapia does not understand, or a link to a page that no longer exists.',
      [for (final (p, text) in items.unreadable) (p, esc(text))],
    );
    return page('Items to correct', sb.toString());
  }

  String changes(List<Change> changes) {
    final sb = StringBuffer('<h1>Recent changes</h1>');
    if (_canEdit) {
      final n = correctionCount();
      if (n > 0) {
        sb.write(
          '<p class="corrections-note"><a href="/corrections">${n == 1 ? 'One item' : '$n items'} to correct</a>: pages that disagree, or facts that cannot be right.</p>',
        );
      }
    }
    if (changes.isEmpty) {
      sb.write('<p class="lead">Nothing has changed yet.</p>');
    } else {
      sb.write(
        '<p class="lead">Every change to the tree, newest first.</p><table class="history">',
      );
      for (final c in changes) {
        final (items, summary) = _changeParts(c);
        sb.write(
          '<tr><td class="when">${time(c.at)}</td><td>${esc(c.by)}</td>'
          '<td>$items</td>'
          '<td>$summary</td></tr>',
        );
      }
      sb.write('</table>');
      sb.write(_summaryNote(changes.map((c) => c.summaryBy)));
    }
    return page('Recent changes', sb.toString());
  }

  /// What a change touched, linked, and its summary, linked to the version
  /// it made when it changed one page.
  (String, String) _changeParts(Change c) {
    final pages = c.pages.length > 5
        ? '${c.pages.length} pages'
        : c.pages.keys.map(personLink).join(', ');
    // A front and its back are one photo.
    final photos = c.media.where((key) => !key.endsWith('-back')).toList();
    final media = [
      for (final key in photos.take(5))
        '<a href="/media/$key">${esc((tree.media[key] ?? tree.deletedMedia[key])?.title ?? 'Untitled')}</a> '
            '<span class="years">(${(tree.media[key] ?? tree.deletedMedia[key])?.isImage ?? true ? 'photo' : 'document'})</span>',
      if (photos.length > 5) '${photos.length - 5} more',
    ].join(', ');
    final only = c.pages.length == 1 && c.media.isEmpty
        ? c.pages.entries.single
        : null;
    return (
      '$pages${pages.isNotEmpty && media.isNotEmpty ? ', ' : ''}$media',
      only == null
          ? esc(c.summary)
          : '<a href="/people/${only.key}/history?version=${only.value}">${esc(c.summary)}</a>',
    );
  }

  /// Whether [c] can be undone in one step: every page it touched is still
  /// as it left them. Large changes, such as loading the tree, are not
  /// offered.
  bool undoable(Change c) =>
      _canEdit &&
      (c.mediaDeleted
          ? c.media.every(tree.deletedMedia.containsKey)
          : c.media.isEmpty) &&
      c.pages.length <= 10 &&
      c.pages.entries.every(
        (e) => (tree.people[e.key] ?? tree.deleted[e.key])?.revision == e.value,
      );

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// When something happened, as GitHub says it: "today", "3 days ago", or
  /// the date for anything older than a month.
  /// How long ago [at] was: `today`, `3 days ago`, `on 12 Oct 2026`. The
  /// browser recounts the days in the viewer's own time zone.
  static String ago(DateTime at, [DateTime? now]) {
    final days = (now ?? DateTime.now()).difference(at).inDays;
    final text = days < 1
        ? 'today'
        : days < 2
        ? 'yesterday'
        : days < 31
        ? '$days days ago'
        : 'on ${_day(at.toUtc())}';
    return '<time datetime="${at.toUtc().toIso8601String()}" data-ago>$text</time>';
  }

  /// `12 Oct 2026, 20:46`: written in UTC, and shown by the browser in the
  /// viewer's own time zone.
  static String time(DateTime at) {
    final t = at.toUtc();
    return '<time datetime="${t.toIso8601String()}" data-time>${_day(t)}, '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} UTC</time>';
  }

  static String _day(DateTime t) =>
      '${t.day} ${_monthNames[t.month - 1]} ${t.year}';

  String forbidden(String what) => page(
    'Not allowed',
    '<h1>Not allowed</h1><p class="lead">${esc(what)}</p>',
  );

  /// The page shown to someone who is not signed in. [config] is handed to
  /// the browser-side sign-in code.
  static String signIn(String treeName, Map<String, Object?> config) =>
      '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sign in · ${esc(treeName)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Sans+3:ital,wght@0,400;0,500;0,600;0,700;1,400&display=swap">
<link rel="stylesheet" href="/style.css">
</head>
<body>
<main class="sign-in">
<h1>${esc(treeName)}</h1>
<p class="lead">This family tree is private. Sign in with the Google account you were invited with.</p>
<p><button id="sign-in" class="primary">Sign in with Google</button></p>
<p id="message" class="message" role="alert"></p>
</main>
<script id="config" type="application/json">${jsonEncode(config).replaceAll('<', r'\u003c')}</script>
<script type="module" src="/assets/sign_in.js"></script>
</body>
</html>
''';

  /// The owner's settings for the tree: help from Claude.
  String settings(
    HelpSettings help, {
    required double spent,
    required bool available,
    List<Member> members = const [],
    String? error,
  }) => page('Settings', '''
<h1>Settings</h1>
${error == null ? '' : '<p class="message" role="alert">${esc(error)}</p>'}
<h2 id="members">Members</h2>
<p>Only the people listed here can open the tree, by signing in with Google using this email address. Owners can also change these settings; editors can edit pages and add photos; viewers can read. Changes take effect within a minute.</p>
<table class="history members">
${[for (final m in members) _memberRow(m)].join('\n')}
</table>
<h3>Invite someone</h3>
<form class="memory invite" method="post" action="/settings/members">
  <input type="hidden" name="action" value="invite">
  <label for="invite_email">Their Google account's email address</label>
  <input id="invite_email" name="email" type="email" required placeholder="cousin@example.com">
  <label for="invite_role">What they may do</label>
  ${_roleSelect(Role.editor, id: 'invite_role')}
  <label>Who they are: their own page, or for someone without one, their nearest relative's. Their first visit starts there.</label>
  <div class="people-picker" data-name="person" data-single="true" data-initial="[]"></div>
  <div class="save"><button class="primary">Invite</button></div>
</form>
<p class="hint">Next you'll see an invitation to send them from your own email. Inviting someone already listed changes their role and who they are.</p>
<script type="module" src="/assets/photos.js"></script>
<h2>Help from Claude</h2>
<p>Members who can edit may ask Claude to draft or revise a page's story, and to tidy a memory. The text replaces what Claude was asked to act on in the editor, and nothing is saved until the member publishes it. Claude Haiku writes the one-line summary of each change.</p>
${available ? '' : '<p class="message">This server has no Anthropic API key, so help is not available whatever is set here. Set <code>ANTHROPIC_API_KEY</code> where the server runs.</p>'}
<form class="memory" method="post" action="/settings">
  <label class="check"><input type="checkbox" name="help"${help.enabled ? ' checked' : ''}> Members may ask Claude for help</label>
  <label for="monthly_limit">Monthly limit, in US dollars</label>
  <input id="monthly_limit" name="monthly_limit" type="number" min="0" step="1" value="${help.monthlyLimit.toStringAsFixed(0)}">
  <p class="hint">Spent this month: \$${spent.toStringAsFixed(2)}. When the limit is reached, help stops until the next month.</p>
  <div class="save"><button class="primary">Save</button></div>
</form>''');

  String _roleSelect(Role selected, {String? id}) =>
      '<select name="role"${id == null ? ' aria-label="Role"' : ' id="$id"'}>${[for (final role in Role.values) '<option value="${role.name}"${role == selected ? ' selected' : ''}>${role.name}</option>'].join()}</select>';

  String _memberRow(Member m) {
    final self = m.email == viewer?.email;
    final form =
        '<form method="post" action="/settings/members"><input type="hidden" name="email" value="${esc(m.email)}">';
    final who = m.person == null ? null : tree.people[m.person];
    return '<tr><td>${esc(m.name ?? '')}<br><span class="years">${esc(m.email)}</span></td>'
        '<td>${who == null ? (self ? '<span class="years">Choose “This is me” in the ⋯ menu on your page</span>' : '') : personLink(who.id)}</td>'
        '<td>${self ? '${m.role.name} (you)' : '$form${_roleSelect(m.role)} <button>Change</button></form>'}</td>'
        '<td>${self ? '' : '<a href="/settings/invitation?email=${Uri.encodeQueryComponent(m.email)}">Invitation</a>'}</td>'
        '<td>${self ? '' : '$form<input type="hidden" name="action" value="remove"><button>Remove</button></form>'}</td></tr>';
  }

  /// An invitation for [from] to send [member] from their own email, so it
  /// comes from someone the member knows.
  String invitation(
    Member member, {
    required Member from,
    required String address,
  }) {
    final person = member.person == null ? null : tree.people[member.person];
    final first = member.name?.split(' ').first;
    final subject = 'You\'re invited to the ${tree.name} history';
    final body = [
      'Hi${first == null ? '' : ' $first'},',
      '',
      'I\'ve added you to "${tree.name}", our family\'s history on Prosapia: a '
          'private website where the family keeps its stories, dates and '
          'photos together${member.role.canEdit ? ', and where anyone invited can add what they know and remember' : ''}.',
      '',
      'To visit, go to $address and sign in with your Google account, '
          '${member.email}.${person == null ? '' : ' You\'ll start at ${person.name}\'s page.'}',
      if (member.role.canEdit) ...[
        '',
        'Every change is kept, so nothing you do can be lost or break anything.',
      ],
      '',
      from.name ?? from.email,
    ].join('\n');
    final mailto = Uri(
      scheme: 'mailto',
      path: member.email,
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    return page('Invitation', '''
<h1>Invite ${esc(member.name ?? member.email)}</h1>
<p class="lead">${esc(member.email)} can now sign in. Send them this from your own email, so it comes from someone they know; change it as you like.</p>
<form class="memory invitation">
  <label for="subject">Subject</label>
  <input id="subject" value="${esc(subject)}" readonly>
  <label for="body">Message</label>
  <textarea id="body" readonly>${esc(body)}</textarea>
  <div class="save">
    <a class="button primary" href="${esc(mailto.toString())}">Open in your email</a>
    <button type="button" class="copy" data-copy="body">Copy the message</button>
    <a href="/settings#members">Back to Settings</a>
  </div>
</form>
<script>
document.querySelector('.copy').addEventListener('click', async (e) => {
  await navigator.clipboard.writeText(document.getElementById('body').value);
  e.target.textContent = 'Copied';
});
</script>''');
  }

  /// A short page that explains why something could not be done.
  String message(String title, String what) =>
      page(title, '<h1>${esc(title)}</h1><p class="lead">${esc(what)}</p>');

  String notFound(String what) =>
      page('Not found', '<h1>Not found</h1><p class="lead">${esc(what)}</p>');
}

const stylesheet = '''
/* "Archive": one humanist sans throughout, ink blue on a cool white. */
:root {
  --bg: #fbfcfd; --surface: #ffffff; --tint: #f3f5f9; --text: #1d2433; --muted: #5a6478;
  --line: #dfe4ec; --link: #24518a; --accent: #24518a; --on-accent: #ffffff; --mark: #fff1a8;
  --ui: "Source Sans 3", system-ui, -apple-system, "Segoe UI", sans-serif;
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #12161d; --surface: #19202a; --tint: #171c24; --text: #e3e8f0; --muted: #97a2b5;
          --line: #2a3240; --link: #9cc0ec; --accent: #3d6fae; --on-accent: #ffffff; --mark: #6b5a00; }
}
* { box-sizing: border-box; }
[hidden] { display: none !important; }
body { margin: 0; background: var(--bg); color: var(--text); font: 18px/1.6 var(--ui); }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
header { display: flex; flex-wrap: wrap; align-items: center; gap: 12px 24px;
         padding: 12px 24px; border-bottom: 1px solid var(--line); background: var(--tint);
         font-size: 16px; }
header .site { font-weight: 600; color: var(--text); }
header nav { display: flex; gap: 16px; flex: 1; }
header input { font: inherit; padding: 6px 10px; border: 1px solid var(--line); border-radius: 6px;
               background: var(--bg); color: var(--text); width: 220px; max-width: 100%; }
main { max-width: 960px; margin: 0 auto; padding: 24px 24px 64px; }
main.wide { max-width: 1100px; }
h1 { font-size: 2em; font-weight: 600; line-height: 1.15; letter-spacing: -0.005em; margin: 0 0 4px;
     text-wrap: balance; }
h2 { font-size: 1.15em; font-weight: 600; margin: 1.8em 0 0.5em; padding-bottom: 4px; text-wrap: balance;
     border-bottom: 1px solid var(--line); overflow: hidden; }
.lead, .years, .meta, .place, .empty, .snippet { color: var(--muted); }
.lead { margin: 0 0 1.2em; }
.years, .meta, .snippet { font-size: 0.88em; }
.place::before { content: " · "; }
.kind { font-variant: small-caps; letter-spacing: 0.03em; color: var(--muted); }
.empty { font-style: italic; }
.missing { color: var(--muted); font-style: italic; }
.infobox { float: right; width: 320px; margin: 0 0 16px 24px; padding: 12px; background: var(--tint);
           border: 1px solid var(--line); border-radius: 6px; font: 15px/1.5 var(--ui); }
.infobox img { display: block; width: 100%; border-radius: 4px; margin-bottom: 10px; }
.infobox table { border-collapse: collapse; width: 100%; }
.infobox th { text-align: left; vertical-align: top; padding: 4px 10px 4px 0; color: var(--muted);
              font-weight: 500; white-space: nowrap; }
.infobox td { padding: 4px 0; }
.infobox .add-relative { font-size: 13px; }
.corrections li { margin-bottom: 6px; }
h2 .count { font-size: 0.8em; font-weight: 500; color: var(--muted); }
.corrections-note { font: 15px var(--ui); }
.prose { white-space: normal; }
.prose p { margin: 0 0 1em; }
.prose a { font-weight: 500; }
.timeline { border-collapse: collapse; }
.timeline th { text-align: right; vertical-align: top; padding: 4px 16px 4px 0; font-weight: 400;
               color: var(--muted); font-variant-numeric: tabular-nums; white-space: nowrap; }
.timeline td { padding: 4px 0; }
.surnames { columns: 3 220px; column-gap: 32px; }
.surnames section { break-inside: avoid; margin-bottom: 16px; }
.surnames h2 { margin-top: 0; font-size: 1.1em; }
.surnames ul, .results { list-style: none; padding: 0; margin: 0; }
.results li { margin-bottom: 12px; }
mark { background: var(--mark); color: inherit; }
.gallery { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 16px; }
@media (max-width: 700px) { .gallery { grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; } }
@media (max-width: 420px) { .gallery { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
.gallery a { display: block; font: 14px/1.4 var(--ui); color: var(--text); overflow-wrap: anywhere; }
.gallery .caption { display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2;
  line-clamp: 2; overflow: hidden; }
.gallery img, .gallery .file { display: block; width: 100%; aspect-ratio: 1; object-fit: cover;
                               border-radius: 4px; border: 1px solid var(--line); margin-bottom: 6px; }
/* A document: its first page, on a small stack of paper, with its kind. */
.gallery .doc { position: relative; display: block; margin-bottom: 6px; }
.gallery .doc img { object-position: top; margin-bottom: 0; background: #fff;
  box-shadow: 3px 3px 0 -1px var(--surface), 3px 3px 0 0 var(--line), 6px 6px 0 -1px var(--surface),
    6px 6px 0 0 var(--line); }
.gallery .doc .badge { position: absolute; left: 6px; bottom: 6px; padding: 1px 6px; border-radius: 3px;
  background: #b3261e; color: #fff; font: 600 11px/1.5 var(--ui); letter-spacing: 0.04em; }
.media figure.document img { max-height: 60vh; background: #fff;
  box-shadow: 4px 4px 0 -1px var(--surface), 4px 4px 0 0 var(--line), 8px 8px 0 -1px var(--surface),
    8px 8px 0 0 var(--line); }
.media figure.document figcaption { margin-top: 14px; }
.media figure.document figcaption .years { margin-left: 8px; }
.photo-card .status progress { width: 160px; vertical-align: middle; margin-left: 6px; }
.photo-card img.document { background: #fff; box-shadow: 3px 3px 0 0 var(--line), 6px 6px 0 0 var(--line); }
.gallery .file { display: grid; place-items: center; background: var(--surface); color: var(--muted);
                 font-weight: 600; letter-spacing: 0.05em; }
/* One row that scrolls sideways, with buttons at its ends. */
.strip { position: relative; }
.strip .gallery { display: flex; overflow-x: auto; scroll-snap-type: x proximity; scrollbar-width: thin;
  padding-bottom: 6px; }
.strip .gallery a { flex: 0 0 160px; scroll-snap-align: start; }
@media (max-width: 700px) { .strip .gallery a { flex-basis: 120px; } }
.strip.rows-2 .gallery, .strip.rows-3 .gallery { display: grid; grid-auto-flow: column;
  grid-template-columns: none; grid-auto-columns: 136px; gap: 12px; }
.strip.rows-2 .gallery { grid-template-rows: repeat(2, auto); }
.strip.rows-3 .gallery { grid-template-rows: repeat(3, auto); }
@media (max-width: 700px) { .strip.rows-2 .gallery, .strip.rows-3 .gallery { grid-auto-columns: 110px; } }
h2.with-action { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; }
h2.with-action .button { font: 14px var(--ui); padding: 3px 12px; }
.strip button { position: absolute; top: calc(50% - 30px); z-index: 1; width: 36px; height: 36px; padding: 0;
  border-radius: 50%; font: 22px/1 var(--ui); background: var(--surface);
  box-shadow: 0 2px 8px rgba(0,0,0,0.2); }
.strip .prev { left: -12px; }
.strip .next { right: -12px; }
.pager { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; justify-content: center;
  margin: 28px 0 0; font: 15px var(--ui); }
.pager a, .pager span { padding: 4px 10px; border-radius: 6px; }
.pager a:hover { background: var(--tint); text-decoration: none; }
.pager [aria-current] { background: var(--accent); color: var(--on-accent); }
.pager .off, .pager .gap { color: var(--muted); }
.media img { max-width: 100%; max-height: 80vh; border: 1px solid var(--line); border-radius: 4px; }
.description { white-space: pre-line; }
.description:has(+ details.rest[open]) { margin-bottom: 0; }
.problems, .issues { font: 14px/1.4 var(--ui); margin-bottom: 16px; }
.issues summary { color: var(--muted); cursor: pointer; }
.unresolved { text-decoration: underline dotted; text-underline-offset: 3px; color: var(--muted); cursor: help; }
.named { text-decoration: underline dotted; text-underline-offset: 3px; cursor: help; }
.date { cursor: help; }
a.add { font: 12px var(--ui); margin-left: 4px; white-space: nowrap; }
a.deleted { color: var(--muted); text-decoration: line-through; }
.contradictions summary { color: #b3261e; }
@media (prefers-color-scheme: dark) { .contradictions summary { color: #f2b8b5; } }
.resolve { display: flex; flex-wrap: wrap; gap: 6px; margin: 6px 0 10px; }
.resolve form { margin: 0; }
.resolve button { font-size: 13px; }
.help { margin-left: auto; display: flex; gap: 6px; align-items: center; }
.help.off { font: 13px var(--ui); color: var(--muted); }
.tabs .help button, .help button { font: 13px var(--ui); padding: 4px 10px; margin: 0 0 4px;
  border: 1px solid var(--line); border-radius: 6px; background: var(--surface); color: var(--text);
  cursor: pointer; }
.tabs .help button:hover:not(:disabled) { border-color: var(--link); color: var(--link); }
.tabs .help button:disabled { opacity: 0.45; cursor: default; }
.help-bar { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; padding: 8px 12px; margin: 8px 0;
  border: 1px solid var(--line); border-radius: 6px; background: var(--surface); font: 14px var(--ui); }
.help-bar[hidden] { display: none; }
.spinner { display: inline-block; width: 14px; height: 14px; margin-right: 8px; vertical-align: -2px;
  border: 2px solid var(--line); border-top-color: var(--accent); border-radius: 50%;
  animation: spin 0.8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
/* A bar moving along the top of the text Claude is working on. */
.busy, .editor .cm-editor.busy { background: linear-gradient(90deg, transparent, var(--accent), transparent) no-repeat,
  var(--surface); background-size: 30% 3px, auto; animation: busy 1.2s linear infinite; }
.cm-editor.busy .cm-scroller { opacity: 0.6; }
textarea.busy { opacity: 0.75; }
@keyframes busy { from { background-position: -40% 0, 0 0; } to { background-position: 140% 0, 0 0; } }
@media (prefers-reduced-motion: reduce) { .spinner, .busy { animation-duration: 3s; } }
.help-bar.error { border-color: #b3261e; }
.help-bar input { flex: 1; min-width: 200px; font: 14px var(--ui); padding: 5px 8px;
  border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--text); }
.cm-helped { background: rgba(140, 90, 220, 0.14); }
textarea.helped { background: rgba(140, 90, 220, 0.08); }
.tidy { margin: 8px 0 0; }
label.check { display: flex; gap: 8px; align-items: center; color: var(--text); font-size: 15px; }
label.check input { width: auto; }
.whole { margin-top: 16px; font: 14px var(--ui); }
.whole summary { cursor: pointer; color: var(--muted); }
.sides { display: grid; gap: 16px; }
.sides.two { grid-template-columns: 1fr 1fr; }
@media (max-width: 640px) { .sides.two { grid-template-columns: 1fr; } }
.sides figure { margin: 0; }
.sides figcaption { font: 13px var(--ui); color: var(--muted); margin-top: 4px; }
.media .sides img { max-width: 100%; }
.shown form { display: inline; margin-left: 8px; }
.shown button { font-size: 13px; }
img.thumb { display: block; max-width: 240px; max-height: 240px; border-radius: 4px; margin-top: 10px;
  border: 1px solid var(--line); }
.guide-example { display: grid; gap: 24px; }
.guide-example h3 { margin: 0 0 8px; font-size: 1em; color: var(--muted); }
.guide-example pre.source { margin: 0; padding: 12px; overflow-x: auto; font-size: 13px; line-height: 1.5;
  background: var(--tint); border: 1px solid var(--line); border-radius: 6px; }
.guide-example .preview { padding: 12px 16px; border: 1px solid var(--line); border-radius: 6px; font-size: 16px; }
.faq h3 { font-size: 1em; margin: 1.4em 0 0.3em; }
.faq h3 a { color: var(--text); }
.faq p { margin: 0 0 0.5em; }
.faq p code { font-size: 0.85em; }
.faq pre { margin: 0; padding: 8px 12px; overflow-x: auto; font-size: 13px; background: var(--tint);
  border: 1px solid var(--line); border-radius: 6px; }
.format .guide-link { font: 13px var(--ui); margin-right: 12px; white-space: nowrap; padding: 3px 8px; }
img.thumb.large { max-width: min(480px, 100%); max-height: 480px; }
.people-picker { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; padding: 6px;
  border: 1px solid var(--line); border-radius: 6px; background: var(--surface); position: relative; }
.people-picker .chip { display: inline-flex; gap: 4px; align-items: center; padding: 2px 4px 2px 10px;
  border-radius: 12px; background: var(--bg); border: 1px solid var(--line); font: 14px var(--ui); }
.people-picker .chip button { border: none; background: none; padding: 0 6px; color: var(--muted); }
.memory .people-picker input { flex: 1; min-width: 160px; border: none; padding: 4px; font: 15px var(--ui);
  background: transparent; width: auto; }
.people-picker .suggestions { position: absolute; top: 100%; left: 0; z-index: 10; min-width: 280px; margin-top: 4px;
  background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 4px 0;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); font: 14px var(--ui); }
.people-picker .suggestions div { padding: 6px 12px; cursor: pointer; }
.people-picker .suggestions div.active, .people-picker .suggestions div:hover { background: var(--bg); }
.people-picker .suggestions span { display: block; color: var(--muted); font-size: 12px; }
.photo-list { display: grid; gap: 16px; margin-top: 12px; }
.photo-card { display: grid; grid-template-columns: 160px 1fr; gap: 16px; padding: 12px;
  border: 1px solid var(--line); border-radius: 6px; background: var(--surface); }
@media (max-width: 640px) { .photo-card { grid-template-columns: 1fr; } }
.photo-card img { width: 160px; max-height: 200px; object-fit: contain; border-radius: 4px; background: var(--bg); }
.photo-card .status { font: 13px var(--ui); color: var(--muted); }
.photo-card label { margin-top: 8px; }
.memory .photo-card textarea, .edit-photo textarea { height: 7em; }
.memory .photo-card textarea.tall, .edit-photo textarea.tall { height: 18em; }
.edit-photo .hint, .photo-card .hint { margin: 0 0 4px; }
details.rest > summary { cursor: pointer; color: var(--link); font: 15px var(--ui); margin: -0.4em 0 0.6em; }
details.rest[open] > summary { display: none; }
details.rest > .description { margin-top: 0; }
.photo-card button { font: 13px var(--ui); }
.photo-card .card-links { display: flex; flex-wrap: wrap; gap: 4px 20px; font: 13px var(--ui); margin: 10px 0 0; }
.members form, .add-member { display: flex; gap: 8px; align-items: center; margin: 0; }
.add-member { margin-top: 12px; max-width: 640px; }
a.button.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
.invitation textarea { height: 16em; font: 15px/1.5 var(--ui); }
.invite select { display: block; }
.add-member input { flex: 1; font: 15px var(--ui); padding: 6px 10px; border: 1px solid var(--line);
  border-radius: 6px; background: var(--surface); color: var(--text); }
select { font: 14px var(--ui); padding: 4px 6px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); }
.start { display: flex; gap: 20px; align-items: flex-start; padding: 16px; margin: 8px 0 24px;
  background: var(--surface); border: 1px solid var(--line); border-radius: 8px; }
.start img { width: 160px; border-radius: 4px; display: block; }
.start h2 { margin-top: 0; border: none; }
.try li { margin-bottom: 8px; }
.recent li { margin-bottom: 8px; }
.research { max-width: 760px; }
.research li { margin-bottom: 8px; }
.research p { margin: 0 0 10px; }
/* A person's page: the title across the top, then the story beside the facts. */
.person-head { border-bottom: 1px solid var(--line); padding-bottom: 14px; margin-bottom: 24px; }
.person-head .title { display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: space-between;
  gap: 8px 24px; }
.person-head .name { display: flex; flex-wrap: wrap; align-items: baseline; gap: 0 14px;
  flex: 1 1 12em; min-width: 0; }
.person-head h1 { margin: 0; min-width: 0; }
.person-head .lead { margin: 0; }
.edited { font: 15px var(--ui); color: var(--muted); margin: 40px 0 0; padding-top: 12px;
  border-top: 1px solid var(--line); clear: both; }
.actions { display: flex; flex-wrap: wrap; gap: 8px 16px; margin: 0 0 12px; font: 15px var(--ui); }
.person-head .actions { gap: 8px; align-items: center; margin: 6px 0 0; }
.person-head .actions .button { padding: 5px 14px; font-size: 15px; }
details.more { position: relative; }
details.more summary { list-style: none; cursor: pointer; padding: 5px 12px; }
details.more summary::-webkit-details-marker { display: none; }
details.more .menu { position: absolute; right: 0; top: calc(100% + 4px); z-index: 10; min-width: 160px;
  padding: 4px 0; background: var(--surface); border: 1px solid var(--line); border-radius: 6px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); font: 15px var(--ui); }
details.more .menu a { display: block; padding: 6px 14px; color: var(--text); }
details.more .menu a:hover { background: var(--tint); text-decoration: none; }
details.more .menu form { margin: 0; }
details.more .menu button { display: block; width: 100%; text-align: left; padding: 6px 14px; border: none;
  border-radius: 0; background: none; color: var(--text); font: inherit; }
details.more .menu button:hover { background: var(--tint); }
@media (min-width: 1100px) {
  main > article.person { display: grid; grid-template-columns: minmax(0, 1fr) 320px; gap: 0 40px;
    align-items: start; }
  main > article.person > .infobox { grid-column: 2; grid-row: 1; float: none; width: auto; margin: 0; }
  main > article.person > .person-body { grid-column: 1; grid-row: 1; }
  main > article.person > .editing { grid-column: 1 / -1; grid-row: 1; }
}
/* The editor takes the page's full width; its preview shows the facts. */
main > article.editing-on > .infobox { display: none; }
.help-bar .drawn-from { flex-basis: 100%; color: var(--muted); }
.help-bar .drawn-from ul { margin: 4px 0 0; padding-left: 20px; color: var(--text); }
.draft-panel { padding: 12px 14px; margin: 8px 0; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); font: 15px var(--ui); }
.draft-panel label { display: block; margin: 0 0 10px; color: var(--muted); font-size: 14px; }
.draft-panel input, .draft-panel textarea { display: block; width: 100%; margin-top: 4px; padding: 6px 10px;
  font: 16px/1.5 var(--ui); color: var(--text); background: var(--bg); border: 1px solid var(--line);
  border-radius: 6px; }
.draft-panel .hint { margin: 0 0 10px; }
.draft-panel button.primary { font-size: 15px; padding: 6px 16px; }
.research-ideas { margin: 0 0 24px; padding: 14px 18px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); }
.research-ideas h2 { margin-top: 0; }
.research-ideas .actions { margin: 10px 0 0; }
.cite { font: 12px var(--ui); color: var(--muted); border-bottom: 1px dotted var(--muted);
  cursor: help; white-space: nowrap; }
.format { display: flex; flex-wrap: wrap; gap: 2px; padding: 6px 8px; border-bottom: 1px solid var(--line); }
.format button { border: none; background: none; color: var(--muted); padding: 3px 8px; border-radius: 4px;
  font: 14px var(--ui); min-width: 28px; }
.format button:hover { background: var(--tint); color: var(--text); }
.format .spacer { flex: 1; }
.format .sep { width: 1px; background: var(--line); margin: 2px 6px; }
.similar { list-style: none; padding: 0; font: 15px/1.5 var(--ui); }
.similar li { margin-bottom: 8px; }
.similar button { margin-left: 8px; font-size: 13px; }
.add-person fieldset { border: none; padding: 0; margin: 14px 0 0; }
.add-person legend { font: 13px/1.4 var(--ui); color: var(--muted); }
.add-person fieldset label { display: block; margin: 6px 0 0; color: var(--text); font-size: 15px; }
.add-person fieldset input { width: auto; margin-right: 6px; }
button.danger { background: #b3261e; border-color: #8c1d18; color: #fff; }
label code { font-size: 12px; }
.editor .cm-editor { min-height: 60vh; background: var(--surface); color: var(--text);
  font: 15px/1.6 ui-monospace, Menlo, monospace; border-radius: 0 0 6px 6px; }
.editor .cm-editor .cm-content { min-height: 60vh; caret-color: var(--text); padding: 12px 4px; }
.editor .cm-editor .cm-cursor { border-left: 2px solid var(--text); }
.editor .cm-editor.cm-focused { outline: 2px solid var(--link); outline-offset: -1px; }
.editor .cm-editor .cm-selectionBackground,
.editor .cm-editor.cm-focused .cm-selectionBackground { background: rgba(66, 133, 244, 0.28); }
.editor .cm-scroller { font-family: inherit; }
.cm-label { color: var(--link); font-weight: 600; }
.cm-ref { color: var(--link); text-decoration: underline; text-underline-offset: 3px; }
.cm-marked { color: #8a5a00; }
@media (prefers-color-scheme: dark) { .cm-marked { color: #e0b35a; } }
.cm-heading { font-weight: 700; }
.cm-quoted { color: #2f6f3e; }
@media (prefers-color-scheme: dark) { .cm-quoted { color: #8fd19e; } }
.cm-tooltip.cm-tooltip-autocomplete { font: 14px var(--ui); background: var(--surface);
  color: var(--text); border: 1px solid var(--line); border-radius: 6px; overflow: hidden;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); }
.cm-tooltip.cm-tooltip-autocomplete > ul { font-family: var(--ui); max-height: 18em; }
.cm-tooltip.cm-tooltip-autocomplete > ul > li { padding: 5px 12px; color: var(--text); }
.cm-tooltip.cm-tooltip-autocomplete > ul > li[aria-selected] { background: var(--link); color: var(--bg); }
.cm-tooltip-autocomplete .cm-completionDetail { color: var(--muted); margin-left: 10px; font-style: normal;
  font-size: 12px; }
.cm-tooltip-autocomplete ul li[aria-selected] .cm-completionDetail { color: inherit; opacity: 0.85; }
.search-suggestions { position: absolute; z-index: 10; background: var(--surface); border: 1px solid var(--line);
  border-radius: 6px; margin-top: 4px; min-width: 260px; max-width: 420px; padding: 4px 0;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15); }
.search-suggestions a { display: block; padding: 6px 12px; color: var(--text); }
.search-suggestions a span { color: var(--muted); font-size: 12px; display: block; }
.search-suggestions a.active, .search-suggestions a:hover { background: var(--bg); text-decoration: none; }
header form { position: relative; }
.tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--line); margin-bottom: -1px; }
.tabs button { border: 1px solid transparent; border-bottom: none; border-radius: 6px 6px 0 0;
  background: none; color: var(--muted); padding: 8px 16px; font: 15px var(--ui); }
.tabs button[aria-selected=true] { border-color: var(--line); background: var(--surface); color: var(--text);
  margin-bottom: -1px; }
.tab-panel { border: 1px solid var(--line); border-top: none; border-radius: 0 0 6px 6px; background: var(--surface); }
.editor .preview { min-height: 60vh; padding: 16px 20px; }
.hint { font: 14px/1.5 var(--ui); color: var(--muted); margin: 20px 0 4px; }
.memory label { display: block; font: 14px/1.4 var(--ui); color: var(--muted); margin-bottom: 6px; }
.memory label { min-height: 0; margin-top: 14px; }
textarea, .save input, .memory input { font: 15px/1.5 ui-monospace, Menlo, monospace;
  width: 100%; padding: 10px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); }
.memory input, .memory textarea, .save input { font: 16px/1.5 var(--ui); }
.memory textarea { height: 30vh; }
.memory { max-width: 640px; }
.preview.stale { opacity: 0.55; }
.button { display: inline-block; padding: 9px 18px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); font: 15px var(--ui); }
.button:hover { text-decoration: none; background: var(--bg); }
button.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
button.primary kbd { font: 12px var(--ui); background: rgba(255,255,255,0.18); border-radius: 4px;
  padding: 2px 6px; margin-left: 6px; }
.save { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; margin-top: 16px;
  font: 15px var(--ui); }
.save label { margin: 0; min-height: 0; }
.editor .save { justify-content: flex-end; }
.save input { flex: 1; min-width: 240px; }
.conflict { border: 1px solid #b3261e; border-radius: 6px; padding: 4px 16px 16px; margin: 12px 0;
  font: 15px/1.5 var(--ui); }
.history { border-collapse: collapse; font: 15px/1.5 var(--ui); width: 100%; }
.history td { padding: 6px 12px 6px 0; border-bottom: 1px solid var(--line); vertical-align: top; }
.source { font: 14px/1.5 ui-monospace, Menlo, monospace; white-space: pre-wrap; overflow-wrap: anywhere;
  background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 12px; }
.diff { font: 16px/1.55 var(--ui); white-space: pre-wrap; overflow-wrap: anywhere; background: var(--surface);
  border: 1px solid var(--line); border-radius: 6px; padding: 6px 0; }
.diff > div { padding: 6px 14px; border-left: 3px solid transparent; }
.diff .changed { border-left-color: #b08800; }
.diff .added { border-left-color: #2ea043; background: rgba(46, 160, 67, 0.08); }
.diff .removed { border-left-color: #da3633; background: rgba(218, 54, 51, 0.08); }
.diff .same { color: var(--muted); }
.diff ins { text-decoration: none; background: rgba(46, 160, 67, 0.22); border-radius: 3px; }
.diff del { background: rgba(218, 54, 51, 0.2); border-radius: 3px; }
.diff .added ins, .diff .removed del { background: none; }
.diff .skip { color: var(--muted); text-align: center; padding: 0; }
.when { white-space: nowrap; }
.versions tbody tr { cursor: pointer; }
.versions tbody tr:hover { background: var(--tint); }
.versions tbody tr[aria-selected=true] { background: var(--tint); box-shadow: inset 3px 0 0 var(--accent); }
.versions td:first-child { padding-left: 10px; }
.versions .restore { text-align: right; white-space: nowrap; padding-right: 8px; }
.versions tr:not([aria-selected=true]) .restore form { display: none; }
.versions .restore button { font-size: 14px; padding: 3px 10px; }
.version-panel h2 { margin-top: 1.4em; }
.changes-scroll { max-height: 60vh; overflow: auto; }
.account { display: flex; align-items: center; gap: 10px; color: var(--muted); }
button { font: inherit; padding: 5px 12px; border: 1px solid var(--line); border-radius: 6px;
         background: var(--surface); color: var(--text); cursor: pointer; }
button.primary { font: 600 16px var(--ui); padding: 10px 20px; }
button:disabled { opacity: 0.6; cursor: default; }
.sign-in { max-width: 520px; padding-top: 12vh; }
.message { font: 16px/1.5 var(--ui); color: #b3261e; min-height: 1.5em; }
@media (max-width: 640px) {
  .infobox { float: none; width: auto; margin: 0 0 16px; }
  main { padding: 16px 16px 48px; }
}
/* The family tree: rows of small cards, with lines drawn by family.js. It
   takes the whole width of the window, since a large family is wide. */
main:has(> .family-view:not(.embedded)) { max-width: none; }
.family-scroll { overflow-x: auto; margin: 8px -24px 0; padding: 8px 24px 16px; scrollbar-width: thin; }
.family { position: relative; width: max-content; min-width: 100%; display: flex; flex-direction: column;
  align-items: center; gap: 36px; font: 14px/1.3 var(--ui); }
.family > svg { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none;
  overflow: visible; }
.family .gen { display: flex; justify-content: center; align-items: flex-start; gap: 24px; }
/* Grandparents in one row and parents in the next, so parents line up
   whether or not their own parents are shown. */
.family .gen.up { display: grid; grid-auto-flow: column; grid-template-rows: auto auto;
  gap: 36px 24px; justify-content: center; justify-items: center; }
.family .gen.up .anc { display: contents; }
.family .gen.up .anc > .row { align-self: end; }
.family .gen.up .anc > .card { align-self: start; }
.family .gen.self { display: grid; grid-template-columns: 1fr auto 1fr; gap: 24px; align-items: start;
  width: 100%; }
.family .side { display: flex; gap: 12px; align-items: flex-start; }
.family .side.before { justify-content: flex-end; }
.family .row { display: flex; gap: 12px; justify-content: center; align-items: flex-start; }
.family .row.couple { gap: 20px; }
.family .anc, .family .desc { display: flex; flex-direction: column; align-items: center; gap: 36px; }
.family .gen.down { gap: 40px; }
.family .group { display: flex; flex-wrap: wrap; justify-content: center; gap: 16px;
  align-items: flex-start; }
.family .family-of { flex-basis: 100%; margin: -6px 0 0; text-align: center; font-size: 12px;
  color: var(--muted); }
.family .card { position: relative; z-index: 1; display: flex; gap: 8px; align-items: center; width: 210px;
  padding: 6px 8px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface);
  color: var(--text); }
.family .card:hover { text-decoration: none; border-color: var(--link); }
.family .card.center { border: 2px solid var(--accent); padding: 5px 7px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.12); }
.family .card img, .family .card .no-photo { flex: none; width: 36px; height: 36px; border-radius: 50%;
  object-fit: cover; background: var(--tint); border: 1px solid var(--line); }
.family .who { display: flex; flex-direction: column; min-width: 0; }
.family .name { font-weight: 600; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical;
  overflow: hidden; }
.family .years, .family .partner, .family .hint { font-size: 12px; color: var(--muted);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.family .hint { color: var(--link); margin: 0; }
.family .more { align-self: center; position: relative; z-index: 1; font-size: 13px; padding: 4px 10px;
  border: 1px dashed var(--line); border-radius: 12px; background: var(--bg); color: var(--muted);
  white-space: nowrap; }
.family svg path { fill: none; stroke: var(--muted); stroke-width: 1.5; }
.family svg path.couple { stroke-width: 1.5; }
.family-view > .meta { margin-top: 4px; }
@media (max-width: 700px) {
  .family-scroll { margin: 8px -16px 0; padding: 8px 16px 16px; }
  .family .card { width: 128px; }
  .family .card img, .family .card .no-photo { width: 28px; height: 28px; }
}
::view-transition-group(*) { animation-duration: 0.35s; }
@media (prefers-reduced-motion: reduce) { ::view-transition-group(*) { animation-duration: 0s; } }
/* Phones: one column, and nothing wider than the screen. */
@media (max-width: 700px) {
  header { padding: 10px 16px; gap: 8px 16px; }
  header nav { order: 3; flex-basis: 100%; gap: 14px; }
  header form.search { flex: 1; }
  header input { width: 100%; }
  main { padding: 16px 16px 48px; }
  h1 { font-size: 1.6em; }
  .infobox { float: none; width: auto; margin: 0 0 16px; }
  .history { display: block; overflow-x: auto; }
  .tabs { flex-wrap: wrap; }
  .tabs .help { margin-left: 0; flex-wrap: wrap; }
  .start { flex-direction: column; }
  .start img { width: 100%; max-width: 320px; }
  .timeline th { padding-right: 10px; white-space: normal; }
  .save { gap: 8px; }
  .save input { min-width: 0; }
}
''';
