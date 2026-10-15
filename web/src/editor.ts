// The page editor, with Write and Preview tabs.
// The text is plain: facts as "Label: value" lines, then the story. The
// editor helps without hiding that: it highlights labels, @ references and
// marked dates and places; it completes people after @, places inside
// [place: …] and labels at the start of a fact line; and it keeps unsaved
// text if the tab is closed.

import {
  autocompletion,
  type Completion,
  type CompletionContext,
  type CompletionResult,
} from '@codemirror/autocomplete';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { EditorState, RangeSetBuilder } from '@codemirror/state';
import {
  Decoration,
  type DecorationSet,
  EditorView,
  keymap,
  ViewPlugin,
  type ViewUpdate,
} from '@codemirror/view';

const form = document.querySelector<HTMLFormElement>('form.editor')!;
const textarea = document.getElementById('source') as HTMLTextAreaElement;
const preview = document.getElementById('preview')!;
const previewUrl = form.dataset.preview!;
const basedOn = form.querySelector<HTMLInputElement>(
  'input[name=based_on]',
)!.value;
const original = textarea.value;
const draftKey = `prosapia.draft.${location.pathname}`;

// ------------------------------------------------------------- highlighting

/** The line numbers of the facts block: from a first "Name:" line to the first blank line. */
function factLines(state: EditorState): Set<number> {
  const lines = new Set<number>();
  let n = 1;
  while (n <= state.doc.lines && state.doc.line(n).text.trim() === '') n++;
  if (n > state.doc.lines || !/^\s*name\s*:/i.test(state.doc.line(n).text))
    return lines;
  for (; n <= state.doc.lines && state.doc.line(n).text.trim() !== ''; n++)
    lines.add(n);
  return lines;
}

const marks = {
  label: Decoration.mark({ class: 'cm-label' }),
  ref: Decoration.mark({ class: 'cm-ref' }),
  marked: Decoration.mark({ class: 'cm-marked' }),
  heading: Decoration.mark({ class: 'cm-heading' }),
};

function decorate(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const facts = factLines(view.state);
  for (const { from, to } of view.visibleRanges) {
    let pos = from;
    while (pos <= to) {
      const line = view.state.doc.lineAt(pos);
      const found: [number, number, Decoration][] = [];
      if (facts.has(line.number)) {
        const label = /^\s*[A-Za-z][A-Za-z ]{0,30}?\s*:/.exec(line.text);
        if (label)
          found.push([line.from, line.from + label[0].length, marks.label]);
      } else if (/^#{1,6} /.test(line.text)) {
        found.push([line.from, line.to, marks.heading]);
      }
      for (const m of line.text.matchAll(
        /(?<![\w@.])@[a-z0-9]+(?:-[a-z0-9]+)*/g,
      )) {
        found.push([
          line.from + m.index,
          line.from + m.index + m[0].length,
          marks.ref,
        ]);
      }
      for (const m of line.text.matchAll(/\[\s*(?:date|place)\s*:[^\]]*\]/gi)) {
        found.push([
          line.from + m.index,
          line.from + m.index + m[0].length,
          marks.marked,
        ]);
      }
      found.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
      let last = -1;
      for (const [start, end, mark] of found) {
        if (start < last) continue; // skip overlaps
        builder.add(start, end, mark);
        last = end;
      }
      pos = line.to + 1;
    }
  }
  return builder.finish();
}

const highlighter = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = decorate(view);
    }
    update(update: ViewUpdate): void {
      if (update.docChanged || update.viewportChanged)
        this.decorations = decorate(update.view);
    }
  },
  { decorations: (v) => v.decorations },
);

// --------------------------------------------------------------- completion

interface PersonSuggestion {
  ref: string;
  name: string;
  detail: string;
}

async function people(
  context: CompletionContext,
): Promise<CompletionResult | null> {
  // "@" followed by part of a name, which may include one space.
  const word = context.matchBefore(/@[\p{L}\p{N}-]*(?: [\p{L}\p{N}]*)?/u);
  if (!word || (word.text.length < 2 && !context.explicit)) return null;
  const query = word.text.slice(1);
  if (query.length === 0) return null;
  const response = await fetch(`/api/people?q=${encodeURIComponent(query)}`);
  if (!response.ok) return null;
  const found = (await response.json()) as PersonSuggestion[];
  return {
    from: word.from,
    filter: false,
    options: found.map((p): Completion => ({
      label: p.name,
      detail: p.detail,
      apply: p.ref,
    })),
  };
}

async function places(
  context: CompletionContext,
): Promise<CompletionResult | null> {
  const inside = context.matchBefore(/\[\s*place\s*:\s*[^\]]*/i);
  if (!inside) return null;
  const typed = /:\s*(.*)$/.exec(inside.text)![1];
  const from = inside.to - typed.length;
  const response = await fetch(`/api/places?q=${encodeURIComponent(typed)}`);
  if (!response.ok) return null;
  const found = (await response.json()) as string[];
  const closed = context.state.sliceDoc(context.pos, context.pos + 1) === ']';
  return {
    from,
    filter: false,
    options: found.map((place) => ({
      label: place,
      apply: closed ? place : `${place}]`,
    })),
  };
}

