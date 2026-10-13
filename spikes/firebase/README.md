# Firebase spike

The first step of milestone 3 in [docs/plan.md](../../docs/plan.md): can a Dart server
do what Loom needs from Firebase?

```
firebase emulators:exec "dart run spikes/firebase/spike.dart"
```

Result: yes. Every check passes against the local emulators using `firebase_admin_sdk`,
the official Firebase Admin SDK for Dart, with `google_cloud_firestore` and
`google_cloud_storage`.

| Area | Checked |
| --- | --- |
| Firestore | Nested documents; a save that writes the page, a revision and a change-log entry in one transaction; refusing a save based on a stale revision; ordered queries; a 500-document batch write and whole-collection read (under 200 ms each); querying children by parent id |
| Sign-in | Verifying a Google sign-in; reading the email and provider; creating and verifying a session cookie; rejecting a malformed token; looking a user up by email |
| Cloud Storage | Uploading a photo and downloading identical bytes, so embedded metadata survives |

Not checked here: rejecting a token with a forged signature. The emulator issues
unsigned tokens, so that needs a real project and belongs to milestone 5.
