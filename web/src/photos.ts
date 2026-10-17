// Adding photos, and editing a photo's details. Each file is uploaded as
// soon as it is chosen, so it can be previewed and its back read by Claude
// before anything is added to the tree.

import { busy, spinner } from './busy';

interface Person {
  id: string;
  name: string;
  detail?: string;
}

/** Choosing people by typing part of a name, as in the editor. */
class PeoplePicker {
  private readonly people: Person[] = [];
  private readonly input = document.createElement('input');
  private readonly list = document.createElement('div');
  private found: Person[] = [];
  private active = 0;

  constructor(private readonly el: HTMLElement) {
    el.classList.add('ready');
    this.input.placeholder = 'Type a name';
    this.input.setAttribute('aria-label', 'Add a person');
    this.list.className = 'suggestions';
    this.list.hidden = true;
    el.append(this.input, this.list);
    for (const p of JSON.parse(el.dataset.initial ?? '[]') as Person[])
      this.add(p);
    this.input.addEventListener('input', () => void this.suggest());
    this.input.addEventListener('keydown', (e) => this.key(e));
    this.input.addEventListener('blur', () =>
      setTimeout(() => (this.list.hidden = true), 150),
    );
  }

  get ids(): string[] {
    return this.people.map((p) => p.id);
  }

  add(person: Person): void {
    if (this.people.some((p) => p.id === person.id)) return;
    // A picker for one person replaces whoever was chosen before.
    if (this.el.dataset.single === 'true') {
      this.people.length = 0;
      this.el.querySelectorAll('.chip').forEach((c) => c.remove());
    }
    this.people.push(person);
    const chip = document.createElement('span');
    chip.className = 'chip';
    chip.textContent = person.name;
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.textContent = '×';
    remove.setAttribute('aria-label', `Remove ${person.name}`);
    remove.addEventListener('click', () => {
      this.people.splice(this.people.indexOf(person), 1);
      chip.remove();
    });
    chip.append(remove);
    // In a plain form, each person is sent as a field of their own.
    if (this.el.dataset.name) {
      const hidden = document.createElement('input');
      hidden.type = 'hidden';
      hidden.name = this.el.dataset.name;
      hidden.value = person.id;
      chip.append(hidden);
    }
    this.el.insertBefore(chip, this.input);
  }

  private async suggest(): Promise<void> {
    const q = this.input.value.trim();
    if (q.length < 2) {
      this.list.hidden = true;
      return;
    }
    const response = await fetch(`/api/people?q=${encodeURIComponent(q)}`);
    if (!response.ok || q !== this.input.value.trim()) return;
    this.found = (await response.json()) as Person[];
    this.active = 0;
    this.render();
  }

  private render(): void {
    this.list.replaceChildren(
      ...this.found.map((p, i) => {
        const row = document.createElement('div');
        row.className = i === this.active ? 'active' : '';
        row.textContent = p.name;
        if (p.detail) {
          const detail = document.createElement('span');
          detail.textContent = p.detail;
          row.append(detail);
        }
        row.addEventListener('mousedown', (e) => {
          e.preventDefault();
          this.choose(p);
        });
        return row;
      }),
    );
    this.list.hidden = this.found.length === 0;
  }

  private choose(person: Person): void {
    this.add(person);
    this.input.value = '';
    this.found = [];
    this.list.hidden = true;
    this.input.focus();
  }

  private key(e: KeyboardEvent): void {
    if (this.list.hidden) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const n = this.found.length;
      this.active = (this.active + (e.key === 'ArrowDown' ? 1 : n - 1)) % n;
      this.render();
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const p = this.found[this.active];
      if (p) this.choose(p);
    } else if (e.key === 'Escape') {
      this.list.hidden = true;
    }
  }
}

interface Reply {
  token?: string;
  kind?: string;
  title?: string;
  date?: string;
  text?: string;
  pages?: number;
  location?: string;
  error?: string;
}

