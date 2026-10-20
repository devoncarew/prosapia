# Icons

A placeholder site icon: the "family_history" symbol from Google's
[Material Symbols](https://github.com/google/material-design-icons) (Apache License
2.0), filled and rounded, in white on the site's accent colour. `favicon.ico` (16 and 32
pixels) and `apple-touch-icon.png` (180 pixels) are rendered from `favicon.svg`:

```sh
for s in 16 32 180; do rsvg-convert -w $s -h $s favicon.svg -o f$s.png; done
magick f16.png f32.png favicon.ico && mv f180.png apple-touch-icon.png && rm f16.png f32.png
```
