// A person's page. Edit opens the editor in place of the story, as editing
// an issue does on GitHub: the title and the facts stay where they are, and
// Discard puts the story back. The editor's code is loaded only when it is
// first needed.

import { busy, spinner } from './busy';
import type { Mounted } from './editor';

const edit = document.querySelector<HTMLAnchorElement>('a[data-edit]');
const actions = document.querySelector<HTMLElement>('.person-head .actions');
const article = document.querySelector<HTMLElement>('main > article.person');
const body = article?.querySelector<HTMLElement>('.person-body');
const edited = document.querySelector<HTMLElement>('main > .edited');
let open: { box: HTMLElement; mounted: Mounted } | null = null;

async function startEditing(push: boolean): Promise<void> {
  if (open || !edit || !article || !body) return;
  const response = await fetch(edit.dataset.edit!);
  if (!response.ok) {
    location.href = edit.href; // the page with the editor open
    return;
  }
  const box = document.createElement('div');
  box.className = 'editing';
  box.innerHTML = await response.text();
  body.replaceWith(box);
  article.classList.add('editing-on');
  if (actions) actions.hidden = true;
  if (edited) edited.hidden = true;
  // A path in a variable is left for the browser to load, not bundled.
  const editorScript = '/assets/editor.js';
  const { mount } = (await import(editorScript)) as typeof import('./editor');
  open = { box, mounted: mount(box.querySelector('form.editor')!) };
  box.querySelector('a.discard')?.addEventListener('click', (event) => {
    event.preventDefault();
    stopEditing(true);
  });
  if (push) history.pushState({ editing: true }, '', edit.href);
  box.querySelector<HTMLElement>('.cm-content')?.focus();
}

/** Closes the editor, after asking if it holds changes. */
function stopEditing(push: boolean): boolean {
  if (!open || !article || !body) return true;
  if (
    open.mounted.changed() &&
    !confirm('Discard your changes to this page?')
  ) {
    return false;
  }
  open.mounted.unmount();
  open.box.replaceWith(body);
  article.classList.remove('editing-on');
  if (actions) actions.hidden = false;
  if (edited) edited.hidden = false;
  open = null;
  if (push) history.pushState({}, '', location.pathname);
  return true;
}

edit?.addEventListener('click', (event) => {
  // A modified click opens the editor in a new tab, as a link would.
  if (event.metaKey || event.ctrlKey || event.shiftKey) return;
  event.preventDefault();
  void startEditing(true);
});

// Back and Forward move between the page and its editor.
window.addEventListener('popstate', () => {
  const editing = new URLSearchParams(location.search).has('edit');
  if (editing && !open) void startEditing(false);
  else if (!editing && open && !stopEditing(false) && edit) {
    history.pushState({ editing: true }, '', edit.href);
  }
});

// The "more actions" menu closes on a click anywhere else, or on Escape.
const more = document.querySelector<HTMLDetailsElement>('details.more');
document.addEventListener('click', (event) => {
  if (more?.open && !more.contains(event.target as Node)) more.open = false;
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && more?.open) more.open = false;
});

// "Claude: Research ideas": where to look next, shown above the page.
// Nothing is saved; Copy puts the list on the clipboard.
const research = document.querySelector<HTMLElement>('[data-research]');
const ideas = document.querySelector<HTMLElement>('.research-ideas');

interface ResearchReply {
  text?: string;
  html?: string;
  modelName?: string;
  error?: string;
}

async function researchIdeas(): Promise<void> {
  if (!research || !ideas) return;
  const heading = document.createElement('h2');
  heading.textContent = 'Research ideas';
  const status = document.createElement('p');
  status.append(spinner(), 'Claude is looking at what the page has and lacks…');
  ideas.replaceChildren(heading, status);
  ideas.hidden = false;
  busy(ideas, true);
  ideas.scrollIntoView({ block: 'nearest' });
  let reply: ResearchReply;
  try {
    const response = await fetch(research.dataset.research!, {
      method: 'POST',
    });
    reply = (await response.json()) as ResearchReply;
  } catch {
    reply = {
      error: 'Claude could not be reached just now. Please try again.',
    };
  }
  busy(ideas, false);
  const close = document.createElement('button');
  close.type = 'button';
  close.textContent = 'Close';
  close.addEventListener('click', () => (ideas.hidden = true));
  const actions = document.createElement('p');
  actions.className = 'actions';
  if (reply.error || reply.html === undefined) {
    status.textContent = reply.error ?? 'Something went wrong.';
    actions.append(close);
    ideas.append(actions);
    return;
  }
  const list = document.createElement('div');
  list.className = 'prose';
  list.innerHTML = reply.html;
  const note = document.createElement('p');
  note.className = 'meta';
  note.textContent = `Suggestions by ${reply.modelName ?? 'Claude'}: where to look, not what you will find. Nothing here is saved.`;
  const copy = document.createElement('button');
  copy.type = 'button';
  copy.textContent = 'Copy';
  copy.addEventListener('click', () => {
    void navigator.clipboard.writeText(reply.text ?? '').then(() => {
      copy.textContent = 'Copied';
    });
  });
  actions.append(copy, ' ', close);
  ideas.replaceChildren(heading, list, note, actions);
}

research?.addEventListener('click', (event) => {
  event.preventDefault();
  void researchIdeas();
});
