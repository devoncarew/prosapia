// The page editor, with Write and Preview tabs.
// The text is plain: facts as "Label: value" lines, then the story. The
// editor helps without hiding that: it highlights labels, @ references,
// quoted values and marked dates and places; it completes people after @,
// places after place: and labels at the start of a fact line; and it asks
// before leaving with changes unsaved. When the tree allows it, Claude can
// draft the story, or work new information into it: its text replaces the
// story as one step, so undo restores the original.

import {
  autocompletion,
  startCompletion,
  type Completion,
  type CompletionContext,
  type CompletionResult,
} from '@codemirror/autocomplete';
import {
  defaultKeymap,
  history,
  historyKeymap,
  isolateHistory,
  undo,
} from '@codemirror/commands';
import {
  Compartment,
  EditorState,
  RangeSetBuilder,
  StateEffect,
  StateField,
} from '@codemirror/state';
import {
  Decoration,
  type DecorationSet,
  EditorView,
  keymap,
  ViewPlugin,
  type ViewUpdate,
} from '@codemirror/view';

import { busy, spinner } from './busy';

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
  quoted: Decoration.mark({ class: 'cm-quoted' }),
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
        // A fact's label, unless the line carries on the fact above it.
        const label = /^[A-Za-z][A-Za-z ]{0,30}?\s*:/.exec(line.text);
        if (label)
          found.push([line.from, line.from + label[0].length, marks.label]);
        // A part's label, and quoted values.
        for (const m of line.text.matchAll(
          /(?:^\s+|,\s*|:\s*)((?:date|place|source)\s*:)/gi,
        )) {
          const at = m.index + m[0].length - m[1].length;
          found.push([
            line.from + at,
            line.from + at + m[1].length,
            marks.marked,
          ]);
        }
        for (const m of line.text.matchAll(/"(?:[^"]|"")*"/g)) {
          found.push([
            line.from + m.index,
            line.from + m.index + m[0].length,
            marks.quoted,
          ]);
        }
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
  // In a fact line, "place: " and a place, perhaps opening a quote.
  const part = context.matchBefore(/\bplace\s*:\s*"?[^",\]]*/i);
  if (part && !part.text.startsWith('[')) {
    const typed = /:\s*"?(.*)$/.exec(part.text)![1];
    const opened = /:\s*"/.test(part.text);
    const response = await fetch(`/api/places?q=${encodeURIComponent(typed)}`);
    if (!response.ok) return null;
    const found = (await response.json()) as string[];
    return {
      from: part.to - typed.length - (opened ? 1 : 0),
      filter: false,
      options: found.map((place) => ({
        label: place,
        apply: place.includes(',') || opened ? `"${place}"` : place,
      })),
    };
  }
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
  'Nickname',
  'Also known as',
  'Family name',
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

// ------------------------------------------------------------------ toolbar

/** The formatting buttons above the text, as on GitHub. */
function toolbar(form: HTMLFormElement, view: EditorView): void {
  form.querySelector('.format')?.addEventListener('click', (event) => {
    const tidy = (event.target as HTMLElement).closest<HTMLButtonElement>(
      'button[data-tidy]',
    );
    if (tidy) {
      void tidyText(view, tidy);
      return;
    }
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>(
      'button[data-format]',
    );
    if (!button) return;
    format(view, button.dataset.format!);
    view.focus();
  });
}

/**
 * Replaces the text with what the server would save: the page's normal
 * form. One step, so undo puts the text back as it was.
 */
async function tidyText(view: EditorView, button: HTMLButtonElement) {
  button.disabled = true;
  try {
    const response = await fetch(button.dataset.tidy!, {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: view.state.doc.toString(),
    });
    if (!response.ok) return;
    const tidied = await response.text();
    if (tidied !== view.state.doc.toString()) {
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: tidied },
        // Its own undo step, apart from what was typed just before.
        annotations: isolateHistory.of('full'),
      });
    }
  } finally {
    button.disabled = false;
    view.focus();
  }
}

