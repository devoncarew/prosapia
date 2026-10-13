# Image-format spike

Milestone 1 in [docs/plan.md](../../docs/plan.md). Packages one photo (front, back,
text) in each candidate format and measures size, fidelity, and whether the back and the
text survive.

Run it from this directory:

```
dart run build.dart
```

It reads `input/`, writes every package to `out/` (not committed), and writes the
measurements to [results_table.md](results_table.md). Findings and the decision they led
to are in [docs/media.md](../../docs/media.md). The decision was to stop packaging the
two sides as one file: each side is an ordinary JPEG, paired by file name and embedded
id.

Needs `exiftool`, ImageMagick, `libheif`, `jpeg-xl`, `libtiff` and `webp` from Homebrew,
plus macOS `sips`.
