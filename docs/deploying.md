# Deploying

How the site runs in production, and how to set it up and update it. The project is
`prosapia-ea818`; everything runs in `us-west1`, beside the database and storage.

```
browser → Firebase Hosting (the site's address, HTTPS) → Cloud Run (the server)
                                                           ↳ Firestore, Cloud Storage,
                                                             Firebase Auth, Claude
```

- **Cloud Run** runs the server from the [Dockerfile](../Dockerfile): the compiled Dart
  server, the browser code, and `exiftool` and `vips` for photos. It runs as its own
  service account, `prosapia-server`, so no key file is needed.
- **Firebase Hosting** gives the site its address and forwards every request to Cloud
  Run ([firebase.json](../firebase.json)). It passes on only the cookie named
  `__session`, which is the one the server uses.
- **The Anthropic API key** is kept in Secret Manager as `anthropic-api-key` and given
  to the server as `ANTHROPIC_API_KEY`.
- **Cloud Run's disk is memory**, lost on restart. Display copies and uploads in
  progress live there and are made again when needed.

## Updating the site

```
tool/deploy.sh
```

Cloud Build builds the image from the repository, and Cloud Run starts it in place of
the old one. Only the files the Dockerfile needs are sent
([.gcloudignore](../.gcloudignore)), so `data/` and `.env` never leave your machine.

## One-time setup

Done once per project, in this order. Each step changes the production project.

1. **Turn on the services** the deployment uses:

   ```
   gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
     artifactregistry.googleapis.com secretmanager.googleapis.com \
     --project prosapia-ea818
   ```

2. **Create the server's service account** and give it what the server does: read and
   write the database and stored files, and create sign-in sessions.

   ```
   gcloud iam service-accounts create prosapia-server \
     --display-name "Prosapia server" --project prosapia-ea818
   SA=prosapia-server@prosapia-ea818.iam.gserviceaccount.com
   for role in roles/datastore.user roles/firebaseauth.admin; do
     gcloud projects add-iam-policy-binding prosapia-ea818 \
       --member "serviceAccount:$SA" --role $role --condition None
   done
   gcloud storage buckets add-iam-policy-binding gs://prosapia-ea818.firebasestorage.app \
     --member "serviceAccount:$SA" --role roles/storage.objectAdmin
   ```

3. **Store the Anthropic key**, from `.env`, and let the server read it:

   ```
   grep '^ANTHROPIC_API_KEY=' .env | cut -d= -f2- | tr -d '\n' | \
     gcloud secrets create anthropic-api-key --data-file=- --project prosapia-ea818
   gcloud secrets add-iam-policy-binding anthropic-api-key \
     --member "serviceAccount:$SA" --role roles/secretmanager.secretAccessor \
     --project prosapia-ea818
   ```

4. **Deploy** with `tool/deploy.sh`. The first build takes a few minutes.

5. **Switch on database backups**, kept for two weeks:

   ```
   gcloud firestore backups schedules create --database='(default)' \
     --recurrence=daily --retention=14d --project prosapia-ea818
   ```

6. **Attach the domain.** In the Firebase console, under Hosting, add the custom domain
   `prosapia.app` and put the DNS records it gives at the registrar. Then, under
   Authentication, Settings, Authorized domains, add `prosapia.app` so Google sign-in
   works there. Until then the site is at `https://prosapia-ea818.web.app`.

## Checks after deploying

- **Sign-in works** at the site's address, for an owner and for an invited member.
- **A forged sign-in is refused.** The server must reject a token that Google did not
  sign. This sends one with a real key id and correct claims but a made-up signature,
  and should print `401`. (Run against the local server with the real project, it did.)

  ```
  SITE=https://prosapia-ea818.web.app
  KID=$(curl -s https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com \
    | python3 -c 'import json,sys; print(next(iter(json.load(sys.stdin))))')
  b64() { base64 | tr -d '=\n' | tr '/+' '_-'; }
  NOW=$(date +%s)
  H=$(printf '{"alg":"RS256","kid":"%s","typ":"JWT"}' "$KID" | b64)
  P=$(printf '{"iss":"https://securetoken.google.com/prosapia-ea818","aud":"prosapia-ea818","auth_time":%s,"sub":"forged","email":"devoncarew@gmail.com","email_verified":true,"iat":%s,"exp":%s}' \
    $NOW $NOW $((NOW + 3600)) | b64)
  curl -s -o /dev/null -w '%{http_code}\n' -X POST $SITE/session \
    -H 'content-type: application/json' -d "{\"idToken\":\"$H.$P.c2lnbmF0dXJl\"}"
  ```

## Limits to know

- **Requests through Hosting time out after 60 seconds.** A long Claude draft could come
  close; if it does, the editor shows an error and nothing changes.
- **Uploads are limited to 32 MB a file** by Cloud Run. Larger scans need a signed
  upload straight to storage, which is in the plan's future work.