async function post(url: string, body: BodyInit, json = true): Promise<Reply> {
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: json ? { 'content-type': 'application/json' } : {},
      body,
    });
    return (await response.json()) as Reply;
  } catch {
    return { error: 'The server could not be reached. Please try again.' };
  }
}

/**
 * Sends [file] to be staged, reporting how much of it has gone, from 0 to
 * 1; fetch cannot report an upload's progress.
 */
function sendFile(
  file: File,
  progress: (sent: number) => void,
): Promise<Reply> {
  return new Promise((resolve) => {
    const request = new XMLHttpRequest();
    request.open('POST', '/media/staging');
    request.upload.addEventListener('progress', (event) => {
      if (event.lengthComputable) progress(event.loaded / event.total);
    });
    request.addEventListener('load', () => {
      try {
        resolve(JSON.parse(request.responseText) as Reply);
      } catch {
        resolve({ error: 'The upload failed.' });
      }
    });
    request.addEventListener('error', () =>
      resolve({ error: 'The server could not be reached. Please try again.' }),
    );
    request.send(file);
  });
}

function element<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  props: Partial<HTMLElementTagNameMap[K]> = {},
  ...children: (Node | string)[]
): HTMLElementTagNameMap[K] {
  const el = Object.assign(document.createElement(tag), props);
  el.append(...children);
  return el;
}

/** A field with a label, for a photo card. */
function field(label: string, input: HTMLInputElement | HTMLTextAreaElement) {
  const id = `f${Math.random().toString(36).slice(2)}`;
  input.id = id;
  return [element('label', { htmlFor: id }, label), input];
}

/**
 * Offers Claude's reading of a photo, its back or a document, with a way to
 * put the text back. A document is read a page at a time, each its own
 * request, so a long one does not run into the server's time limit.
 */
function transcribeButton(
  text: HTMLTextAreaElement,
  request: () => Record<string, string | boolean>,
): HTMLElement {
  const button = element('button', {
    type: 'button',
    className: 'transcribe',
    textContent: 'Claude: Transcribe',
  });
  const status = element('span', { className: 'status' });
  button.addEventListener('click', () => {
    void (async () => {
      const before = text.value;
      button.disabled = true;
      busy(text, true);
      const read: string[] = [];
      let pages = 1;
      let error: string | undefined;
      for (let page = 1; page <= pages; page++) {
        status.replaceChildren(
          ' ',
          spinner(),
          pages > 1
            ? `Claude is reading page ${page} of ${pages}…`
            : 'Claude is reading it…',
        );
        const reply = await post(
          '/media/transcribe',
          JSON.stringify({ ...request(), page }),
        );
        if (reply.error || reply.text === undefined) {
          error = reply.error ?? 'Something went wrong.';
          break;
        }
        pages = reply.pages ?? 1;
        read.push(reply.text);
        // What is read so far shows as it comes.
        text.value = joinPages(read, pages);
      }
      busy(text, false);
      button.disabled = false;
      if (error) {
        if (!read.length) text.value = before;
        status.textContent = read.length
          ? ` Stopped after page ${read.length}: ${error}`
          : ` ${error}`;
        if (!read.length) return;
      }
      text.classList.add('helped');
      const undo = element('button', { type: 'button', textContent: 'Undo' });
      undo.addEventListener('click', () => {
        text.value = before;
        text.classList.remove('helped');
        status.textContent = '';
      });
      if (!error) status.replaceChildren(' Check what Claude read. ', undo);
      else status.append(' ', undo);
    })();
  });
  return element('div', { className: 'help tidy' }, button, status);
}

/** The pages of a document read so far, each under its page number. */
function joinPages(read: string[], pages: number): string {
  if (pages <= 1) return read.join('');
  return read
    .map((text, i) => `— Page ${i + 1} —\n\n${text.trim()}`)
    .join('\n\n');
}

// ------------------------------------------------------------ add photos

