# Changelog

All notable changes to Snowfall are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
