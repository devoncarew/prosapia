import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import 'dates.dart';
import 'index.dart';
import 'tree.dart';

/// Turns the tree into HTML pages. Nothing here is stored: every page is
/// computed from the repository and the index.
class Renderer {
  Renderer(this.tree, this.index);

  final Tree tree;
  final Index index;

  static String esc(String? s) => htmlEscape.convert(s ?? '');

  String page(String title, String body, {String query = ''}) => '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · ${esc(tree.name)}</title>
<link rel="stylesheet" href="/style.css">
</head>
<body>
<header>
  <a class="site" href="/">${esc(tree.name)}</a>
  <nav><a href="/">People</a> <a href="/media">Photos</a></nav>
  <form action="/search"><input type="search" name="q" value="${esc(query)}" placeholder="Search" aria-label="Search"></form>
</header>
<main>
$body
</main>
</body>
</html>
''';

  String personLink(String id, {bool years = false}) {
    final p = tree.people[id];
    if (p == null) return '<span class="missing">unknown person ($id)</span>';
    final suffix = years && p.years.isNotEmpty ? ' <span class="years">(${p.years})</span>' : '';
    return '<a href="/people/${p.id}">${esc(p.name)}</a>$suffix';
  }

  // ------------------------------------------------------------------ home

  String home() {
    final groups = <String, List<Person>>{};
    for (final id in index.peopleByName()) {
      final p = tree.people[id]!;
      groups.putIfAbsent(p.surname ?? '', () => []).add(p);
    }
    final sb = StringBuffer()
      ..write('<h1>${esc(tree.name)}</h1>')
      ..write('<p class="lead">${tree.people.length} people, ${tree.unions.length} partnerships, ${tree.media.length} photos and documents.</p>');
    if (tree.problems.isNotEmpty) {
      sb.write('<details class="problems"><summary>${tree.problems.length} files could not be read</summary><ul>');
      for (final problem in tree.problems) {
        sb.write('<li>${esc(problem)}</li>');
      }
      sb.write('</ul></details>');
    }
    sb.write('<div class="surnames">');
    groups.forEach((surname, people) {
      sb.write('<section><h2>${esc(surname.isEmpty ? 'No surname recorded' : surname)}</h2><ul>');
      for (final p in people) {
        sb.write('<li>${personLink(p.id, years: true)}</li>');
      }
      sb.write('</ul></section>');
    });
    sb.write('</div>');
    return page('People', sb.toString());
  }

  // ---------------------------------------------------------------- person

  String person(Person p) {
    final sb = StringBuffer();
    sb.write('<article class="person">');
    sb.write(_infobox(p));
    sb.write('<h1>${esc(p.name)}</h1>');
    if (p.years.isNotEmpty) sb.write('<p class="lead">${p.years}</p>');

    if (p.body.isNotEmpty) {
      sb.write('<div class="prose">${markdown(p.body)}</div>');
    } else {
      sb.write('<p class="empty">Nothing has been written about ${esc(p.name)} yet.</p>');
    }

    final (dated, undated) = _timeline(p);
    if (dated.isNotEmpty) {
      sb.write('<h2>Timeline</h2><table class="timeline">');
      for (final e in dated) {
        sb.write('<tr><th>${esc(e.date.display)}</th><td>${e.html}</td></tr>');
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

    final media = [for (final key in index.mediaOf(p.id)) tree.media[key]!];
    if (media.isNotEmpty) {
      sb.write('<h2>Photos and documents</h2>${gallery(media)}');
    }
    sb.write('</article>');
    return page(p.name, sb.toString());
  }

  String _infobox(Person p) {
    final rows = <(String, String)>[];
    void row(String label, String html) {
      if (html.isNotEmpty) rows.add((label, html));
    }

    String event(Event? e) => e == null
        ? ''
        : [if (e.date != null) esc(e.date!.display), if (e.place != null) esc(e.place)].join('<br>');

    if (p.alsoKnownAs.isNotEmpty) row('Also known as', esc(p.alsoKnownAs.join(', ')));
    row('Born', event(p.born));
    row('Died', event(p.died));
    row(
        'Parents',
        p.parents
            .map((l) => personLink(l.id) + (l.relationship == null ? '' : ' <span class="years">(${esc(l.relationship)})</span>'))
            .join('<br>'));
    row(
        'Partners',
        index.partnershipsOf(p.id).map((uid) {
          final u = tree.unions[uid]!;
          final other = u.partners.firstWhere((x) => x != p.id, orElse: () => p.id);
          final year = u.married?.date?.year;
          return personLink(other) + (year == null ? '' : ' <span class="years">(married $year)</span>');
        }).join('<br>'));
    row('Children', index.childrenOf(p.id).map((id) => personLink(id, years: true)).join('<br>'));
    row('Siblings', index.siblingsOf(p.id).map((id) => personLink(id, years: true)).join('<br>'));

    final photo = p.photo == null ? null : tree.media[p.photo];
    if (rows.isEmpty && photo == null) return '';
    final sb = StringBuffer('<aside class="infobox">');
    if (photo != null && photo.isImage) {
      sb.write('<a href="/media/${photo.key}"><img src="/media/${photo.key}/display?w=480" alt="${esc(photo.title ?? p.name)}"></a>');
    }
    sb.write('<table>');
    for (final (label, html) in rows) {
      sb.write('<tr><th>$label</th><td>$html</td></tr>');
    }
    sb.write('</table></aside>');
    return sb.toString();
  }

  /// A life in order: structured events, family events, and dated headings
  /// from the prose. Facts with no date are returned separately.
  (List<({LoomDate date, String html})>, List<String>) _timeline(Person p) {
    final dated = <({LoomDate date, String html})>[];
    final undated = <String>[];
    void add(LoomDate? date, String html) =>
        date == null ? undated.add(html) : dated.add((date: date, html: html));
    String at(String? place) => place == null ? '' : ' <span class="place">${esc(place)}</span>';

    if (p.born?.date != null) add(p.born!.date, 'Born${at(p.born!.place)}');
    for (final f in p.facts) {
      final label = f.type[0].toUpperCase() + f.type.substring(1);
      add(f.event.date, '<span class="kind">$label</span>${f.value == null ? '' : ' ${esc(f.value)}'}${at(f.event.place)}');
    }
    for (final uid in index.partnershipsOf(p.id)) {
      final u = tree.unions[uid]!;
      if (u.married == null) continue;
      final other = u.partners.firstWhere((x) => x != p.id, orElse: () => p.id);
      add(u.married!.date, 'Married ${personLink(other)}${at(u.married!.place)}');
    }
    for (final id in index.childrenOf(p.id)) {
      final child = tree.people[id]!;
      if (child.born?.date != null) add(child.born!.date, 'Birth of ${personLink(id)}');
    }
    for (final m in RegExp(r'^##\s+((?:\d{1,2} )?(?:[A-Za-z]{3,9} )?\d{4})\s*[:–-]\s*(.+)$', multiLine: true).allMatches(p.body)) {
      final year = RegExp(r'\d{4}').firstMatch(m[1]!)![0]!;
      add(LoomDate(year), esc(m[2]));
    }
    if (p.died?.date != null) add(p.died!.date, 'Died${at(p.died!.place)}');

    // A stable sort keeps birth first and death last among equal dates.
    final sorted = [
      for (final (i, e) in dated.indexed) (i, e),
    ]..sort((a, b) {
        final c = a.$2.date.sortKey.compareTo(b.$2.date.sortKey);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return ([for (final (_, e) in sorted) e], undated);
  }

  /// Renders page prose. Links between people and to media are written as
  /// relative file paths so they work on GitHub; here they become site URLs.
  String markdown(String source) {
    final html = md.markdownToHtml(source, extensionSet: md.ExtensionSet.gitHubWeb);
    return html
        .replaceAllMapped(RegExp(r'href="[^"]*?([a-z0-9]{6})/index\.md"'), (m) => 'href="/people/p-${m[1]}"')
        .replaceAllMapped(RegExp(r'src="[^"]*?media/(m-[a-z0-9]+(?:-back)?)\.\w+"'), (m) => 'src="/media/${m[1]}/display?w=960"');
  }

  // ----------------------------------------------------------------- media

  String gallery(Iterable<Media> items) {
    final sb = StringBuffer('<div class="gallery">');
    for (final m in items) {
      final caption = esc(m.title ?? 'Untitled');
      sb.write('<a href="/media/${m.key}">');
      if (m.isImage) {
        sb.write('<img loading="lazy" src="/media/${m.key}/display?w=240" alt="$caption">');
      } else {
        sb.write('<span class="file">${m.extension.toUpperCase()}</span>');
      }
      sb.write('<span>$caption</span></a>');
    }
    sb.write('</div>');
    return sb.toString();
  }

  String mediaIndex() => page(
      'Photos',
      '<h1>Photos and documents</h1>'
          '<p class="lead">${tree.media.length} files. Titles and names are read from each file\'s embedded metadata.</p>'
          '${gallery(tree.media.values)}');

  String media(Media m) {
    final sb = StringBuffer('<article class="media">');
    sb.write('<h1>${esc(m.title ?? 'Untitled')}</h1>');
    if (m.isImage) {
      sb.write('<a href="/media/${m.key}/file"><img src="/media/${m.key}/display?w=1920" alt="${esc(m.title ?? '')}"></a>');
    } else {
      sb.write('<p><a class="file" href="/media/${m.key}/file">Open the ${m.extension.toUpperCase()} file</a></p>');
    }
    final other = tree.media[m.isBack ? m.id : '${m.id}-back'];
    if (other != null) {
      sb.write('<p><a href="/media/${other.key}">See the ${other.isBack ? 'back' : 'front'}</a></p>');
    }
    if (m.description != null) sb.write('<p class="description">${esc(m.description)}</p>');
    if (m.people.isNotEmpty) {
      sb.write('<h2>People shown</h2><ul>');
      for (final id in m.people) {
        sb.write('<li>${personLink(id, years: true)}</li>');
      }
      sb.write('</ul>');
    }
    sb.write('<p class="meta">${m.key}.${m.extension}${m.width == null ? '' : ' · ${m.width} × ${m.height}'} · <a href="/media/${m.key}/file">original file</a></p>');
    sb.write('</article>');
    return page(m.title ?? 'Untitled', sb.toString());
  }

  // ---------------------------------------------------------------- search

  String search(String query) {
    final results = index.search(query);
    final sb = StringBuffer('<h1>Search</h1>');
    if (query.trim().isEmpty) {
      sb.write('<p class="lead">Type a name, a place or a word from a page.</p>');
    } else if (results.isEmpty) {
      sb.write('<p class="lead">Nothing found for “${esc(query)}”.</p>');
    } else {
      sb.write('<p class="lead">${results.length} results for “${esc(query)}”.</p><ul class="results">');
      for (final r in results) {
        // The snippet is escaped, then the highlight marks are restored.
        final snippet = esc(r.snippet).replaceAll('&lt;mark&gt;', '<mark>').replaceAll('&lt;&#47;mark&gt;', '</mark>');
        final link = r.kind == 'person'
            ? personLink(r.id, years: true)
            : '<a href="/media/${r.id}">${esc(tree.media[r.id]?.title ?? 'Untitled')}</a> <span class="years">(${tree.media[r.id]?.isImage ?? false ? 'photo' : 'document'})</span>';
        sb.write('<li>$link${snippet.trim().isEmpty ? '' : '<div class="snippet">$snippet</div>'}</li>');
      }
      sb.write('</ul>');
    }
    return page('Search', sb.toString(), query: query);
  }

  String notFound(String what) => page('Not found', '<h1>Not found</h1><p class="lead">${esc(what)}</p>');
}

const stylesheet = '''
:root {
  --bg: #fbfaf7; --surface: #ffffff; --text: #1f1d1a; --muted: #6b665e;
  --line: #e2ded5; --link: #1a5a96; --mark: #fff1a8;
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #191817; --surface: #222120; --text: #ebe8e1; --muted: #a39e94;
          --line: #3a3835; --link: #8ab8e6; --mark: #6b5a00; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
       font: 17px/1.6 Georgia, "Iowan Old Style", "Times New Roman", serif; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
header { display: flex; flex-wrap: wrap; align-items: center; gap: 12px 24px;
         padding: 12px 24px; border-bottom: 1px solid var(--line); background: var(--surface);
         font-family: system-ui, sans-serif; font-size: 15px; }
header .site { font-weight: 600; color: var(--text); }
header nav { display: flex; gap: 16px; flex: 1; }
header input { font: inherit; padding: 6px 10px; border: 1px solid var(--line); border-radius: 6px;
               background: var(--bg); color: var(--text); width: 220px; max-width: 100%; }
main { max-width: 960px; margin: 0 auto; padding: 24px 24px 64px; }
h1 { font-size: 2em; font-weight: 500; line-height: 1.2; margin: 0 0 4px; }
h2 { font-size: 1.3em; font-weight: 500; margin: 1.8em 0 0.5em; padding-bottom: 4px;
     border-bottom: 1px solid var(--line); overflow: hidden; }
.lead, .years, .meta, .place, .empty, .snippet { color: var(--muted); }
.lead { margin: 0 0 1.2em; }
.years, .meta, .snippet { font-size: 0.88em; }
.place::before { content: " · "; }
.kind { font-variant: small-caps; letter-spacing: 0.03em; color: var(--muted); }
.empty { font-style: italic; }
.missing { color: var(--muted); font-style: italic; }
.infobox { float: right; width: 300px; margin: 0 0 16px 24px; padding: 12px; background: var(--surface);
           border: 1px solid var(--line); border-radius: 6px; font: 14px/1.45 system-ui, sans-serif; }
.infobox img { display: block; width: 100%; border-radius: 4px; margin-bottom: 10px; }
.infobox table { border-collapse: collapse; width: 100%; }
.infobox th { text-align: left; vertical-align: top; padding: 4px 10px 4px 0; color: var(--muted);
              font-weight: 500; white-space: nowrap; }
.infobox td { padding: 4px 0; }
.prose { white-space: normal; }
.prose p { margin: 0 0 1em; }
.timeline { border-collapse: collapse; }
.timeline th { text-align: right; vertical-align: top; padding: 4px 16px 4px 0; font-weight: 400;
               color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
.timeline td { padding: 4px 0; }
.surnames { columns: 3 220px; column-gap: 32px; }
.surnames section { break-inside: avoid; margin-bottom: 16px; }
.surnames h2 { margin-top: 0; font-size: 1.1em; }
.surnames ul, .results { list-style: none; padding: 0; margin: 0; }
.results li { margin-bottom: 12px; }
mark { background: var(--mark); color: inherit; }
.gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 16px; }
.gallery a { display: block; font: 13px/1.35 system-ui, sans-serif; color: var(--text);
             overflow-wrap: anywhere; }
.gallery img, .gallery .file { display: block; width: 100%; aspect-ratio: 1; object-fit: cover;
                               border-radius: 4px; border: 1px solid var(--line); margin-bottom: 6px; }
.gallery .file { display: grid; place-items: center; background: var(--surface); color: var(--muted);
                 font-weight: 600; letter-spacing: 0.05em; }
.media img { max-width: 100%; max-height: 80vh; border: 1px solid var(--line); border-radius: 4px; }
.description { white-space: pre-line; }
.problems { font: 14px/1.4 system-ui, sans-serif; margin-bottom: 16px; }
@media (max-width: 640px) {
  .infobox { float: none; width: auto; margin: 0 0 16px; }
  main { padding: 16px 16px 48px; }
}
''';
