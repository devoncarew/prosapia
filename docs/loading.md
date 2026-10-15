# Loading an existing tree

How a family's existing tree, kept in other genealogy software, is loaded into
Prosapia's production project before the site is opened to the family. This is done
once, by the tree's owner, on their own computer; the backup holding the photos can be a
gigabyte or more, too large to upload through a web page.

Loading again later replaces everything, including any edits made in Prosapia since. It
is for setting a tree up, not for keeping it in step with other software; importing into
a tree already in use is milestone 7 in the [plan](plan.md).

## What you need

- From the other software, a **GEDCOM export** of the tree. For Family Tree Maker, also
  its **backup file** (`.ftmb`), which holds the photos and documents.
- Dart, `exiftool` and `unzip`, as in [CONTRIBUTING.md](../CONTRIBUTING.md).
- Access to the Firebase project, and the Google Cloud command-line tools signed in with
  that account: run `gcloud auth application-default login` once.

## Steps

1. **Convert the export into Prosapia's file layout.** Keep the result under `data/`,
   which is never committed.

   ```
   dart run spikes/gedcom_import/import.dart --name="Carew family" \
       ~/Downloads/export.ged data/carew ~/Downloads/backup.ftmb
   ```

   It prints what it imported, which media files it could not find in the backup, dates
   it kept as written, and anything in the export it did not understand.

2. **Look at the result locally.** No sign-in, nothing leaves your computer:

   ```
   dart run prosapia data/carew
   ```

   Open http://localhost:8080 and check a few people you know well.

3. **Check your credentials reach the project.**

   ```
   dart run tool/check_credentials.dart prosapia-ea818
   ```

4. **Load it into the project**, naming yourself as owner. Nobody else can see the tree
   until they are added as members.

   ```
   dart run prosapia:load --project prosapia-ea818 --tree carew \
       --owner you@example.com data/carew
   ```

   Files larger than 50 MB, such as long videos, are skipped and listed; `--max-file-mb`
   changes the limit. If the tree already exists, the loader stops unless you add
   `--replace`, which deletes the tree's pages, their history and its change log before
   loading. Members are kept, and photos already uploaded are not uploaded again.

5. **Check it in the project.**

   ```
   dart run prosapia --project prosapia-ea818 --tree carew
   ```

   Open http://localhost:8080 and sign in with the owner's Google account.
