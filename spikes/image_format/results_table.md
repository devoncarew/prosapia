| Candidate | Files | Size (kB) | vs input | Front PSNR (dB) | Back PSNR (dB) | Input JPEGs recoverable exactly | Back present after metadata write | Text read back by exiftool | Text findable in raw bytes | macOS opens it | After macOS re-save: back | After macOS re-save: text |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Two JPEGs with metadata (baseline) | 2 | 221 | 103% | identical | identical | yes | n/a | yes | yes | yes | separate file | kept |
| JPEG with the back appended (MPF) | 1 | 222 | 103% | identical | identical | yes | yes | yes | yes | yes | lost | kept |
| Multi-page TIFF (tiff_lossless) | 1 | 1012 | 472% | identical | identical | no | yes | yes | yes | yes | kept | kept |
| Multi-page TIFF (tiff_jpeg_q90) | 1 | 569 | 265% | 49.2 | 50.5 | no | yes | yes | yes | yes | kept | kept |
| Multi-page TIFF (tiff_jpeg_q75) | 1 | 335 | 156% | 41.3 | 44.2 | no | yes | yes | yes | yes | kept | kept |
| HEIF collection (heic_q90) | 1 | 359 | 168% | 56.2 | 52.2 | no | yes | yes | yes | yes | lost | kept |
| HEIF collection (heic_q75) | 1 | 238 | 111% | 51.1 | 51.2 | no | yes | yes | yes | yes | lost | kept |
| HEIF collection (avif_q90) | 1 | 171 | 80% | 48.5 | 49.1 | no | yes | yes | yes | yes | lost | kept |
| HEIF collection (avif_q75) | 1 | 109 | 51% | 43.2 | 46.2 | no | yes | yes | yes | yes | lost | kept |
| Two JPEG XL files, repacked JPEGs | 2 | 180 | 84% | 51.0 | 52.5 | yes | n/a | yes | yes | yes | n/a | n/a |
| Side by side (sbs_jpeg_q93) | 1 | 227 | 106% | 51.9 | 47.2 | no | yes | yes | yes | yes | kept | kept |
| Side by side (sbs_webp_q90) | 1 | 131 | 61% | 42.3 | 45.8 | no | yes | yes | yes | yes | n/a | n/a |
| Side by side (sbs_avif_q90) | 1 | 169 | 79% | 48.4 | 48.3 | no | yes | yes | yes | yes | kept | kept |
| Side by side (sbs_jxl_d1) | 1 | 140 | 65% | 46.0 | 45.8 | no | yes | yes | yes | yes | n/a | n/a |
| Two-page PDF, JPEGs embedded | 1 | 219 | 102% | identical | identical | yes | yes | yes | yes | yes | n/a | n/a |
| Zip bundle: JPEGs plus text file | 1 | 222 | 104% | identical | identical | yes | yes | n/a | yes | no | n/a | n/a |