function format(view: EditorView, kind: string): void {
  const { from, to } = view.state.selection.main;
  const text = view.state.sliceDoc(from, to);
  // Wraps the selection, or a placeholder to type over, and selects it.
  const wrap = (before: string, after: string, placeholder: string) => {
    const inner = text || placeholder;
    view.dispatch({
      changes: { from, to, insert: before + inner + after },
      selection: {
        anchor: from + before.length,
        head: from + before.length + inner.length,
      },
    });
  };
  // Starts each selected line with [mark], or removes it if all have it.
  const lines = (mark: string) => {
    const first = view.state.doc.lineAt(from).number;
    const last = view.state.doc.lineAt(to).number;
    const all = [];
    for (let n = first; n <= last; n++) all.push(view.state.doc.line(n));
    const remove = all.every((l) => l.text.startsWith(mark));
    view.dispatch({
      changes: all.map((l) =>
        remove
          ? { from: l.from, to: l.from + mark.length, insert: '' }
          : { from: l.from, insert: mark },
      ),
    });
  };
  switch (kind) {
    case 'bold':
      return wrap('**', '**', 'bold text');
    case 'italic':
      return wrap('_', '_', 'italic text');
    case 'heading':
      return lines('## ');
    case 'list':
      return lines('- ');
    case 'link': {
      const label = text || 'link text';
      const insert = `[${label}](https://)`;
      const at = from + label.length + 3;
      view.dispatch({
        changes: { from, to, insert },
        selection: { anchor: at, head: at + 8 },
      });
      return;
    }
    case 'person':
      view.dispatch({
        changes: { from, to, insert: '@' },
        selection: { anchor: from + 1 },
      });
      return;
    case 'date':
      return wrap('[date: ', ']', 'about 1925');
    case 'place':
      wrap('[place: ', ']', '');
      startCompletion(view);
      return;
  }
}

// ------------------------------------------------------------------- mount

/** An editor on the page, which can be taken down again. */
export interface Mounted {
  /** Whether the text differs from what the page had. */
  changed(): boolean;

  /** Removes the editor. */
  unmount(): void;
}

/**
 * Sets up the editor in [form]: on the editing page, or in place on a
 * person's page when Edit is chosen there.
 */
