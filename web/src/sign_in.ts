// Sign-in page. The browser signs in with Google through Firebase, then
// hands the resulting ID token to the Prosapia server, which checks membership
// and sets the session cookie. Nothing is kept in the browser afterwards:
// the server's cookie is the session.

import { initializeApp, type FirebaseOptions } from 'firebase/app';
import {
  connectAuthEmulator,
  getAuth,
  GoogleAuthProvider,
  inMemoryPersistence,
  setPersistence,
  signInWithPopup,
  signOut,
} from 'firebase/auth';

interface Config {
  firebase: FirebaseOptions;
  /** Set only in development, when the local emulator stands in for Google. */
  authEmulator?: string;
}

const config = JSON.parse(
  document.getElementById('config')!.textContent,
) as Config;
const button = document.getElementById('sign-in') as HTMLButtonElement;
const message = document.getElementById('message')!;

const auth = getAuth(initializeApp(config.firebase));
if (config.authEmulator) {
  connectAuthEmulator(auth, config.authEmulator, { disableWarnings: true });
}

/** Where to go after signing in: the page that was asked for, if it is ours. */
function destination(): string {
  const next = new URLSearchParams(location.search).get('next');
  return next && next.startsWith('/') && !next.startsWith('//') ? next : '/';
}

async function signIn(): Promise<void> {
  button.disabled = true;
  message.textContent = '';
  try {
    await setPersistence(auth, inMemoryPersistence);
    const result = await signInWithPopup(auth, new GoogleAuthProvider());
    const response = await fetch('/session', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ idToken: await result.user.getIdToken() }),
    });
    if (response.ok) {
      location.assign(destination());
      return;
    }
    const body = (await response.json().catch(() => ({}))) as {
      error?: string;
    };
    message.textContent = body.error ?? 'Sign-in failed. Please try again.';
    await signOut(auth);
  } catch (error) {
    const code = (error as { code?: string }).code;
    // Closing the Google window is not an error worth reporting.
    if (
      code !== 'auth/popup-closed-by-user' &&
      code !== 'auth/cancelled-popup-request'
    ) {
      message.textContent = 'Sign-in failed. Please try again.';
      console.error(error);
    }
  }
  button.disabled = false;
}

button.addEventListener('click', () => void signIn());
