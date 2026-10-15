# GEDCOM import spike

Milestone 0, and the starting point for milestone 7, in
[docs/plan.md](../../docs/plan.md). Converts a GEDCOM 5.5.1 export from Family Tree
Maker into a sample tree in Prosapia's repository layout, and copies the media it refers
to out of the matching `.ftmb` backup, writing each file's title, people and ids into
the file.

```
dart run spikes/gedcom_import/import.dart data/CarewFamTree_2024-09-08_01.ged data/tree ~/Downloads/CarewFamTree_2024-09-08.ftmb
```

The output is sample data for trying the design, not the seed of a real tree. It
contains living people and is written to `data/`, which is not committed. Ids are
derived from the GEDCOM references, so a rerun gives the same ids.

It prints a report of what was imported and what was not. Findings are in
[docs/content-model.md](../../docs/content-model.md#what-the-sample-import-showed).

Needs `exiftool` and `unzip`.

The full process for loading a real tree into the production project, which starts with
this script, is in [docs/loading.md](../../docs/loading.md).