export function mount(form: HTMLFormElement): Mounted {
  const textarea = document.getElementById('source') as HTMLTextAreaElement;
  const preview = document.getElementById('preview')!;
  const previewUrl = form.dataset.preview!;
  const original = textarea.value;

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

  // ------------------------------------------------------------ help from Claude

  const helpButtons = document.querySelector<HTMLElement>('.help[data-url]');
  const panel = document.querySelector<HTMLElement>('.draft-panel');
  const helpBar = document.querySelector<HTMLElement>('.help-bar');
  const helpedBy = form.querySelector<HTMLInputElement>(
    'input[name=helped_by]',
  )!;
  const editable = new Compartment();

  /** Marks the lines Claude wrote or changed, until kept or undone. */
  const markHelped = StateEffect.define<number[]>();
  const helpedLine = Decoration.line({ class: 'cm-helped' });
  const helpedField = StateField.define<DecorationSet>({
    create: () => Decoration.none,
    update(marks, tr) {
      for (const e of tr.effects) {
        if (e.is(markHelped)) {
          return Decoration.set(e.value.map((at) => helpedLine.range(at)));
        }
      }
      // An undo takes Claude's text away, and the marks with it.
      if (tr.isUserEvent('undo')) return Decoration.none;
      return marks.map(tr.changes);
    },
    provide: (f) => EditorView.decorations.from(f),
  });

  /** Where the story starts: after the facts block and the blank line. */
  function storyStart(state: EditorState): number {
    const facts = factLines(state);
    if (facts.size === 0) return 0;
    const last = state.doc.line(Math.max(...facts));
    return Math.min(state.doc.length, last.to);
  }

  function storyIsEmpty(state: EditorState): boolean {
    return state.sliceDoc(storyStart(state)).trim() === '';
  }

  function bar(
    message: string,
    actions: [string, () => void][] = [],
    error = false,
    working = false,
  ): void {
    if (!helpBar) return;
    helpBar.replaceChildren(...(working ? [spinner()] : []), message);
    helpBar.classList.toggle('error', error);
    for (const [label, run] of actions) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = label;
      button.addEventListener('click', run);
      helpBar.append(' ', button);
    }
    helpBar.hidden = false;
  }

  function hideBar(): void {
    if (helpBar) helpBar.hidden = true;
  }

  /** Shows the Draft panel, with a suggestion when there is no story. */
  function openPanel(): void {
    if (!panel) return;
    hideBar();
    const instruction = panel.querySelector<HTMLInputElement>('.instruction')!;
    if (!instruction.value && storyIsEmpty(view.state)) {
      instruction.value = panel.dataset.first ?? '';
    }
    panel.hidden = false;
    instruction.focus();
    instruction.select();
  }

  function closePanel(): void {
    if (panel) panel.hidden = true;
  }

  interface HelpReply {
    text?: string;
    changed?: number[];
    drawnFrom?: string[];
    model?: string;
    modelName?: string;
    error?: string;
  }

  /** Asks Claude to rewrite the story as the Draft panel says. */
  async function askClaude(): Promise<void> {
    if (!panel) return;
    const instruction =
      panel.querySelector<HTMLInputElement>('.instruction')!.value;
    const notes = panel.querySelector<HTMLTextAreaElement>('.notes')!.value;
    const state = view.state;
    const [replaceFrom, replaceTo] = [storyStart(state), state.doc.length];
    const before = helpedBy.value;
    closePanel();
    bar('Claude is writing…', [], false, true);
    busy(view.dom, true);
    view.dispatch({
      effects: editable.reconfigure(EditorView.editable.of(false)),
    });
    helpButtons?.querySelectorAll('button').forEach((b) => (b.disabled = true));
    let reply: HelpReply;
    try {
      const response = await fetch(helpButtons!.dataset.url!, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          source: state.doc.toString(),
          instruction,
          notes,
        }),
      });
      reply = (await response.json()) as HelpReply;
    } catch {
      reply = {
        error: 'Claude could not be reached just now. Please try again.',
      };
    } finally {
      busy(view.dom, false);
      view.dispatch({
        effects: editable.reconfigure(EditorView.editable.of(true)),
      });
      helpButtons
        ?.querySelectorAll('button')
        .forEach((b) => (b.disabled = false));
    }
    if (reply.error || reply.text === undefined) {
      bar(reply.error ?? 'Something went wrong.', [['Close', hideBar]], true);
      return;
    }

    // The story is separated from the facts by one blank line.
    const lead = replaceFrom === 0 ? '' : '\n\n';
    const insert = `${lead}${reply.text.trim()}\n`;
    const start = replaceFrom + lead.length;
    // The lines Claude added or changed, counted from the story's first.
    const first =
      view.state.doc.lineAt(Math.min(replaceFrom, view.state.doc.length))
        .number + (lead ? 2 : 0);
    view.dispatch({
      changes: { from: replaceFrom, to: replaceTo, insert },
      userEvent: 'input.help',
      scrollIntoView: true,
    });
    const doc = view.state.doc;
    const lines = (reply.changed ?? [])
      .map((n) => first + n)
      .filter((n) => n >= 1 && n <= doc.lines)
      .map((n) => doc.line(n).from)
      .filter((at) => at >= start);
    view.dispatch({ effects: markHelped.of(lines) });
    helpedBy.value = reply.model ?? '';
    const keep = () => {
      view.dispatch({ effects: markHelped.of([]) });
      hideBar();
    };
    const count = lines.length;
    bar(
      `${reply.modelName ?? 'Claude'} ${
        count === 0
          ? 'made no changes to the story.'
          : `wrote or changed the ${count === 1 ? 'marked line' : `${count} marked lines`}.`
      } ⌘Z or Undo restores what was there.`,
      [
        [
          'Undo',
          () => {
            undo(view);
            helpedBy.value = before;
            hideBar();
          },
        ],
        ['Keep', keep],
      ],
    );
    // Where a first draft found facts elsewhere in the tree, to check.
    if (reply.drawnFrom?.length && helpBar) {
      const sources = document.createElement('div');
      sources.className = 'drawn-from';
      const list = document.createElement('ul');
      for (const item of reply.drawnFrom) {
        const li = document.createElement('li');
        li.textContent = item;
        list.append(li);
      }
      sources.append('Drawn from elsewhere in the tree:', list);
      helpBar.append(sources);
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
        helpedField,
        editable.of(EditorView.editable.of(true)),
        autocompletion({
          override: [people, places, labels],
          activateOnTyping: true,
        }),
        EditorView.updateListener.of((update) => {
          if (update.transactions.some((tr) => tr.isUserEvent('undo')))
            hideBar();
          if (!update.docChanged) return;
          const text = update.state.doc.toString();
          textarea.value = text;
        }),
      ],
    }),
  });
  textarea.hidden = true;
  textarea.after(view.dom);
  helpButtons
    ?.querySelector('button[data-request=draft]')
    ?.addEventListener('click', openPanel);
  panel
    ?.querySelector('button.go')
    ?.addEventListener('click', () => void askClaude());
  panel?.querySelector('button.cancel')?.addEventListener('click', closePanel);
  panel?.querySelector('.instruction')?.addEventListener('keydown', (event) => {
    if ((event as KeyboardEvent).key === 'Enter') {
      event.preventDefault();
      void askClaude();
    }
  });
  writeTab.addEventListener('click', () => select('write'));
  previewTab.addEventListener('click', () => select('preview'));

  let saving = false;
  form.addEventListener('submit', () => {
    textarea.value = view.state.doc.toString();
    saving = true;
  });
  const guard = (event: BeforeUnloadEvent): void => {
    if (!saving && view.state.doc.toString() !== original)
      event.preventDefault();
  };
  window.addEventListener('beforeunload', guard);

  toolbar(form, view);

  return {
    changed: () => view.state.doc.toString() !== original,
    unmount: () => {
      window.removeEventListener('beforeunload', guard);
      view.destroy();
    },
  };
}

// On a page that already holds the editor, start it. An editor opened in
// place on a person's page is started by that page's script instead.
const existing = document.querySelector<HTMLFormElement>(
  'form.editor:not([data-in-place])',
);
if (existing) mount(existing);