const vocabulary = [
  'Name',
  'Also known as',
  'Sex',
  'Born',
  'Christened',
  'Died',
  'Buried',
  'Parents',
  'Children',
  'Partner',
  'Siblings',
  'Married',
  'Divorced',
  'Occupation',
  'Education',
  'Residence',
  'Degree',
  'Graduated',
  'Title',
  'Note',
];

function labels(context: CompletionContext): CompletionResult | null {
  const line = context.state.doc.lineAt(context.pos);
  if (!factLines(context.state).has(line.number) && line.text.trim() !== '')
    return null;
  const word = context.matchBefore(/^[A-Za-z][A-Za-z ]*/);
  if (!word || word.from !== line.from || line.text.includes(':')) return null;
  return {
    from: word.from,
    options: vocabulary.map((label) => ({
      label,
      apply: `${label}: `,
    })),
  };
}

// ------------------------------------------------------------- write/preview

const writeTab = document.getElementById('tab-write')!;
const previewTab = document.getElementById('tab-preview')!;
const writePanel = document.getElementById('panel-write')!;
const previewPanel = document.getElementById('panel-preview')!;
let previewed = original;

async function showPreview(): Promise<void> {
  const text = view.state.doc.toString();
  if (text === previewed) return;
  preview.classList.add('stale');
  const response = await fetch(previewUrl, {
    method: 'POST',
    headers: { 'content-type': 'text/plain' },
    body: text,
  });
  preview.innerHTML = await response.text();
  previewed = text;
  preview.classList.remove('stale');
}

function select(tab: 'write' | 'preview'): void {
  const writing = tab === 'write';
  writeTab.setAttribute('aria-selected', String(writing));
  previewTab.setAttribute('aria-selected', String(!writing));
  writePanel.hidden = !writing;
  previewPanel.hidden = writing;
  if (writing) view.focus();
  else void showPreview();
}

// ------------------------------------------------------------------- drafts

interface Draft {
  basedOn: string;
  text: string;
  savedAt: number;
}

function readDraft(): Draft | null {
  try {
    const raw = localStorage.getItem(draftKey);
    return raw ? (JSON.parse(raw) as Draft) : null;
  } catch {
    return null;
  }
}

function writeDraft(text: string): void {
  try {
    if (text === original) localStorage.removeItem(draftKey);
    else
      localStorage.setItem(
        draftKey,
        JSON.stringify({ basedOn, text, savedAt: Date.now() }),
      );
  } catch {
    // Storage may be unavailable; the draft is a convenience only.
  }
}

function clearDraft(): void {
  try {
    localStorage.removeItem(draftKey);
  } catch {
    // ignore
  }
}

// ------------------------------------------------------------------- set up

const view = new EditorView({
  parent: textarea.parentElement!,
  state: EditorState.create({
    doc: original,
    extensions: [
      history(),
      keymap.of([
        // Save with Cmd+Enter or Ctrl+Enter, as on GitHub.
        { key: 'Mod-Enter', run: () => (form.requestSubmit(), true) },
        ...defaultKeymap,
        ...historyKeymap,
      ]),
      EditorView.lineWrapping,
      EditorView.contentAttributes.of({
        spellcheck: 'true',
        'aria-label': 'Page text',
      }),
      highlighter,
      autocompletion({
        override: [people, places, labels],
        activateOnTyping: true,
      }),
      EditorView.updateListener.of((update) => {
        if (!update.docChanged) return;
        const text = update.state.doc.toString();
        textarea.value = text;
        writeDraft(text);
      }),
    ],
  }),
});
textarea.hidden = true;
textarea.after(view.dom);
writeTab.addEventListener('click', () => select('write'));
previewTab.addEventListener('click', () => select('preview'));
document.getElementById('summary')!.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && (event.metaKey || event.ctrlKey))
    form.requestSubmit();
});

// Offer back any unsaved text from a closed tab.
const draft = readDraft();
if (draft && draft.text !== original) {
  const notice = document.createElement('p');
  notice.className = 'message draft';
  const when = new Date(draft.savedAt).toLocaleString();
  notice.textContent =
    draft.basedOn === basedOn
      ? `Your unsaved changes from ${when} have been brought back. `
      : `You have unsaved changes from ${when}, made to an earlier version of this page. `;
  const use = document.createElement('button');
  use.type = 'button';
  const discard = document.createElement('button');
  discard.type = 'button';
  discard.textContent = 'Discard them';
  const apply = (text: string): void =>
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: text },
    });
  if (draft.basedOn === basedOn) {
    apply(draft.text);
  } else {
    use.textContent = 'Use them anyway';
    use.addEventListener('click', () => {
      apply(draft.text);
      notice.remove();
    });
    notice.append(use, ' ');
  }
  discard.addEventListener('click', () => {
    apply(original);
    clearDraft();
    notice.remove();
  });
  notice.append(discard);
  form.before(notice);
}

let saving = false;
form.addEventListener('submit', () => {
  textarea.value = view.state.doc.toString();
  saving = true;
  clearDraft();
});
window.addEventListener('beforeunload', (event) => {
  if (!saving && view.state.doc.toString() !== original) event.preventDefault();
});