class PhotoCard {
  front?: string;
  back?: string;
  uploading = 0;
  readonly el = element('div', { className: 'photo-card' });
  readonly title = element('input', { maxLength: 200 });
  readonly date = element('input', {
    maxLength: 80,
    placeholder: 'As above',
  });
  readonly place = element('input', {
    maxLength: 200,
    placeholder: 'As above',
  });
  readonly transcription = element('textarea', { spellcheck: true });
  readonly notes = element('textarea', { spellcheck: true });
  readonly people: PeoplePicker;

  constructor(
    file: File,
    private readonly page: AddPhotos,
  ) {
    const preview = element('img', { alt: '' });
    const status = element('p', {
      className: 'status',
      textContent: `Uploading ${file.name}…`,
    });
    const remove = element('button', {
      type: 'button',
      textContent: 'Remove',
    });
    remove.addEventListener('click', () => page.remove(this));
    const pickerEl = element('div', { className: 'people-picker' });
    const peopleLabel = element('label', {}, 'Also in this photo');
    this.people = new PeoplePicker(pickerEl);

    const backArea = element('div', { hidden: true });
    const backInput = element('input', {
      type: 'file',
      accept: 'image/jpeg,image/heic,image/png,image/tiff,.heic,.tif,.tiff',
      hidden: true,
    });
    const addBack = element('a', {
      href: '#',
      className: 'add-back',
      textContent: 'Add the back',
    });
    addBack.addEventListener('click', (e) => {
      e.preventDefault();
      backInput.click();
    });
    const backPreview = element('img', { alt: 'The back' });
    backInput.addEventListener('change', () => {
      const chosen = backInput.files?.[0];
      if (!chosen) return;
      addBack.hidden = true;
      backArea.hidden = false;
      void this.upload(chosen, backPreview, backStatus).then((reply) => {
        this.back = reply?.token;
      });
    });
    const backStatus = element('p', { className: 'status' });
    backArea.append(backPreview, backStatus);

    // The words on it, and notes about it: a link opens them for a photo,
    // and they are open for a document or a photo with its back.
    const [writtenLabel, writtenInput] = field(
      'Written on it',
      this.transcription,
    );
    const textArea = element(
      'div',
      { hidden: true },
      writtenLabel,
      writtenInput,
      ...(page.help
        ? [
            transcribeButton(this.transcription, () =>
              this.back
                ? { token: this.back, back: true }
                : { token: this.front ?? '', back: false },
            ),
          ]
        : []),
      ...field('Notes', this.notes),
    );
    const addText = element('a', {
      href: '#',
      className: 'add-back',
      textContent: 'Add a transcription or notes',
    });
    const openText = () => {
      addText.hidden = true;
      textArea.hidden = false;
    };
    addText.addEventListener('click', (e) => {
      e.preventDefault();
      openText();
    });
    backInput.addEventListener('change', () => {
      writtenLabel.textContent = 'Written on the back';
      openText();
    });

    this.el.append(
      element('div', {}, preview, status),
      element(
        'div',
        {},
        ...field('Caption', this.title),
        ...field('When', this.date),
        ...field('Where', this.place),
        peopleLabel,
        pickerEl,
        addBack,
        backInput,
        backArea,
        addText,
        textArea,
        element('p', {}, remove),
      ),
    );
    void this.upload(file, preview, status).then((reply) => {
      this.front = reply?.token;
      // A document has no back, and names people rather than showing them.
      if (reply?.kind === 'pdf') {
        addBack.hidden = true;
        peopleLabel.textContent = 'People it names';
        preview.classList.add('document');
        writtenLabel.textContent = 'Transcription';
        this.transcription.classList.add('tall');
        openText();
        if (reply.title && !this.title.value) this.title.value = reply.title;
        if (reply.date && !this.date.value) this.date.value = reply.date;
      }
    });
  }

