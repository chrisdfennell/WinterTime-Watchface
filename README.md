# Snowfall Watch Face
 
A premium, winter alpine themed **digital watch face** for the **Garmin Fenix 8 and tactix 8**, written in Monkey C for Connect IQ.

Snowfall brings a crisp, serene, and beautiful winter aesthetic to your watch:
 
- **Living Winter Sky Backdrop**: A smooth color gradient shifting through deep indigo night, cold rose dawn, pale midday blue, a brief cold-peach sunset, and twilight purple based on the current hour.
- **Aurora & Stars at Night**: Wavy ribbons of green, cyan, and violet aurora borealis drift above a field of stars on the long winter nights.
- **Arcing Celestial Objects**: A pale winter sun (with faint rotating rays and a cold halo) and a silver crescent moon rise and set along a circular path, driven by the **real sunrise/sunset** computed from the watch's location and today's date (falls back to a fixed winter schedule when no location fix is available). The sky, day/night, and aurora all follow the same real sun times.
- **Drifting Snow Clouds & Rolling Drifts**: Soft clouds drift across the sky, and overlapping snow-drift layers roll gently at the bottom with real-time motion in active mode.
- **Snow-laden Pine Silhouette**: A tiered evergreen with snow caps sways in the breeze at the snowbank.
- **Falling Snow**: Gentle snowflakes drift down across the whole face in active mode.
- **Snowflake Seconds**: A six-armed snowflake second indicator orbits the outer perimeter.
- **Centered Digital Time**: Large, clean, rounded clock numerals (Arial Rounded MT Bold) centered with high-contrast black outlining.
- **Centered Date & Weather**: An elegant date line (Segoe UI Light) showing the calendar date and dynamic weather temperature (with automatic Celsius/Fahrenheit unit conversion).
- **Configurable Complications**: The bottom-left and bottom-right complications are each chosen in the app settings, and the watch draws a matching icon:
  - **❤ Heart Rate** (icy-mint heart) — live BPM, sampled at most once every ~10s to spare the battery.
  - **⚡ Body Battery** (teal bolt) — Garmin's 0–100 energy score.
  - **🔋 Device Battery** (glacier-blue battery with a live fill bar) — the watch's charge.
  - **👣 Steps** (frost boot) — today's step count.
  - **🔥 Calories** (ember flame) — today's calories.
  - **Off** — hide the complication.
  - Defaults: left = Heart Rate, right = Device Battery.
  - **Bottom-center**: A steps progress bar (frosted ice themed) + steps numeric count, always shown.
- **High-Contrast Text Outlines**: All text elements (clock, date, and metrics) are drawn with a custom black outline to ensure legibility against any dynamic gradient or snow background.

## Hardware / scaling

The project targets the Fenix 8 and tactix 8 platforms. Connect IQ has no dedicated `tactix8` product id, so the project targets the Fenix 8 AMOLED and Solar products:

| Product id      | Resolution | Case            | Panel Type |
|-----------------|------------|-----------------|------------|
| `fenix847mm`    | 454×454    | tactix 8 51mm   | AMOLED     |
| `fenix843mm`    | 416×416    | tactix 8 47mm   | AMOLED     |
| `fenix8pro47mm` | 454×454    | Fenix 8 Pro     | AMOLED     |
| `fenix8solar51mm` / `fenix8solar47mm` | 280/260 | Fenix 8 Solar | MIP (Solar) |
| `fr965`         | 454×454    | Forerunner 965  | AMOLED     |
| `fr970`         | 454×454    | Forerunner 970  | AMOLED     |

Everything is laid out in percentages of `dc.getWidth()/getHeight()` and the screen center, so it scales cleanly across all of these resolutions.

## Always-on display

The face has two render paths sharing one `onUpdate()`:

- **Active mode** — full brightness, animations (snow drifts, swaying pine, sun rotation, falling snow, drifting clouds, aurora), sky gradients, and text outlines.
- **Always-on / low-power** (`mIsSleep`) — burn-in-safe: dim grey time/date, thin outline representations of the battery metrics, steps progress outline, and **no visual fills or background animations**. All lit pixels are shifted a few pixels each minute (`requiresBurnInProtection`). `onPartialUpdate()` only repaints when the minute changes, staying well inside the always-on power budget.

