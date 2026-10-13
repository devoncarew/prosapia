// The page editor: the text on the left, a live preview on the right. The
// server renders the preview, so it matches the saved page exactly.

const form = document.querySelector<HTMLFormElement>('form.editor')!;
const source = document.getElementById('source') as HTMLTextAreaElement;
const preview = document.getElementById('preview')!;
const previewUrl = form.dataset.preview!;

const original = source.value;
let timer: number | undefined;
let latest = 0;

async function refresh(): Promise<void> {
  const request = ++latest;
  const response = await fetch(previewUrl, {
    method: 'POST',
    headers: { 'content-type': 'text/plain' },
    body: source.value,
  });
  const html = await response.text();
  // A slower, older request must not overwrite a newer preview.
  if (request !== latest) return;
  preview.innerHTML = html;
  preview.classList.remove('stale');
}

source.addEventListener('input', () => {
  preview.classList.add('stale');
  window.clearTimeout(timer);
  timer = window.setTimeout(() => void refresh(), 400);
});

// Typing Tab in the facts block should indent, not leave the box.
source.addEventListener('keydown', (event) => {
  if (event.key !== 'Tab' || event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return;
  event.preventDefault();
  source.setRangeText('  ', source.selectionStart, source.selectionEnd, 'end');
  source.dispatchEvent(new Event('input'));
});

// Warn before losing unsaved text, except when the form itself is saving.
let saving = false;
form.addEventListener('submit', () => {
  saving = true;
});
window.addEventListener('beforeunload', (event) => {
  if (!saving && source.value !== original) event.preventDefault();
});
