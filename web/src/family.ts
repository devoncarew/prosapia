// The family tree. It draws the lines between the cards the server laid
// out, and choosing someone centres the tree on them in place, with the
// cards that stay moving to their new places.

const svgNS = 'http://www.w3.org/2000/svg';

type Union = { p: string[]; c: string[] };
type Box = { top: number; height: number };

// Where a line between two cards side by side meets them: level with the
// middle of the shorter, so it reaches both.
const level = (a: Box, b: Box) =>
  Math.max(a.top, b.top) + Math.min(a.height, b.height) / 2;

function draw(): void {
  const chart = document.querySelector<HTMLElement>('.family');
  if (!chart) return;
  chart.querySelector(':scope > svg')?.remove();
  const origin = chart.getBoundingClientRect();
  const box = (key: string) => {
    const card = chart.querySelector(`[data-key="${key}"]`);
    if (!card) return null;
    const r = card.getBoundingClientRect();
    return {
      left: r.left - origin.left,
      right: r.right - origin.left,
      top: r.top - origin.top,
      bottom: r.bottom - origin.top,
      x: r.left - origin.left + r.width / 2,
      y: r.top - origin.top + r.height / 2,
      height: r.height,
    };
  };
  const svg = document.createElementNS(svgNS, 'svg');
  svg.setAttribute('aria-hidden', 'true');
  const path = (d: string, kind = '') => {
    const p = document.createElementNS(svgNS, 'path');
    p.setAttribute('d', d);
    if (kind) p.setAttribute('class', kind);
    svg.append(p);
  };

  // Partners: a line between the two cards.
  const couples = JSON.parse(chart.dataset.couples ?? '[]') as string[][];
  for (const [a, b] of couples) {
    const [l, r] = [box(a), box(b)].sort((x, y) => (x?.x ?? 0) - (y?.x ?? 0));
    if (!l || !r) continue;
    path(`M${l.right} ${level(l, r)}H${r.left}`, 'couple');
  }

  // Parents to children: down from the couple's line, or from a single
  // parent, to a bar, and down from the bar to each child.
  const unions = JSON.parse(chart.dataset.unions ?? '[]') as Union[];
  for (const u of unions) {
    const parents = u.p.map(box).filter((b) => b !== null);
    const children = u.c.map(box).filter((b) => b !== null);
    if (!parents.length || !children.length) continue;
    let x: number, y: number;
    if (parents.length === 2) {
      const [l, r] = parents.sort((a, b) => a.x - b.x);
      x = (l.right + r.left) / 2;
      y = level(l, r);
    } else {
      x = parents[0].x;
      y = parents[0].bottom;
    }
    const lowest = Math.max(...parents.map((b) => b.bottom));
    const bar = (lowest + Math.min(...children.map((b) => b.top))) / 2;
    const xs = [x, ...children.map((b) => b.x)];
    let d = `M${x} ${y}V${bar}M${Math.min(...xs)} ${bar}H${Math.max(...xs)}`;
    for (const c of children) d += `M${c.x} ${bar}V${c.top}`;
    path(d);
  }
  chart.prepend(svg);
}

// The person in the middle starts in view on a narrow screen.
function centre(): void {
  const scroll = document.querySelector<HTMLElement>('.family-scroll');
  const card = scroll?.querySelector<HTMLElement>('.card.center');
  if (!scroll || !card) return;
  const s = scroll.getBoundingClientRect();
  const c = card.getBoundingClientRect();
  scroll.scrollLeft += c.left + c.width / 2 - (s.left + s.width / 2);
}

async function show(href: string, push: boolean): Promise<void> {
  const section = document.querySelector('.family-view');
  let text: string;
  try {
    const response = await fetch(`${href}?fragment`);
    if (!response.ok) throw new Error(String(response.status));
    text = await response.text();
  } catch {
    location.href = href;
    return;
  }
  const update = () => {
    section?.insertAdjacentHTML('beforebegin', text);
    section?.remove();
    const title =
      document.querySelector<HTMLElement>('.family-view')?.dataset.title;
    const tree = document.title.split(' · ').pop();
    if (title) document.title = `${title} · ${tree}`;
    draw();
    centre();
  };
  if (push) history.pushState(null, '', href);
  if (document.startViewTransition) {
    await document.startViewTransition(update).finished;
  } else {
    update();
  }
}

document.addEventListener('click', (e) => {
  if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) {
    return;
  }
  const link = (e.target as Element).closest<HTMLAnchorElement>(
    '.family a.card:not(.center), .family a.more',
  );
  // On another page, such as the home page, the link opens the family
  // tree page itself.
  if (!link || !location.pathname.endsWith('/family')) return;
  e.preventDefault();
  void show(link.pathname, true);
});

window.addEventListener('popstate', () => {
  if (location.pathname.endsWith('/family'))
    void show(location.pathname, false);
});

let pending = 0;
window.addEventListener('resize', () => {
  cancelAnimationFrame(pending);
  pending = requestAnimationFrame(draw);
});

draw();
centre();
// Lines move if the page's font arrives after they are drawn.
void document.fonts.ready.then(draw);