## Data sources

- **Steps + goal:** `ActivityMonitor.getInfo()` (`steps`, `stepGoal`).
- **Calories:** `ActivityMonitor.getInfo().calories`.
- **Heart rate:** `Activity.getActivityInfo().currentHeartRate` (with an `ActivityMonitor.getHeartRateHistory` fallback), cached and refreshed at most once every ~10s.
- **Device battery:** `System.getSystemStats().battery`.
- **Body Battery:** `SensorHistory.getBodyBatteryHistory()`. Fails gracefully if the value is unavailable.
- **Weather:** `Weather.getCurrentConditions()` (uses Connect IQ weather APIs to display current temperature in Celsius or Fahrenheit depending on device settings).
- **Location & sun times:** last-known location from `Activity.getActivityInfo().currentLocation` (or the weather observation location — neither powers up GPS); sunrise/sunset are computed locally with a standard NOAA almanac formula and cached per day.

## Settings

Editable in Garmin Connect / the simulator's App Settings:

- **Show Date** — toggle the date and weather line.
- **Step Goal Override** — steps for a full progress bar; `0` uses the watch's own step goal.
- **Bottom-Left Complication** — Off / Heart Rate / Body Battery / Device Battery / Steps / Calories.
- **Bottom-Right Complication** — same options (each shows an emoji in the phone picker and a matching icon on the watch).

## Build & run

Prerequisites: the **Connect IQ SDK** and a JDK. Paths live in `build_config.json` (auto-created on first run) — edit them to match your machine:

```json
{
  "JavaHome": "C:\\Program Files\\Android\\openjdk\\jdk-21.0.8",
  "SdkDir":   "C:\\Users\\<you>\\AppData\\Roaming\\Garmin\\ConnectIQ\\Sdks\\<sdk-version>"
}
```

### Build (default device = `fenix847mm`, 454×454)

```powershell
./build.ps1                     # build .prg
./build.ps1 -Device fenix843mm  # build the 416×416 variant
./build.ps1 -Export             # package a store-ready .iq
```

### Build + launch in the simulator

```powershell
./build.ps1 -Run                # or double-click run_simulator.bat
```

In the simulator you can exercise the design via the menus:
- **Settings → Battery** to move the device-battery complication.
- **Simulation → Body Battery** for the Body Battery percentage.
- **Simulation → Time / Sleep** (Always On) to preview the low-power render path.
- **Simulation → Set Time** to test different hour transitions (dawn, pale noon, cold sunset, and the aurora-lit night).

### Sideload to the watch

1. Build the `.prg` (or `.iq`).
2. Connect the watch by USB; it mounts as a drive.
3. Copy `bin/Snowfall.prg` to `GARMIN/APPS/` on the device.
4. Eject and select **Snowfall** from the watch face list.

For store distribution, upload the `.iq` from `./build.ps1 -Export`.

## Fonts & Typography

The face renders using custom rasterized bitmap fonts:

- **Time font**: *Arial Rounded MT Bold* (`exocet_time.fnt`/`.png`).
- **Date / Metrics font**: *Segoe UI Light* (`exocet_label.fnt`/`.png`).

The bitmap font pipeline is:

```
fonts-src/RoundedTime.ttf  ──┐
fonts-src/SegoeUILight.ttf ──┤  python tools/gen_fonts.py
                             └─▶  resources/fonts/exocet_*.fnt + .png
```

- `tools/gen_fonts.py` rasterizes the glyphs we use (digits, symbols like `:` and `%`, and standard letters) into alpha atlases so `dc.setColor()` tints them. Re-run it if you need to modify font sizes or support new characters.
- `resources/fonts/fonts.xml` declares `ExocetTime` / `ExocetValue` / `ExocetLabel`.
- `initFonts()` loads them, falling back to vector fonts then built-ins if missing.

## Customizing

- **Colors / palettes**: drift, pine, cloud, aurora, and sky gradient palettes are constants and function calculations inside `SnowfallView.mc`.
- **Layout anchors**: all coordinate scales are relative percentage values in `onUpdate()`.
