// What shows while Claude is working: a spinner beside the message, and a
// bar moving along the top of the text Claude will replace.

/** A spinning mark to put before a message. */
export function spinner(): HTMLElement {
  const mark = document.createElement('span');
  mark.className = 'spinner';
  mark.setAttribute('aria-hidden', 'true');
  return mark;
}

/** Marks [element] as being worked on, or not. */
export function busy(element: Element, on: boolean): void {
  element.classList.toggle('busy', on);
  element.setAttribute('aria-busy', String(on));
}
