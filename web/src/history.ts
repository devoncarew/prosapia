// A page's change history. Choosing a version shows what it changed below
// the list, and offers to restore it, without leaving the page.

const table = document.querySelector<HTMLTableElement>('table.versions');
const panel = document.querySelector<HTMLElement>('.version-panel');

async function select(row: HTMLTableRowElement): Promise<void> {
  if (!table || !panel || row.getAttribute('aria-selected') === 'true') return;
  for (const other of table.querySelectorAll('tr[aria-selected]')) {
    other.removeAttribute('aria-selected');
  }
  row.setAttribute('aria-selected', 'true');
  const version = row.dataset.version!;
  history.replaceState({}, '', `?version=${version}`);
  const response = await fetch(
    `/people/${table.dataset.person}/revisions/${version}?fragment`,
  );
  // Only the latest choice is shown, if several are made quickly.
  if (response.ok && row.getAttribute('aria-selected') === 'true') {
    panel.innerHTML = await response.text();
  }
}

table?.addEventListener('click', (event) => {
  const target = event.target as HTMLElement;
  if (target.closest('form')) return; // Restore this version
  const row = target.closest<HTMLTableRowElement>('tr[data-version]');
  if (row) void select(row);
});

table?.addEventListener('keydown', (event) => {
  const row = (event.target as HTMLElement).closest<HTMLTableRowElement>(
    'tr[data-version]',
  );
  if (!row) return;
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    void select(row);
  } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    const next =
      event.key === 'ArrowDown'
        ? row.nextElementSibling
        : row.previousElementSibling;
    if (next instanceof HTMLTableRowElement) {
      next.focus();
      void select(next);
    }
  }
});
