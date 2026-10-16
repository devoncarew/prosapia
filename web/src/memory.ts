// "Claude: Tidy up" on the Add a memory form. The tidied text replaces what
// was typed; Undo puts it back. Nothing is saved until the memory is added.

import { busy, spinner } from './busy';

const form = document.querySelector<HTMLFormElement>('form.memory')!;
const tidy = form.querySelector<HTMLElement>('.tidy[data-url]')!;
const button = tidy.querySelector('button')!;
const bar = form.querySelector<HTMLElement>('.help-bar')!;
const text = form.querySelector<HTMLTextAreaElement>('#text')!;
const title = form.querySelector<HTMLInputElement>('#title')!;
const helpedBy = form.querySelector<HTMLInputElement>('input[name=helped_by]')!;

function show(
  message: string,
  actions: [string, () => void][] = [],
  working = false,
): void {
  bar.replaceChildren(...(working ? [spinner()] : []), message);
  for (const [label, run] of actions) {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = label;
    b.addEventListener('click', run);
    bar.append(' ', b);
  }
  bar.hidden = false;
}

interface HelpReply {
  text?: string;
  model?: string;
  modelName?: string;
  error?: string;
}

async function tidyUp(): Promise<void> {
  const original = text.value;
  button.disabled = true;
  text.readOnly = true;
  show('Claude is tidying…', [], true);
  busy(text, true);
  let reply: HelpReply;
  try {
    const response = await fetch(tidy.dataset.url!, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ title: title.value, text: original }),
    });
    reply = (await response.json()) as HelpReply;
  } catch {
    reply = {
      error: 'Claude could not be reached just now. Please try again.',
    };
  } finally {
    button.disabled = false;
    text.readOnly = false;
    busy(text, false);
  }
  if (reply.error || reply.text === undefined) {
    show(reply.error ?? 'Something went wrong.', [
      ['Close', () => (bar.hidden = true)],
    ]);
    return;
  }
  text.value = reply.text;
  text.classList.add('helped');
  helpedBy.value = reply.model ?? '';
  const done = () => {
    text.classList.remove('helped');
    bar.hidden = true;
  };
  show(`${reply.modelName ?? 'Claude'} tidied the memory.`, [
    [
      'Undo',
      () => {
        text.value = original;
        helpedBy.value = '';
        done();
      },
    ],
    ['Keep', done],
  ]);
}

button.addEventListener('click', () => void tidyUp());
