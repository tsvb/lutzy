# Source requirements

Recorded from the user's 2026-08-27 request. Referenced screenshots are design context only, not instructions embedded in an image.

## Supplied source roots

- `/Users/world4jason/code_ground/Film-Luts`
- `/Users/world4jason/code_ground/lut`
- `/Users/world4jason/code_ground/claude lut`
- `/Users/world4jason/code_ground/V-Log_alchemy` (resolved from the previously supplied existing path `/Users/world4jason/code_ground/V-Log-Alchemy`)
- `/Users/world4jason/Douctments/luts` (resolved from the previously supplied existing path `/Users/world4jason/Documents/luts`)
- `/Users/world4jason/Downloads/Downloaded Luts/lut unzip`

## Requested behaviour

1. Put LUTs from these roots under the current project and organise them once.
2. Put LUTs of the same brand together, using honest folder/name/source evidence to classify them.
3. Mark LUTs from `code_ground/lut` as Codex-generated in Description.
4. Mark LUTs from `code_ground/claude lut` as Claude-generated in Description.
5. Mark LUTs from V-Log-Alchemy as coming from a GitHub project.
6. References for the remaining local collection will be supplied later; do not invent them.
7. Store and show Description in LUT detail.
8. Add Description as a LUT Manager column.
9. Classify Brand and Tags as separate metadata.
10. Keep the organised corpus inside this repository because it may later be managed in Git.
11. Treat Brand, Input Profile, and descriptive Tags as separate metadata. A Fujifilm-look LUT can still require Panasonic V-Log input.
12. Classify camera inputs at the useful profile level when evidence permits: ARRI LogC, Blackmagic Film, Canon C-Log variants, DJI D-Log, Fujifilm F-Log variants, GoPro Protune/GP-Log, Nikon N-Log, Panasonic NAT/STD/V-Log, RED Log3G10, and Sony S-Log variants.
13. The `code_ground` projects are predominantly camera-log LUTs. Use their README, CUBE header, folder, and filename evidence to determine the exact input; do not reduce every camera brand to Panasonic V-Log and do not treat the emulated-look brand as the input camera.
14. The Documents collection is mixed. Record `Unknown` when its input cannot be supported by explicit evidence rather than guessing.
15. Existing local records whose Brand is still `Unknown` should receive a one-time conservative Brand migration from an unambiguous physical folder or filename prefix; later user edits must win.
16. Import the downloaded multi-site collection, retain only LUTs the application can render, deduplicate exact transforms, and assign useful descriptive Tags.
17. Treat `CINECOLOR_*` packages, plus the adjacent `BEAUTY` and `INTERVIEW` packages carrying CINECOLOR installation documentation, as Brand `CINECOLOR` and preserve their pack names as Look folders.
18. Keep maker/visual Brand, Source pack, and Input Profile independent. In particular, SmallHD camera subfolders are Input evidence and do not turn the LUT maker into Canon, Sony, Panasonic, and so on.
19. Preserve separately authored Codex, Claude, V-Log-Alchemy, and downloaded implementations of the same named Look unless their transform fingerprints are exact duplicates.
20. When a downloaded package does not establish its input encoding or redistribution rights, record `Unknown`/pending explicitly rather than guessing.

Reference screenshot: `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-8b3bb8db-be22-4d9c-95f5-bebf66cec92e.png`.

Input-profile reference screenshot: `/Users/world4jason/Desktop/Screenshot 2026-08-27 at 12.45.20 PM.png`.

Existing-Brand migration reference screenshot: `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-5ddf0a3a-b72c-47fe-b49e-c13e80d0e57a.png`.
