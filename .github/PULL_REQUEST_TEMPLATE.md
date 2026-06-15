<!-- Thanks for contributing to Snowfall! -->

## Description

<!-- What does this PR change and why? Link any related issue, e.g. "Closes #12". -->

## Type of change

- [ ] Bug fix
- [ ] New feature (new indicator, ornamentation, globe behavior, etc.)
- [ ] Layout / readability improvement
- [ ] New device support
- [ ] Art / font assets
- [ ] Documentation
- [ ] Other:

## Devices tested

<!-- Snowfall targets the tactix 8 (Fenix 8 AMOLED). Please cover both case sizes. -->

- [ ] `fenix847mm` (454×454, 51mm)
- [ ] `fenix843mm` (416×416, 47mm)

## Checklist

- [ ] `.\build.ps1 -Device <device>` compiles with no warnings
- [ ] Verified in the simulator in both active and Always-On / low-power modes
- [ ] Globes fill correctly from live data, and degrade gracefully when a value is
      unavailable (e.g. Body Battery → dimmed `--`)
- [ ] Layout holds on both 454 and 416 panels (no clipping at the round edge)
- [ ] Re-ran `python tools/gen_fonts.py` if any font size/glyph changed
- [ ] Updated `CHANGELOG.md` if this is a user-facing change

## Screenshots

<!-- Before/after simulator screenshots for any visual change (see savescreenshot.ps1). -->
