// A row of photos that scrolls sideways. Its buttons move a screenful at a
// time, and the row keeps its place when the reader opens a photo and
// comes back.

for (const [i, strip] of document.querySelectorAll('.strip').entries()) {
  const row = strip.querySelector<HTMLElement>('.gallery')!;
  const prev = strip.querySelector<HTMLButtonElement>('.prev')!;
  const next = strip.querySelector<HTMLButtonElement>('.next')!;
  const key = `prosapia.strip.${location.pathname}.${i}`;

  const update = () => {
    prev.hidden = row.scrollLeft <= 1;
    next.hidden = row.scrollLeft + row.clientWidth >= row.scrollWidth - 1;
  };
  const by = (direction: number) =>
    row.scrollBy({
      left: direction * row.clientWidth * 0.9,
      behavior: 'smooth',
    });
  prev.addEventListener('click', () => by(-1));
  next.addEventListener('click', () => by(1));

  // Storage may be unavailable, as in a private window; the row then
  // starts at the beginning.
  try {
    const saved = Number(sessionStorage.getItem(key));
    if (saved > 0) row.scrollLeft = saved;
  } catch {
    // Nothing saved.
  }
  let timer = 0;
  row.addEventListener('scroll', () => {
    update();
    clearTimeout(timer);
    timer = window.setTimeout(() => {
      try {
        sessionStorage.setItem(key, String(Math.round(row.scrollLeft)));
      } catch {
        // Not saved.
      }
    }, 150);
  });
  window.addEventListener('resize', update);
  update();
}
