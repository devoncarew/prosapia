// A person's page. Edit opens the editor in place of the page's content,
// as editing a comment does on GitHub; Discard puts the page back. The
// editor's code is loaded only when it is first needed.

import type { Mounted } from './editor';

const edit = document.querySelector<HTMLAnchorElement>('a[data-edit]');
const actions = document.querySelector<HTMLElement>('main > .actions');
const article = document.querySelector<HTMLElement>('article.person');
const memory = document.getElementById('add-memory');
let open: { box: HTMLElement; mounted: Mounted } | null = null;

async function startEditing(push: boolean): Promise<void> {
  if (open || !edit || !article) return;
  const response = await fetch(edit.dataset.edit!);
  if (!response.ok) {
    location.href = edit.href; // the page with the editor open
    return;
  }
  const box = document.createElement('div');
  box.className = 'editing';
  box.innerHTML = await response.text();
  article.replaceWith(box);
  if (actions) actions.hidden = true;
  if (memory) memory.hidden = true;
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
  if (!open || !article) return true;
  if (
    open.mounted.changed() &&
    !confirm('Discard your changes to this page?')
  ) {
    return false;
  }
  open.mounted.unmount();
  open.box.replaceWith(article);
  if (actions) actions.hidden = false;
  if (memory) memory.hidden = false;
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

// "Add a memory" goes to the box at the end of the page.
document
  .querySelector('a[href="#add-memory"]')
  ?.addEventListener('click', () => {
    setTimeout(() => document.getElementById('title')?.focus());
  });