  private async upload(
    file: File,
    preview: HTMLImageElement,
    status: HTMLElement,
  ): Promise<Reply | undefined> {
    this.uploading++;
    this.page.update();
    const bar = element('progress', { max: 1, value: 0 });
    status.replaceChildren(`Uploading ${file.name}… `, bar);
    const reply = await sendFile(file, (sent) => {
      bar.value = sent;
      if (sent >= 1) {
        // Sent; the server is storing it and making its preview.
        status.replaceChildren(spinner(), `Preparing ${file.name}…`);
      }
    });
    this.uploading--;
    if (reply.error || !reply.token) {
      status.textContent = reply.error ?? 'The upload failed.';
      this.page.update();
      return undefined;
    }
    preview.src = `/media/staging/${reply.token}/preview`;
    status.textContent = file.name;
    // The token is recorded by the caller before the page checks again.
    setTimeout(() => this.page.update());
    return reply;
  }
}

class AddPhotos {
  readonly cards: PhotoCard[] = [];
  readonly help: boolean;
  private readonly list: HTMLElement;
  private readonly submit: HTMLButtonElement;
  private readonly message: HTMLElement;
  private readonly shared: PeoplePicker;

  constructor(private readonly form: HTMLFormElement) {
    this.help = form.dataset.help === 'true';
    this.list = form.querySelector('.photo-list')!;
    this.submit = form.querySelector('button.primary')!;
    this.message = form.querySelector('.message')!;
    this.shared = new PeoplePicker(form.querySelector('.people-picker')!);
    const files = form.querySelector<HTMLInputElement>('#files')!;
    files.addEventListener('change', () => {
      for (const file of files.files ?? []) {
        const card = new PhotoCard(file, this);
        this.cards.push(card);
        this.list.append(card.el);
      }
      files.value = '';
      this.update();
    });
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      void this.add();
    });
  }

  remove(card: PhotoCard): void {
    this.cards.splice(this.cards.indexOf(card), 1);
    card.el.remove();
    this.update();
  }

  update(): void {
    const ready =
      this.cards.length > 0 &&
      this.cards.every((c) => c.uploading === 0 && c.front);
    this.submit.disabled = !ready;
    this.submit.textContent =
      this.cards.length > 1
        ? `Add the ${this.cards.length} photos`
        : 'Add the photo';
  }

  private async add(): Promise<void> {
    const value = (id: string) =>
      this.form.querySelector<HTMLInputElement>(`#${id}`)!.value.trim();
    const date = value('shared_date');
    const place = value('shared_place');
    this.submit.disabled = true;
    this.message.hidden = true;
    const reply = await post(
      '/media/add',
      JSON.stringify({
        person: this.form.dataset.person,
        photos: this.cards.map((c) => ({
          front: c.front,
          back: c.back,
          title: c.title.value,
          date: c.date.value.trim() || date,
          place: c.place.value.trim() || place,
          transcription: c.transcription.value,
          notes: c.notes.value,
          people: [...new Set([...this.shared.ids, ...c.people.ids])],
        })),
      }),
    );
    if (reply.location) {
      location.href = reply.location;
      return;
    }
    this.message.textContent = reply.error ?? 'The photos were not added.';
    this.message.hidden = false;
    this.update();
  }
}

// ------------------------------------------------------------ edit photo

function editPhoto(form: HTMLFormElement): void {
  new PeoplePicker(form.querySelector('.people-picker')!);
  const help = form.querySelector<HTMLElement>('.help[data-key]');
  const text = form.querySelector<HTMLTextAreaElement>('#transcription');
  if (help && text) {
    help.replaceWith(
      transcribeButton(text, () => ({ key: help.dataset.key! })),
    );
  }
  // Enter in the name box picks a person rather than saving the form.
  form.addEventListener('keydown', (e) => {
    if (
      e.key === 'Enter' &&
      (e.target as HTMLElement).closest('.people-picker')
    )
      e.preventDefault();
  });
}

const addForm = document.querySelector<HTMLFormElement>('form.add-photos');
if (addForm) new AddPhotos(addForm);
const editForm = document.querySelector<HTMLFormElement>('form.edit-photo');
if (editForm) editPhoto(editForm);
// Any other picker on the page, such as choosing who a new member is.
for (const el of document.querySelectorAll<HTMLElement>(
  '.people-picker:not(.ready)',
)) {
  new PeoplePicker(el);
  // Enter picks a person rather than sending the form.
  el.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') e.preventDefault();
  });
}
