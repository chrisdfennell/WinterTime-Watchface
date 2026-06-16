# Changelog

All notable changes to Snowfall are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.1] - 2026-06-16

### Changed
- **Festive Mode now defaults to off.** The holiday extras (Santa's sleigh flyover, the lit/sparkling pine, and the night-time Star of Bethlehem) no longer appear out of the box — the watch shows the pure alpine look until you turn on the **Festive Mode** switch yourself. The `FestiveMode` property default and the in-code fallback are both `false`. Winter Critters remains on by default.

## [1.4.0] - 2026-06-16

### Added
- **Winter Critters**: A new app setting (on by default) adds occasional crossing visitors — at most one at a time, every ~40s, computed purely from the clock (no RNG, no state). The day pool is a red cardinal (flies the sky), a snowshoe hare (bounds across the snow), a red fox (trots, with a mid-screen snow-pounce), and a chickadee (glides in, lands and pecks, then flits off). The night pool is a snowy owl (glides overhead), an arctic fox (white trotter), a grey wolf (pauses mid-crossing to howl), and an antlered stag (walks across, breath steaming). Sky visitors draw in the sky pass; ground visitors draw after the snowbank so they stand on the snow. Each creature is silhouette-outlined for legibility and renders only in the active layer, so it never touches the always-on power budget.

### Performance & Stability
- **Adaptive render quality**: `onUpdate()` now measures its own frame time and nudges a quality level (0–3) with hysteresis; text-outline passes, sun rays, aurora ribbons, and falling-snow count scale with it, so the scene keeps animating and only sheds detail on hardware that can't keep up.
- **Cheaper always-on**: on AMOLED, `onPartialUpdate()` now clips to just the central time/date band instead of re-rendering the whole screen; MIP keeps the full redraw (its sleep frame is the full colour scene).
- **Cached/buffered rendering**: device settings, clock, and activity info are read once per frame and reused; sunrise/sunset retries are throttled while no fix is available; weather is skipped in always-on; the star field, sky-gradient tables, and drift/aurora polygon buffers are hoisted/reused; and the AMOLED sky gradient is rendered once into a `BufferedBitmap` (repainted in place only when colors change).
- **Loop-safe math**: `normDeg`/`normHour` use bounded modulo with a non-finite (NaN/Infinity) guard instead of unbounded `while` loops, and the drifting-cloud wrap uses positive modulo.

### Fixed
- The snowflake seconds marker is now drawn last (on top of the time, date, and complications) and is gated on `mIsSleep` so it hides cleanly in low power on every device class (including MIP, where the old `mLowPower` gate never applied).

## [1.3.0] - 2026-06-15

### Added
- **Festive Mode**: A single new app setting (on by default) adds holiday flair. Santa's sleigh and two reindeer — the lead one sporting Rudolph's glowing red nose — sweep across the upper sky on a timed flyover (once every ~2.5 minutes, trailing a little stardust). The snow-laden pine is strung with garlands of blinking multicolor lights and crowned with a twinkling, pulsing five-point star topper. At night a radiant **Star of Bethlehem** — a brilliant core with a glowing halo and long shimmering nativity-style rays — joins the starfield. Everything is gated behind one toggle, so it can be turned off for the pure alpine look. Festive elements only render in the active (non-burn-in) layer to stay within the always-on power budget.

## [1.2.0] - 2026-06-15

### Added
- **Broad device support**: Snowfall now targets every Connect IQ 4.0+ round watch that supports watch faces — Forerunner (incl. **965 / 970**), fenix 7/8, epix 2 / Pro, enduro 3, Venu 2/3, Vivoactive 5/6, Instinct 3 / E / Crossover, and the Approach (golf), Descent (dive), D2 (aviation), and MARQ specialty watches. Edge bike computers, handheld GPS units, and square/rectangular panels (Venu Sq 2, Venu X1) are excluded.
- **Per-resolution bitmap fonts for all panel sizes**: `tools/gen_fonts.py` now bakes a correctly-sized Exocet font set for each distinct round resolution (454, 416, 390, 360, 280, 260, 240, 218, 176, 166), and `monkey.jungle` maps every product to its set.

## [1.1.0] - 2026-06-15

### Added
- **Configurable Complications**: The bottom-left and bottom-right complications are each chosen in the app settings — Heart Rate, Body Battery, Device Battery, Steps, Calories, or Off — and the watch draws a matching icon (heart, bolt, battery, boot, flame). Each option shows an emoji in the Garmin Connect picker.
- **Heart Rate complication**: Live BPM from the optical HR sensor, cached and sampled at most once every ~10 seconds to stay within the watch-face power budget.
- **Real Sunrise/Sunset**: The sun, day/night swap, aurora/stars, and sky gradient now track the actual sunrise/sunset computed from the watch's last-known location and today's date (NOAA almanac formula, cached per day), with a fixed winter-schedule fallback when no location fix is available.

### Changed
- **Device Battery complication** now uses a battery icon with a live fill bar (previously a water droplet).
- **Default complications**: bottom-left = Heart Rate, bottom-right = Device Battery.

## [1.0.0] - 2026-06-15

### Added
- **Initial release of Snowfall watch face** for Garmin tactix 8 and Fenix 8 devices (AMOLED + Solar variants).
- **Living Winter Sky Backdrop**: Smooth color gradient shifting through deep indigo night, cold rose dawn, pale midday blue, a cold-peach sunset, and twilight purple based on the current hour.
- **Aurora & Stars at Night**: Wavy green/cyan/violet aurora ribbons drifting above a starfield through the long winter nights.
- **Arcing Sun & Moon**: Day/night orbital progression of a pale winter sun (with faint rotating rays and a cold halo) and a silver crescent moon, on a shorter winter daylight window.
- **Drifting Clouds & Rolling Snow Drifts**: Gentle snow-drift motion and wind-drifting clouds.
- **Snow-laden Pine Silhouette**: Tiered evergreen with snow caps, swaying in the wind.
- **Falling Snow**: Drifting snowflakes across the whole face in active mode.
- **Snowflake Seconds**: Six-armed snowflake second indicator orbiting the outer perimeter.
- **Symmetrical Complications Layout**:
  - Heart icon (icy mint) + numeric Body Battery percentage.
  - Water-droplet icon (glacier blue) + numeric Device Battery percentage.
  - Steps progress bar (frosted ice themed) + steps numeric display.
- **High-Contrast Text Outlines**: Dynamic black text outlining on all elements (clock, date, steps, battery, and body battery values) for supreme legibility against moving backdrops.
- **Dimmed Low-Power Render Path**: Burn-in safe ambient mode for AMOLED screens with coordinate shifting.
- **Custom Fonts**: *Arial Rounded MT Bold* clock font and *Segoe UI Light* labeling/date fonts.
