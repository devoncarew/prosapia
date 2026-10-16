// Times are written into pages in UTC; this shows them in the viewer's own
// time zone: `16 Oct 2026, 18:25`, and `today` or `3 days ago` counted by
// the viewer's own calendar.

const months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

function day(d: Date): string {
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}

function clock(d: Date): string {
  const two = (n: number) => String(n).padStart(2, '0');
  return `${two(d.getHours())}:${two(d.getMinutes())}`;
}

/** Whole calendar days from [d] to now, in the viewer's time zone. */
function daysAgo(d: Date): number {
  const start = (x: Date) =>
    new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  return Math.round((start(new Date()) - start(d)) / 86_400_000);
}

export function localTimes(root: ParentNode = document): void {
  for (const el of root.querySelectorAll<HTMLTimeElement>('time[datetime]')) {
    const d = new Date(el.dateTime);
    if (isNaN(d.getTime())) continue;
    el.title = d.toLocaleString();
    if (el.hasAttribute('data-time')) {
      el.textContent = `${day(d)}, ${clock(d)}`;
    } else if (el.hasAttribute('data-ago')) {
      const days = daysAgo(d);
      el.textContent =
        days < 1
          ? 'today'
          : days < 2
            ? 'yesterday'
            : days < 31
              ? `${days} days ago`
              : `on ${day(d)}`;
    }
  }
}

localTimes();
