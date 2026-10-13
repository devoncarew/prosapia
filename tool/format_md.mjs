// Formats the repository's markdown: prose wrapped at the configured width
// (see .prettierrc.json), by Prettier, with one change to what Prettier does.
//
// Prettier pads every table so its columns line up. That reads well for a
// small table, but a table with long cells becomes lines hundreds of
// characters wide, and changing one cell re-pads every row. So a table that
// does not fit within the line width is written compactly instead, one space
// around each cell.
//
//   node tool/format_md.mjs           format every markdown file
//   node tool/format_md.mjs --check   report files that are not formatted

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import * as prettier from 'prettier';

const check = process.argv.includes('--check');

/** Splits a table row into its cells, ignoring pipes that are escaped or in code. */
function cells(row) {
  const out = [];
  let cell = '';
  let inCode = false;
  const inner = row.trim().replace(/^\|/, '').replace(/\|$/, '');
  for (let i = 0; i < inner.length; i++) {
    const c = inner[i];
    if (c === '\\' && i + 1 < inner.length) {
      cell += c + inner[++i];
    } else if (c === '`') {
      inCode = !inCode;
      cell += c;
    } else if (c === '|' && !inCode) {
      out.push(cell.trim());
      cell = '';
    } else {
      cell += c;
    }
  }
  out.push(cell.trim());
  return out;
}

/** `:-----:` becomes `:---:`; the alignment colons are kept. */
function compactRow(row) {
  const compact = cells(row).map((c) => (/^:?-+:?$/.test(c) ? c.replace(/-+/, '---') : c));
  return `| ${compact.join(' | ')} |`;
}

/** Rewrites the tables in [text] that are wider than [width] in compact form. */
function compactWideTables(text, width) {
  const lines = text.split('\n');
  let fence = null;
  for (let i = 0; i < lines.length; i++) {
    const marker = lines[i].match(/^\s*(```+|~~~+)/);
    if (marker) {
      if (fence === null) fence = marker[1][0];
      else if (marker[1][0] === fence) fence = null;
      continue;
    }
    if (fence !== null || !lines[i].startsWith('|')) continue;
    let end = i;
    while (end < lines.length && lines[end].startsWith('|')) end++;
    if (lines.slice(i, end).some((line) => line.length > width)) {
      for (let j = i; j < end; j++) lines[j] = compactRow(lines[j]);
    }
    i = end - 1;
  }
  return lines.join('\n');
}

const files = execFileSync(
  'git',
  ['ls-files', '--cached', '--others', '--exclude-standard', '*.md'],
  { encoding: 'utf8' },
)
  .split('\n')
  .filter(Boolean);

const unformatted = [];
for (const file of files) {
  const info = await prettier.getFileInfo(file, { ignorePath: '.prettierignore' });
  if (info.ignored) continue;
  const options = await prettier.resolveConfig(file);
  const source = readFileSync(file, 'utf8');
  const formatted = compactWideTables(
    await prettier.format(source, { ...options, filepath: file }),
    options.printWidth,
  );
  if (formatted === source) continue;
  unformatted.push(file);
  if (!check) writeFileSync(file, formatted);
}

if (check && unformatted.length > 0) {
  console.error(`Not formatted:\n${unformatted.map((f) => `  ${f}`).join('\n')}`);
  console.error('Run "npm run format:md" to fix.');
  process.exit(1);
}
console.log(
  check
    ? 'All markdown files are formatted.'
    : unformatted.length === 0
      ? 'Nothing to change.'
      : `Formatted ${unformatted.length} files:\n${unformatted.map((f) => `  ${f}`).join('\n')}`,
);
