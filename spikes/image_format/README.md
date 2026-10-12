# Image-format spike

Milestone 1 in [docs/plan.md](../../docs/plan.md). Packages one photo (front, back, text) in each candidate format and measures size, fidelity, and whether the back and the text survive.

Run it from this directory:

```
dart run build.dart
```

It reads `input/`, writes every package to `out/` (not committed), and writes the measurements to [results_table.md](results_table.md). Findings and the proposed decision are in [docs/media.md](../../docs/media.md).

Needs `exiftool`, ImageMagick, `libheif`, `jpeg-xl`, `libtiff` and `webp` from Homebrew, plus macOS `sips`.
