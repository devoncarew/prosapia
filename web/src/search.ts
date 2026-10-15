// The search box in the header: as you type a name, matching people are
// offered with their years and parents, so namesakes can be told apart.
// Pressing Enter without choosing one still runs a full search.

interface PersonSuggestion {
  id: string;
  name: string;
  detail: string;
}

const input = document.querySelector<HTMLInputElement>('form.search input');
if (input) {
  const list = document.createElement('div');
  list.className = 'search-suggestions';
  list.hidden = true;
  input.after(list);

  let active = -1;
  let latest = 0;
  let timer: number | undefined;

  const links = (): HTMLAnchorElement[] =>
    Array.from(list.querySelectorAll('a'));

  const highlight = (index: number): void => {
    const items = links();
    active = items.length === 0 ? -1 : (index + items.length) % items.length;
    items.forEach((a, i) => a.classList.toggle('active', i === active));
  };

  const show = async (): Promise<void> => {
    const query = input.value.trim();
    const request = ++latest;
    if (query.length < 2) {
      list.hidden = true;
      return;
    }
    const response = await fetch(`/api/people?q=${encodeURIComponent(query)}`);
    if (!response.ok || request !== latest) return;
    const people = (await response.json()) as PersonSuggestion[];
    list.replaceChildren(
      ...people.map((p) => {
        const a = document.createElement('a');
        a.href = `/people/${p.id}`;
        a.textContent = p.name;
        if (p.detail) {
          const detail = document.createElement('span');
          detail.textContent = p.detail;
          a.append(detail);
        }
        return a;
      }),
    );
    active = -1;
    list.hidden = people.length === 0;
  };

  input.addEventListener('input', () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => void show(), 150);
  });
  input.addEventListener('keydown', (event) => {
    if (list.hidden) return;
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      highlight(active + (event.key === 'ArrowDown' ? 1 : -1));
    } else if (event.key === 'Enter' && active >= 0) {
      event.preventDefault();
      links()[active].click();
    } else if (event.key === 'Escape') {
      list.hidden = true;
    }
  });
  input.addEventListener('blur', () => {
    // Let a click on a suggestion land before the list disappears.
    window.setTimeout(() => (list.hidden = true), 150);
  });
}
