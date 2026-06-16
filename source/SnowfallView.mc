import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Application;
import Toybox.SensorHistory;
import Toybox.Position;
import Toybox.Math;
import Toybox.Weather;

//
// Snowfall - a winter alpine watch face.
//
//   - Center:  large digital time (Rounded) + elegant date line (Segoe UI)
//   - Left:    configurable complication (default heart rate)
//   - Right:   configurable complication (default device battery)
//   - Bottom:  steps progress bar, styled as a frosted ice bar
//   - Background: living winter sky gradient, arcing pale sun / silver moon,
//                 aurora ribbons + stars at night, drifting snow clouds,
//                 rolling snow drifts, a snow-laden pine, and falling snow
//
// The two bottom complications are chosen in the app settings (heart rate, Body
// Battery, device battery, steps, or calories) and each draws a matching icon.
// The sun, day/night, aurora, and sky track the REAL sunrise/sunset computed from
// the watch's location and today's date, falling back to a fixed winter schedule
// when no location fix is available.
//
// Everything scales cleanly relative to the screen dimensions (dc.getWidth()/getHeight()).
//
class SnowfallView extends WatchUi.WatchFace {

    // --- Screen geometry (resolved in onLayout) ---
    private var mWidth as Number = 0;
    private var mHeight as Number = 0;
    private var mCenterX as Number = 0;
    private var mCenterY as Number = 0;

    // --- State ---
    private var mIsSleep as Boolean = false;
    private var mLowPower as Boolean = false;  // true only on AMOLED in Always-On (burn-in) mode
    private var mFlatGlobes as Boolean = false; // true on MIP: flat 2-tone fills (no banded gradient)
    private var mLastMin as Number = -1;       // throttles low-power partial updates

    // --- Per-frame syscall caches (read once at the top of a redraw, reused
    //     everywhere; helpers fall back to a live read if called outside one). ---
    private var mSettings as System.DeviceSettings or Null = null;  // Fix #6
    private var mClock as System.ClockTime or Null = null;          // Fix #10
    private var mActInfo as ActivityMonitor.Info or Null = null;    // Fix #10

    // --- Sunrise/sunset retry throttle (Fix #7) ---
    private var mSunLastTry as Number = -10000;  // epoch sec of last failed retry

    // --- Adaptive render quality (Fix #13): self-tunes detail to the device by
    //     measuring each active frame and nudging mQuality with hysteresis. ---
    private var mQuality as Number = 2;        // 3 = full detail, 0 = leanest
    private var mFrameStart as Number = 0;
    private const Q_SLOW_MS = 220;             // frame slower than this -> drop a level
    private const Q_FAST_MS = 120;             // faster than this -> raise a level

    // --- AMOLED sky-gradient buffer (Fix #9/#12): render the per-row gradient
    //     into a bitmap once and blit it; repaint in place only when colors
    //     change. MIP uses a flat fill and never touches this. ---
    private var mSkyBufRef as Graphics.BufferedBitmapReference or Null = null;
    private var mSkyKeyTop as Number = -1;
    private var mSkyKeyBottom as Number = -1;
    private var mSkyKeyW as Number = -1;
    private var mSkyKeyH as Number = -1;

    // --- Hoisted per-frame allocations (Fix #2/#3) -------------------------
    // Night star field (was two 18-element literals rebuilt every night frame).
    private const STAR_X = [70, 120, 180, 240, 310, 380, 90, 150, 220, 290, 360, 130, 200, 270, 340, 110, 250, 330] as Array<Number>;
    private const STAR_Y = [50, 70, 45, 60, 55, 75, 110, 95, 120, 105, 115, 160, 150, 175, 155, 200, 210, 195] as Array<Number>;
    // Sky-gradient keyframe color tables (the hour arrays still vary per frame).
    private const SKY_TOP_REAL    = [0x05060F, 0x121028, 0x6E7CA6, 0x9DC2E0, 0xB8D2E8, 0x8FA6CE, 0x7E8EBE, 0x3A3A6A, 0x05060F] as Array<Number>;
    private const SKY_BOTTOM_REAL = [0x0A0C1A, 0x2A2548, 0xC890A8, 0xE8F2FA, 0xF0F6FB, 0xF0D0B0, 0xE8A878, 0x6A4A7A, 0x0A0C1A] as Array<Number>;
    private const SKY_TOP_FB      = [0x05060F, 0x121028, 0x6E7CA6, 0x9DC2E0, 0xB8D2E8, 0x7E8EBE, 0x3A3A6A, 0x0F1228, 0x05060F] as Array<Number>;
    private const SKY_BOTTOM_FB   = [0x0A0C1A, 0x2A2548, 0xC890A8, 0xE8F2FA, 0xF0F6FB, 0xE8A878, 0x6A4A7A, 0x2A2548, 0x0A0C1A] as Array<Number>;
    private const SKY_HOURS_FB    = [0.0, 6.0, 8.0, 11.0, 15.0, 16.5, 18.0, 20.0, 24.0] as Array<Float>;
    // Aurora ribbon keyframes (were rebuilt every night frame).
    private const AUR_BASES  = [0.20, 0.27, 0.24] as Array<Float>;
    private const AUR_AMPS   = [0.045, 0.060, 0.050] as Array<Float>;
    private const AUR_DIM    = [0x1E6E3C, 0x1A5A6E, 0x3A2E6E] as Array<Number>;
    private const AUR_BRIGHT = [0x3FB370, 0x36A6BE, 0x6A5ABE] as Array<Number>;
    // Reusable polygon buffers for the snow drifts + aurora bands.
    private var mDriftPts as Array<Array> or Null = null;
    private var mAuroraPts as Array<Array> or Null = null;

    // --- Complication option ids (must match resources/settings list values) ---
    private const COMP_OFF      = 0;
    private const COMP_HR       = 1;  // heart rate (BPM)
    private const COMP_BODY     = 2;  // Body Battery (%)
    private const COMP_BATTERY  = 3;  // device battery (%)
    private const COMP_STEPS    = 4;  // step count
    private const COMP_CALORIES = 5;  // calories (kcal)

    // --- Settings (see resources/settings) ---
    private var mShowDate as Boolean = true;
    private var mStepGoalOverride as Number = 0;  // 0 => use device step goal
    private var mLeftComp as Number = COMP_HR;       // bottom-left complication
    private var mRightComp as Number = COMP_BATTERY; // bottom-right complication
    private var mFestive as Boolean = false;         // Santa's sleigh + sparkling tree (opt-in)
    private var mShowCritters as Boolean = true;     // occasional winter visitors

    // --- Critter type ids (day + night pools, indexed by a clock hash) ---
    private const CR_CARDINAL   = 0;  // red songbird, flies across the sky (day)
    private const CR_HARE       = 1;  // snowshoe hare, bounds across the snow (day)
    private const CR_FOX        = 2;  // red fox, trots + mid-screen snow-pounce (day)
    private const CR_CHICKADEE  = 3;  // chickadee: glides in, lands & pecks, flits off (day)
    private const CR_OWL        = 4;  // snowy owl, glides across the night sky (night)
    private const CR_ARCTIC_FOX = 5;  // white fox, trots across the snow (night)
    private const CR_WOLF       = 6;  // grey wolf, trots then pauses to howl (night)
    private const CR_STAG       = 7;  // antlered stag, walks across, breath steaming (night)

    // --- Festive timing: a sleigh flyover every SLEIGH_PERIOD seconds, lasting
    //     SLEIGH_FLIGHT seconds as it crosses the sky left-to-right. ---
    private const SLEIGH_PERIOD = 150;  // one flyover every 2.5 minutes
    private const SLEIGH_FLIGHT = 9;    // seconds the sleigh is on screen

    // --- Heart-rate cache (sensor read throttled to once every ~10s) ---
    private var mCachedHr as Number or Null = null;
    private var mHrLastSec as Number = -100;

    // --- Sunrise/sunset cache (recomputed when the day or first fix changes) ---
    private var mSunDay as Number = -1;        // day-of-year the times were computed for
    private var mSunValid as Boolean = false;  // true once a real location fix was used
    private var mSunrise as Float = 7.5;       // local hours; defaults = fixed winter schedule
    private var mSunset as Float = 16.5;

    // --- Fonts (vector fonts with safe fallbacks) ---
    private var mFontTime as Graphics.FontType or Null = null;
    private var mFontDate as Graphics.FontType or Null = null;
    private var mFontValue as Graphics.FontType or Null = null;
    private var mFontLabel as Graphics.FontType or Null = null;

    // --- Color Palettes ----------------------------------------------------
    // Body Battery globe = icy mint / cyan
    private const C_BODY_BRIGHT = 0x9FE8E0;
    private const C_BODY_DARK   = 0x123330;
    private const C_BODY_RIM    = 0xCFF5F0;
    private const C_BODY_GLOW   = 0x1A5A52;

    // Device battery globe = glacier blue
    private const C_BATT_BRIGHT = 0x8FC4FF;
    private const C_BATT_DARK   = 0x122A45;
    private const C_BATT_RIM    = 0xC4E2FF;
    private const C_BATT_GLOW   = 0x1E4A7A;

    // Steps bar = frosted ice / silver-blue
    private const C_XP_TRACK    = 0x141C28;
    private const C_XP_FILL     = 0x6FB6E8;
    private const C_XP_BRIGHT   = 0xCFEFFF;
    private const C_XP_GLOW     = 0x14406A;
    private const C_XP_BORDER   = 0xEAF6FF;

    private const BG_COLOR = 0x000000;        // pitch black for AMOLED contrast/battery

    function initialize() {
        WatchFace.initialize();
        loadSettings();
    }

    // Read user settings; safe to call any time.
    function loadSettings() as Void {
        try {
            if (Application has :Properties) {
                var showDate = Application.Properties.getValue("ShowDate");
                var stepGoal = Application.Properties.getValue("StepGoalOverride");
                var leftComp = Application.Properties.getValue("LeftComplication");
                var rightComp = Application.Properties.getValue("RightComplication");
                var festive = Application.Properties.getValue("FestiveMode");
                var critters = Application.Properties.getValue("ShowCritters");
                if (showDate != null) { mShowDate = showDate; }
                if (stepGoal != null) { mStepGoalOverride = stepGoal; }
                if (leftComp != null) { mLeftComp = leftComp; }
                if (rightComp != null) { mRightComp = rightComp; }
                if (festive != null) { mFestive = festive; }
                if (critters != null) { mShowCritters = critters; }
            }
        } catch (e) {
            // keep defaults
        }
        if (mStepGoalOverride < 0) { mStepGoalOverride = 0; }
    }

    function onLayout(dc as Dc) as Void {
        mWidth = dc.getWidth();
        mHeight = dc.getHeight();
        mCenterX = mWidth / 2;
        mCenterY = mHeight / 2;
        initFonts();
    }

    // Custom fonts generated by gen_fonts.py are loaded here.
    function initFonts() as Void {
        try {
            mFontTime  = WatchUi.loadResource(Rez.Fonts.ExocetTime) as Graphics.FontType;
            mFontValue = WatchUi.loadResource(Rez.Fonts.ExocetValue) as Graphics.FontType;
            mFontLabel = WatchUi.loadResource(Rez.Fonts.ExocetLabel) as Graphics.FontType;
            mFontDate  = mFontLabel;
        } catch (e) {
            mFontTime = null;
            mFontValue = null;
            mFontLabel = null;
            mFontDate = null;
        }

        // Vector-font fallback for anything that didn't load.
        if (Graphics has :getVectorFont) {
            var bold = ["RobotoCondensedBold", "RobotoRegular", "sans-serif"] as Array<String>;
            if (mFontTime == null)  { mFontTime  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.21).toNumber() }); }
            if (mFontDate == null)  { mFontDate  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.058).toNumber() }); }
            if (mFontValue == null) { mFontValue = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.085).toNumber() }); }
            if (mFontLabel == null) { mFontLabel = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.044).toNumber() }); }
        }

        // Built-in last resort.
        if (mFontTime == null)  { mFontTime  = Graphics.FONT_NUMBER_THAI_HOT; }
        if (mFontDate == null)  { mFontDate  = Graphics.FONT_TINY; }
        if (mFontValue == null) { mFontValue = Graphics.FONT_MEDIUM; }
        if (mFontLabel == null) { mFontLabel = Graphics.FONT_XTINY; }
    }

    function onShow() as Void {
        loadSettings();
    }

    // Single render entry point for both active and low-power frames.
    function onUpdate(dc as Dc) as Void {
        mFrameStart = System.getTimer();   // Fix #13: measure this frame's cost

        var w = mWidth;
        var h = mHeight;

        // Cache per-frame syscalls once (Fix #6 / #10): settings, clock, activity.
        var settings = System.getDeviceSettings();
        mSettings = settings;
        var clockTime = System.getClockTime();
        mClock = clockTime;
        mActInfo = ActivityMonitor.getInfo();

        var burnIn = false;
        var dx = 0;
        var dy = 0;
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        if (hasBurnIn && mIsSleep) {
            burnIn = true;
            var shift = computeBurnInShift();
            dx = shift[0]; dy = shift[1];
        }
        mLowPower = burnIn;
        mFlatGlobes = !hasBurnIn;

        var cx = mCenterX + dx;
        var cy = mCenterY + dy;

        // 1. Clear to pitch black
        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();

        // Time values
        var hour = clockTime.hour;
        var min = clockTime.min;
        var secVal = clockTime.sec;

        if (!mLowPower) {
            // --- ACTIVE VISUAL LAYER ---

            // A. Resolve today's sunrise/sunset (cached), then get the living
            //    winter-sky gradient colors for the current time.
            updateSunTimes();
            var tNow = hour.toFloat() + min.toFloat() / 60.0;
            var skyColors = getSkyColors(hour, min);
            var cTop = skyColors[0];
            var cBottom = skyColors[1];

            // B. Draw Sky
            var skyH = (h * 0.76).toNumber();
            if (mFlatGlobes) {
                // MIP: Solid fill to prevent ugly banding
                dc.setColor(cTop, cTop);
                dc.fillRectangle(0, 0, w, skyH);
            } else {
                // AMOLED: smooth gradient, cached in a BufferedBitmap so the
                // per-row fill loop runs ~once/minute, not every frame. (Fix #9/#12)
                var skyBmp = getSkyBitmap(w, skyH, cTop, cBottom);
                if (skyBmp != null) {
                    dc.drawBitmap(0, 0, skyBmp);
                } else {
                    drawSkyGradientDirect(dc, w, skyH, cTop, cBottom);
                }
            }

            var isNight = !(tNow >= mSunrise && tNow < mSunset);

            // At most one critter is active at a time; computed purely from the
            // clock (no RNG/state). Sky visitors draw in the sky pass below;
            // ground visitors draw after the snowbank so they stand on the snow.
            var crit = mShowCritters ? computeCritter(hour, min, secVal, isNight) : null;

            // C. Draw Aurora ribbons + Stars at night
            if (isNight) {
                if (!mFlatGlobes) {
                    drawAurora(dc, w, skyH, secVal);
                }
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                for (var i = 0; i < STAR_X.size(); i++) {
                    var sx = (STAR_X[i] * w / 454).toNumber();
                    var sy = (STAR_Y[i] * h / 454).toNumber();
                    dc.drawPoint(sx, sy);
                }

                // In Festive Mode, one star becomes the radiant Star of Bethlehem
                if (mFestive) {
                    drawBethlehemStar(dc, (w * 0.74).toNumber(), (h * 0.14).toNumber(), w, secVal);
                }
            }

            // D. Draw Arcing Pale Sun / Silver Moon along the real day arc
            var dayStart = mSunrise;
            var dayEnd = mSunset;
            var t = tNow;
            var isDay = !isNight;
            var arcR = (w * 0.38).toNumber();
            var arcCenterY = (h * 0.68).toNumber();

            var angle = 0.0;
            if (isDay) {
                angle = Math.PI - (Math.PI * (t - dayStart) / (dayEnd - dayStart));
            } else {
                var tNight = (t < dayStart) ? (t + (24.0 - dayEnd)) : (t - dayEnd);
                angle = Math.PI - (Math.PI * tNight / (24.0 - (dayEnd - dayStart)));
            }
            var sx = cx + (arcR * Math.cos(angle)).toNumber();
            var sy = arcCenterY - (arcR * Math.sin(angle)).toNumber();

            if (isDay) {
                var sunR = (w * 0.065).toNumber();
                var sunSkyFrac = sy.toFloat() / skyH.toFloat();
                if (sunSkyFrac < 0.0) { sunSkyFrac = 0.0; }
                if (sunSkyFrac > 1.0) { sunSkyFrac = 1.0; }
                var sunSkyColor = lerpColor(cTop, cBottom, sunSkyFrac);

                // Faint rays rotation based on seconds (dropped at low quality, Fix #13)
                if (mQuality >= 2) {
                    dc.setColor(0xCFE6F5, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(1);
                    var numRays = 8;
                    var secOffset = secVal.toFloat() * 0.02;
                    for (var i = 0; i < numRays; i++) {
                        var rayAngle = (i * (2.0 * Math.PI / numRays)) + secOffset;
                        var rx1 = (sx + (sunR + 2) * Math.cos(rayAngle)).toNumber();
                        var ry1 = (sy + (sunR + 2) * Math.sin(rayAngle)).toNumber();
                        var rx2 = (sx + (sunR + 8) * Math.cos(rayAngle)).toNumber();
                        var ry2 = (sy + (sunR + 8) * Math.sin(rayAngle)).toNumber();
                        dc.drawLine(rx1, ry1, rx2, ry2);
                    }
                }

                // Cold pale halo
                dc.setColor(lerpColor(sunSkyColor, 0xDCEAF8, 0.25), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR + 6);
                dc.setColor(lerpColor(sunSkyColor, 0xDCEAF8, 0.55), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR + 3);

                // Core (pale winter sun)
                dc.setColor(0xEAF2FF, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR);
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR - 4);
            } else {
                var moonR = (w * 0.055).toNumber();
                var moonSkyFrac = sy.toFloat() / skyH.toFloat();
                if (moonSkyFrac < 0.0) { moonSkyFrac = 0.0; }
                if (moonSkyFrac > 1.0) { moonSkyFrac = 1.0; }
                var moonSkyColor = lerpColor(cTop, cBottom, moonSkyFrac);

                // Silver base circle
                dc.setColor(0xE6ECF2, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, moonR);
                // Offset circle of sky color to mask crescent
                dc.setColor(moonSkyColor, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx + 5, sy - 2, moonR);
            }

            // E. Draw Drifting Snow Clouds
            var cloudOffset = (min * 60 + secVal).toFloat();
            // Positive modulo: Monkey C's % keeps the dividend's sign, so a
            // drifting (possibly negative) position must wrap with ((v%s)+s)%s.
            var cloudSpan = w + 80;
            var cx1 = (((((w * 0.1 + (cloudOffset * 0.08)).toNumber()) % cloudSpan) + cloudSpan) % cloudSpan) - 40;
            var cx2 = (((((w * 0.7 - (cloudOffset * 0.05)).toNumber()) % cloudSpan) + cloudSpan) % cloudSpan) - 40;
            drawCloud(dc, cx1, (h * 0.20).toNumber());
            drawCloud(dc, cx2, (h * 0.28).toNumber());

            // E2. Sky critters (cardinal / owl) glide through the sky here.
            if (crit != null && isSkyCritter(crit[0] as Number)) {
                drawCritter(dc, crit);
            }

            // F. Draw Rolling Snow Drifts (sine-wave polygons, gentle)
            var driftPhase1 = secVal.toFloat() * 0.04;
            var driftPhase2 = -secVal.toFloat() * 0.05;
            // Back drift (shadowed snow)
            drawDrift(dc, (h * 0.76).toNumber(), 4, 50.0, driftPhase1, 0xAFC6DC);
            // Front drift (bright snow)
            drawDrift(dc, (h * 0.81).toNumber(), 5, 38.0, driftPhase2, 0xEAF2FA);

            // G. Draw Snowbank Foreground
            var bankY = (h * 0.88).toNumber();
            dc.setColor(0xF4FAFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, bankY, w, h - bankY);

            // H. Draw Snow-laden Pine, swaying in the wind (decked out in lights
            //    and a sparkling star topper when Festive Mode is on)
            var pineSway = 0.06 * Math.sin(secVal.toFloat() * 0.15);
            drawPineTree(dc, (w * 0.82).toNumber(), bankY, (h * 0.40).toNumber(), pineSway, secVal);

            // H2. Santa's sleigh, sweeping across the sky once in a while
            if (mFestive) {
                drawSleighFlyover(dc, w, h, hour, min, secVal);
            }

            // H3. Ground critters (hare/fox/chickadee/wolf/stag) walk on the snow.
            if (crit != null && !isSkyCritter(crit[0] as Number)) {
                drawCritter(dc, crit);
            }

            // I. Draw Falling Snow
            drawSnow(dc, w, h, secVal, min);
        }

        // --- Center Clock & Date ---
        drawTime(dc, cx, cy - (h * 0.05).toNumber());
        if (mShowDate) {
            drawDate(dc, cx, cy + (h * 0.06).toNumber());
        }

        // --- Bottom Snowfield Complications (Symmetrical Layout) ---
        var metricsY = (h * 0.815).toNumber() + dy;
        var leftX    = (w * 0.22).toNumber() + dx;
        var rightX   = (w * 0.78).toNumber() + dx;

        // Bottom complications are user-configurable (see resources/settings).
        drawComplication(dc, leftX, metricsY, mLeftComp);
        drawComplication(dc, rightX, metricsY, mRightComp);

        // Steps Progress Bar & Numeric Text (Centered)
        var barW = (w * 0.38).toNumber();
        var barH = 8;
        var barY = (h * 0.91).toNumber() + dy;
        var stepsFraction = getStepFraction();
        drawXpBar(dc, cx, barY, barW, barH, stepsFraction);

        if (!burnIn) {
            var actInfo = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
            var steps = (actInfo != null && actInfo.steps != null) ? actInfo.steps : 0;
            var stepsStr = steps.format("%d") + " STEPS";
            drawTextWithOutline(dc, cx, barY - 14, mFontLabel, stepsStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, 0xFFFFFF);
        }

        // Snowflake seconds marker — drawn LAST so it sits on top of the time,
        // date, and complications (draw order = z-order in CIQ). Only animates
        // while active; gated on mIsSleep (NOT mLowPower) so it hides correctly
        // on MIP too, where mLowPower is never true. (Fix #14 + z-order)
        if (!mIsSleep) {
            var secAngle = (secVal * 6.0) * Math.PI / 180.0;
            var secRadius = (w * 0.44).toNumber() - 10;
            var fsx = cx + (secRadius * Math.sin(secAngle)).toNumber();
            var fsy = cy - (secRadius * Math.cos(secAngle)).toNumber();
            drawSnowflake(dc, fsx, fsy);
        }

        // Adaptive quality (Fix #13): nudge detail up/down by this frame's cost,
        // active frames only — never adapt in low-power/AOD.
        if (!mLowPower) {
            var dt = System.getTimer() - mFrameStart;
            if (dt > Q_SLOW_MS) { if (mQuality > 0) { mQuality--; } }
            else if (dt < Q_FAST_MS) { if (mQuality < 3) { mQuality++; } }
        }
    }

    // Shared anti-burn-in pixel shift (Fix #2 dedup): used by both onUpdate and
    // the AMOLED onPartialUpdate cheap path so they nudge by the same amount.
    private function computeBurnInShift() as Array<Number> {
        var clock = (mClock != null) ? mClock : System.getClockTime();
        var phase = clock.min % 4;
        if (phase == 1)      { return [4, 2]; }
        else if (phase == 2) { return [-3, 4]; }
        else if (phase == 3) { return [3, -4]; }
        return [0, 0];
    }

    // ------------------------------------------------------------------ Elements

    function drawTime(dc as Dc, cx as Number, cy as Number) as Void {
        var clock = (mClock != null) ? mClock : System.getClockTime();
        var hour = clock.hour;
        var min = clock.min;
        var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
        var is24 = settings.is24Hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var hourStr = is24 ? hour.format("%02d") : hour.format("%d");
        var timeStr = hourStr + ":" + min.format("%02d");

        // Dim in AOD, bright frost-white otherwise
        var color = mLowPower ? 0x6E6E6E : 0xEAF6FF;
        drawTextWithOutline(dc, cx, cy, mFontTime, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, color);
    }

    function drawDate(dc as Dc, cx as Number, y as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week.toUpper() + "   " + info.month.toUpper() + " " + info.day;

        // Append weather if available. Skip the lookup in always-on so it stays
        // out of the partial-update budget and the dim AOD date matches the full
        // and partial redraws (no flicker). (Fix #11)
        var weatherStr = mLowPower ? null : getWeatherString();
        if (weatherStr != null) {
            dateStr = dateStr + "   •   " + weatherStr;
        }

        // Dim in AOD, cool ice blue otherwise
        var color = mLowPower ? 0x555555 : 0x8FC4FF;
        drawTextWithOutline(dc, cx, y, mFontDate, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, color);
    }

    private function drawCloud(dc as Dc, x as Number, y as Number) as Void {
        dc.setColor(0xDCE6F0, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 12, y, 10);
        dc.fillCircle(x + 12, y, 10);
        dc.fillCircle(x, y - 5, 14);
        dc.fillRectangle(x - 12, y - 2, 24, 12);
    }

    // Aurora borealis: a few wavy ribbons of green/cyan/violet light near the
    // top of the night sky. Each ribbon is a dim wide band with a brighter core.
    private function drawAurora(dc as Dc, w as Number, skyH as Number, sec as Number) as Void {
        // Ribbon count scales with adaptive quality (Fix #13); at the leanest
        // level the dim wide under-band is dropped too.
        var ribbons = (mQuality >= 2) ? 3 : (mQuality == 1) ? 2 : 1;
        for (var b = 0; b < ribbons; b++) {
            var baseY = (skyH * AUR_BASES[b]).toNumber();
            var amp = skyH * AUR_AMPS[b];
            var phase = sec.toFloat() * 0.03 + b * 1.7;
            if (mQuality >= 1) {
                drawAuroraBand(dc, w, baseY, amp, (skyH * 0.10).toNumber(), phase, AUR_DIM[b]);
            }
            drawAuroraBand(dc, w, baseY, amp, (skyH * 0.035).toNumber(), phase, AUR_BRIGHT[b]);
        }
    }

    private function drawAuroraBand(dc as Dc, w as Number, baseY as Number, amp as Float, thick as Number, phase as Float, color as Number) as Void {
        var steps = 16;
        var n = (steps + 1) * 2;
        // Reuse a persistent buffer (steps is fixed) instead of allocating a
        // fresh [n] array of pairs on every band. (Fix #3)
        if (mAuroraPts == null) {
            var buf = new [n] as Array<Array>;
            for (var k = 0; k < n; k++) { buf[k] = [0, 0]; }
            mAuroraPts = buf;
        }
        var pts = mAuroraPts;
        var sw = w / steps;
        for (var i = 0; i <= steps; i++) {
            var x = i * sw;
            var y = baseY + (amp * Math.sin(x.toFloat() / 55.0 + phase)).toNumber();
            pts[i][0] = x; pts[i][1] = y;
            pts[n - 1 - i][0] = x; pts[n - 1 - i][1] = y + thick;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    private function drawDrift(dc as Dc, yBase as Number, amp as Number, waveLen as Float, phase as Float, color as Number) as Void {
        var w = mWidth;
        var h = mHeight;

        var steps = 12;
        var stepW = w / steps;
        // Reuse a persistent buffer (steps is fixed) instead of allocating a
        // fresh [steps+3] array of pairs every call. (Fix #3)
        if (mDriftPts == null) {
            var buf = new [steps + 3] as Array<Array>;
            for (var k = 0; k < steps + 3; k++) { buf[k] = [0, 0]; }
            mDriftPts = buf;
        }
        var points = mDriftPts;
        points[0][0] = w; points[0][1] = h;
        points[1][0] = 0; points[1][1] = h;

        for (var i = 0; i <= steps; i++) {
            var x = i * stepW;
            var angle = (x.toFloat() / waveLen) + phase;
            var y = yBase + (amp * Math.sin(angle)).toNumber();
            points[i + 2][0] = x;
            points[i + 2][1] = y;
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(points);
    }

    // A snow-laden evergreen: tapered trunk + tiered triangles with snow on top.
    // When Festive Mode is on it is strung with blinking lights and crowned with
    // a twinkling star topper; `sec` drives the blink/twinkle animation.
    private function drawPineTree(dc as Dc, baseX as Number, baseY as Number, height as Number, sway as Float, sec as Number) as Void {
        var trunkColor = 0x3A2A1A;
        var green = 0x16401F;     // dark winter pine silhouette
        var snow = 0xEAF6FF;

        var trunkH = (height * 0.16).toNumber();
        var trunkW = (height * 0.05).toNumber();
        if (trunkW < 3) { trunkW = 3; }
        dc.setColor(trunkColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(baseX - trunkW / 2, baseY - trunkH, trunkW, trunkH);

        var tiers = 3;
        var tierH = (height * 0.34).toNumber();
        var baseHalf = (height * 0.30).toNumber();
        var topApexX = baseX;
        var topApexY = baseY;
        for (var i = 0; i < tiers; i++) {
            // Lower (i=0) tier is widest; tiers overlap going up.
            var ty = baseY - trunkH - (i * (tierH * 0.62)).toNumber();
            var apexY = ty - tierH;
            var halfW = (baseHalf * (tiers - i).toFloat() / tiers.toFloat()).toNumber();
            var leanX = (sway * (baseY - apexY)).toNumber();

            // Green body
            dc.setColor(green, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[baseX - halfW, ty], [baseX + halfW, ty], [baseX + leanX, apexY]] as Array<Array>);

            // Snow cap near the apex
            var snowTy = ty - (tierH * 0.45).toNumber();
            var snowHalf = (halfW * 0.5).toNumber();
            dc.setColor(snow, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[baseX + leanX - snowHalf, snowTy], [baseX + leanX + snowHalf, snowTy], [baseX + leanX, apexY]] as Array<Array>);

            // Festive string of lights draped along this tier's base edge
            if (mFestive) {
                drawTreeLights(dc, baseX - halfW, baseX + halfW, ty, i, height, sec);
            }

            // Remember the topmost apex for the star topper
            if (i == tiers - 1) {
                topApexX = baseX + leanX;
                topApexY = apexY;
            }
        }

        // Sparkling star topper at the very top of the tree
        if (mFestive) {
            var starR = (height * 0.075).toNumber();
            if (starR < 5) { starR = 5; }
            drawStarTopper(dc, topApexX, topApexY - (starR / 2), starR, sec);
        }
    }

    // A garland of small colored lights along a tier's base edge. Each light
    // blinks on a staggered schedule so the whole string twinkles; lit bulbs
    // get a warm glow + white sparkle, dark ones are dimmed to a faint ember.
    private function drawTreeLights(dc as Dc, x1 as Number, x2 as Number, y as Number, tier as Number, height as Number, sec as Number) as Void {
        var colors = [0xFF3B30, 0xFFD23F, 0x37C0FF, 0x44E06A, 0xFF7AD0] as Array<Number>;
        var r = (height * 0.022).toNumber();
        if (r < 2) { r = 2; }

        var count = 4 + tier;          // wider lower tiers carry more lights
        var span = (x2 - x1).toFloat();
        for (var k = 0; k < count; k++) {
            var fx = (x1 + span * (k + 1).toFloat() / (count + 1).toFloat()).toNumber();
            // Slight downward sag toward the middle of the garland
            var midFrac = ((k + 1).toFloat() / (count + 1).toFloat());
            var sag = (r * 1.5 * Math.sin(midFrac * Math.PI)).toNumber();
            var fy = y + sag;

            var ci = (k + tier) % colors.size();
            var color = colors[ci];

            // Stagger blink so neighbours are rarely lit together
            var lit = (((sec + k * 2 + tier * 3) % 5) < 3);
            if (lit) {
                dc.setColor(scaleColor(color, 0.30), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(fx, fy, r + 2);            // soft glow
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(fx, fy, r);
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(fx, fy, (r > 2) ? (r - 2) : 1);   // hot white center
            } else {
                dc.setColor(scaleColor(color, 0.45), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(fx, fy, (r > 1) ? r - 1 : 1);     // dim ember
            }
        }
    }

    // A five-pointed star topper that twinkles: the body pulses gently in size
    // and a white sparkle cross flashes across it on a slow cadence.
    private function drawStarTopper(dc as Dc, cxp as Number, cyp as Number, r as Number, sec as Number) as Void {
        var pulse = 0.85 + 0.15 * Math.sin(sec.toFloat() * 0.9);
        var rOuter = (r * pulse);
        var rInner = rOuter * 0.42;

        // Gold halo behind the star
        dc.setColor(0x4A3A10, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cxp, cyp, (rOuter + 2).toNumber());

        // Build the 10-point star polygon, first point straight up
        var pts = new [10] as Array<Array>;
        for (var i = 0; i < 10; i++) {
            var rad = (i % 2 == 0) ? rOuter : rInner;
            var ang = -Math.PI / 2.0 + i * (Math.PI / 5.0);
            pts[i] = [(cxp + rad * Math.cos(ang)).toNumber(), (cyp + rad * Math.sin(ang)).toNumber()];
        }
        dc.setColor(0xFFD23F, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);

        // Bright core
        dc.setColor(0xFFF6CC, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cxp, cyp, (rInner * 0.7).toNumber());

        // Twinkle: a white sparkle cross that flares for part of each cycle
        if ((sec % 4) < 2) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            var sp = (rOuter + r * 0.6).toNumber();
            dc.drawLine(cxp - sp, cyp, cxp + sp, cyp);
            dc.drawLine(cxp, cyp - sp, cxp, cyp + sp);
        }
    }

    // The Star of Bethlehem: a brilliant white star with a glowing halo, four
    // long shimmering rays (the lower one extended, nativity-style) and shorter
    // diagonal sparkles. Gently pulses so it shines against the night sky.
    private function drawBethlehemStar(dc as Dc, cxp as Number, cyp as Number, w as Number, sec as Number) as Void {
        var pulse = 0.85 + 0.15 * Math.sin(sec.toFloat() * 0.8);
        var ray = (w * 0.085 * pulse).toNumber();    // main ray length
        var diag = (ray * 0.45).toNumber();          // diagonal sparkle length
        var down = (ray * 1.6).toNumber();           // extended lower ray
        if (ray < 8) { ray = 8; }

        // Soft golden-white halo
        dc.setColor(0x3A3A2A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cxp, cyp, (w * 0.018).toNumber() + 2);

        // Long shimmering rays (vertical extended down, horizontal, diagonals)
        dc.setColor(0xFFF6CC, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cxp, cyp - ray, cxp, cyp + down);     // vertical w/ long tail
        dc.drawLine(cxp - ray, cyp, cxp + ray, cyp);      // horizontal
        dc.drawLine(cxp - diag, cyp - diag, cxp + diag, cyp + diag);
        dc.drawLine(cxp + diag, cyp - diag, cxp - diag, cyp + diag);

        // Bright core
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cxp, cyp, (w * 0.011).toNumber() + 1);
        dc.setColor(0xFFF2B0, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cxp, cyp, (w * 0.005).toNumber() + 1);
    }

    // Santa's sleigh and reindeer sweep across the upper sky once every
    // SLEIGH_PERIOD seconds, taking SLEIGH_FLIGHT seconds to cross left-to-right.
    // Outside that window nothing is drawn, so it's a rare little treat.
    private function drawSleighFlyover(dc as Dc, w as Number, h as Number, hour as Number, min as Number, sec as Number) as Void {
        var secOfDay = hour * 3600 + min * 60 + sec;
        var cyclePos = secOfDay % SLEIGH_PERIOD;
        if (cyclePos >= SLEIGH_FLIGHT) { return; }

        var p = cyclePos.toFloat() / SLEIGH_FLIGHT.toFloat();   // 0..1 across screen
        var margin = (w * 0.30).toNumber();
        var x = (-margin + p * (w + 2 * margin)).toNumber();    // lead reindeer X
        // Gentle vertical bob along the flight path
        var baseY = (h * 0.17).toNumber();
        var y = baseY + (h * 0.03 * Math.sin(p * Math.PI * 3.0)).toNumber();

        drawSleigh(dc, x, y, sec);
    }

    // Draws the full team (sleigh + two reindeer + reins + Santa) moving right,
    // scaled to the screen. `x,y` is the lead reindeer's front-foot anchor.
    private function drawSleigh(dc as Dc, x as Number, y as Number, sec as Number) as Void {
        var s = mWidth / 280.0;
        if (s < 0.7) { s = 0.7; }

        var deerColor   = 0x5A3A1F;   // brown reindeer silhouette
        var sleighColor = 0xD83A2A;   // festive red sleigh
        var trimColor   = 0xFFD23F;   // gold trim / runner
        var santaColor  = 0xE8392B;   // Santa's coat

        var lead = x;
        var rear = (x - 30 * s).toNumber();
        var sleighX = (x - 64 * s).toNumber();

        // Reins arcing from the sleigh up to the reindeer
        dc.setColor(0x2A1A0E, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((s > 1.0) ? 2 : 1);
        dc.drawLine(sleighX + (10 * s).toNumber(), (y - 10 * s).toNumber(), rear - (8 * s).toNumber(), (y - 8 * s).toNumber());
        dc.drawLine(rear - (8 * s).toNumber(), (y - 8 * s).toNumber(), lead - (8 * s).toNumber(), (y - 8 * s).toNumber());

        drawReindeer(dc, rear, y, s, deerColor, false);
        drawReindeer(dc, lead, y, s, deerColor, true);   // lead = Rudolph (red nose)
        drawSleighBody(dc, sleighX, y, s, sleighColor, trimColor, santaColor);

        // Trailing stardust behind the sleigh, twinkling with the seconds
        var sparkleColors = [0xFFD23F, 0xFFFFFF, 0xCFEFFF] as Array<Number>;
        for (var i = 0; i < 4; i++) {
            if (((sec + i) % 2) == 0) { continue; }
            var tx = (sleighX - (14 + i * 11) * s).toNumber();
            var ty = (y + ((i % 2 == 0) ? -4 : 6) * s).toNumber();
            dc.setColor(sparkleColors[i % sparkleColors.size()], Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(tx, ty, (s > 1.0) ? 2 : 1);
        }
    }

    // One reindeer facing right, anchored at its front foot (rx, ry).
    private function drawReindeer(dc as Dc, rx as Number, ry as Number, s as Float, color as Number, lead as Boolean) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((s > 1.0) ? 2 : 1);

        // Legs
        dc.drawLine(rx - (10 * s).toNumber(), ry, rx - (10 * s).toNumber(), (ry + 6 * s).toNumber());
        dc.drawLine(rx - (2 * s).toNumber(),  ry, rx - (2 * s).toNumber(),  (ry + 6 * s).toNumber());

        // Body + neck
        dc.fillRoundedRectangle(rx - (12 * s).toNumber(), (ry - 6 * s).toNumber(), (13 * s).toNumber(), (7 * s).toNumber(), (2 * s).toNumber());
        dc.fillPolygon([
            [rx - (2 * s).toNumber(),  (ry - 4 * s).toNumber()],
            [rx + (4 * s).toNumber(),  (ry - 13 * s).toNumber()],
            [rx + (7 * s).toNumber(),  (ry - 12 * s).toNumber()],
            [rx + (3 * s).toNumber(),  (ry - 3 * s).toNumber()]
        ] as Array<Array>);

        // Head
        dc.fillCircle((rx + 6 * s).toNumber(), (ry - 13 * s).toNumber(), (3 * s).toNumber());

        // Antlers
        var hx = (rx + 6 * s).toNumber();
        var hy = (ry - 15 * s).toNumber();
        dc.drawLine(hx, hy, (hx - 3 * s).toNumber(), (hy - 5 * s).toNumber());
        dc.drawLine(hx, hy, (hx + 3 * s).toNumber(), (hy - 5 * s).toNumber());
        dc.drawLine((hx + 3 * s).toNumber(), (hy - 5 * s).toNumber(), (hx + 6 * s).toNumber(), (hy - 4 * s).toNumber());

        // Rudolph's glowing red nose on the lead reindeer
        if (lead) {
            dc.setColor(0xFF2A2A, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle((rx + 9 * s).toNumber(), (ry - 13 * s).toNumber(), (s > 1.0) ? 2 : 1);
        }
    }

    // The sleigh itself, anchored at its mid-base (px, py), with Santa aboard.
    private function drawSleighBody(dc as Dc, px as Number, py as Number, s as Float, body as Number, trim as Number, santa as Number) as Void {
        // Sleigh body: a seat that curls up at the back (left)
        dc.setColor(body, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [px - (16 * s).toNumber(), (py - 2 * s).toNumber()],
            [px - (16 * s).toNumber(), (py - 14 * s).toNumber()],
            [px - (10 * s).toNumber(), (py - 8 * s).toNumber()],
            [px + (10 * s).toNumber(), (py - 8 * s).toNumber()],
            [px + (10 * s).toNumber(), (py - 2 * s).toNumber()]
        ] as Array<Array>);

        // Santa, seated
        dc.setColor(santa, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(px - (8 * s).toNumber(), (py - 16 * s).toNumber(), (10 * s).toNumber(), (9 * s).toNumber(), (2 * s).toNumber());
        dc.setColor(0xFFE0C0, Graphics.COLOR_TRANSPARENT);   // face
        dc.fillCircle((px - 2 * s).toNumber(), (py - 18 * s).toNumber(), (2 * s).toNumber());
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);   // hat bobble / beard
        dc.fillCircle((px + 1 * s).toNumber(), (py - 21 * s).toNumber(), (s > 1.0) ? 2 : 1);

        // Gold runner with a curled front
        dc.setColor(trim, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((s > 1.0) ? 2 : 1);
        dc.drawLine(px - (16 * s).toNumber(), (py - 1 * s).toNumber(), px + (12 * s).toNumber(), (py - 1 * s).toNumber());
        dc.drawLine(px + (12 * s).toNumber(), (py - 1 * s).toNumber(), px + (15 * s).toNumber(), (py - 5 * s).toNumber());
    }

    // Falling snow particles, drifting down and swaying with a gentle breeze.
    private function drawSnow(dc as Dc, w as Number, h as Number, sec as Number, min as Number) as Void {
        var t = (min * 60 + sec).toFloat();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        // Particle count scales with adaptive quality (Fix #13).
        var n = (mQuality >= 3) ? 22 : (mQuality == 2) ? 18 : (mQuality == 1) ? 12 : 8;
        for (var i = 0; i < n; i++) {
            var colF = ((i * 37) % 100).toFloat() / 100.0;   // base column 0..1
            var speed = 16.0 + (i % 5) * 7.0;                // fall speed
            var drift = 9.0 * Math.sin(t * 0.03 + i);        // horizontal sway
            var x = (colF * w + drift).toNumber();
            if (x < 0) { x += w; }
            if (x >= w) { x -= w; }
            var y = (i * 23 + (t * speed).toNumber()) % h;
            var r = (i % 4 == 0) ? 2 : 1;
            dc.fillCircle(x, y, r);
        }
    }

    private function drawSnowflake(dc as Dc, sx as Number, sy as Number) as Void {
        // Black outline pass (thicker arms + a backing dot), then the bright
        // flake on top, so the marker stays legible over the time/date text and
        // bright snow alike.
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        snowflakeArms(dc, sx, sy, 3);
        dc.fillCircle(sx, sy, 4);

        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        snowflakeArms(dc, sx, sy, 1);
        dc.setColor(0xCFEFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 2);
        dc.setPenWidth(1);
    }

    // The six spokes + their little branch arms, drawn at the given pen width
    // (caller sets the colour). Used twice: a thick black outline, then white.
    private function snowflakeArms(dc as Dc, sx as Number, sy as Number, penW as Number) as Void {
        dc.setPenWidth(penW);
        for (var a = 0; a < 360; a += 60) {
            var rad = a * Math.PI / 180.0;
            var ex = (sx + 7 * Math.cos(rad)).toNumber();
            var ey = (sy + 7 * Math.sin(rad)).toNumber();
            dc.drawLine(sx, sy, ex, ey);

            // Little branch arms partway along each spoke
            var bx = (sx + 4 * Math.cos(rad)).toNumber();
            var by = (sy + 4 * Math.sin(rad)).toNumber();
            var p1 = rad + 0.6;
            var p2 = rad - 0.6;
            dc.drawLine(bx, by, (bx + 3 * Math.cos(p1)).toNumber(), (by + 3 * Math.sin(p1)).toNumber());
            dc.drawLine(bx, by, (bx + 3 * Math.cos(p2)).toNumber(), (by + 3 * Math.sin(p2)).toNumber());
        }
    }

    private function drawWinterBezel(dc as Dc, gx as Number, gy as Number, r as Number, lit as Boolean) as Void {
        var ice       = lit ? 0xC4E2FF : 0x5A7088;
        var frost     = lit ? 0xEAF6FF : 0xC0CEDC;
        var glowColor = lit ? 0xDCEAF8 : 0x14406A;

        if (lit) {
            dc.setPenWidth(4);
            dc.setColor(scaleColor(glowColor, 0.4), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
        }

        dc.setPenWidth(3);
        dc.setColor(frost, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r + 1);

        dc.setPenWidth(1);
        dc.setColor(ice, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r - 1);
    }

    // Liquid-fill globe.
    function drawGlobe(dc as Dc, gx as Number, gy as Number, r as Number,
                       value as Number, available as Boolean,
                       bright as Number, dark as Number, rim as Number, glow as Number) as Void {
        if (mLowPower) {
            drawGlobeLowPower(dc, gx, gy, r, value, available, rim);
            return;
        }

        // 1. Soft outer glow
        if (available && value > 0 && !mFlatGlobes) {
            dc.setPenWidth(3);
            dc.setColor(scaleColor(glow, 0.60), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
            dc.setPenWidth(2);
            dc.setColor(scaleColor(glow, 0.30), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 5);
        }

        // 2. Dark glass sphere base.
        dc.setColor(scaleColor(dark, 0.55), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx, gy, r);

        // 3. Liquid fill
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var fillH = (2.0 * r) * v / 100.0;
            var surfaceY = ((gy + r) - fillH).toNumber();
            var bottomY = gy + r - 1;
            var flatTop = bright;
            var flatBottom = lerpColor(bright, dark, 0.5);
            var step = 2;
            for (var y = surfaceY; y <= bottomY; y += step) {
                var half = chordHalf(r - 1, y - gy);
                if (half < 1) { continue; }
                var depth = (y - surfaceY).toFloat() / fillH;
                var c;
                if (mFlatGlobes) {
                    c = (depth < 0.55) ? flatTop : flatBottom;
                } else {
                    var tt = 1.0 - depth;
                    if (tt < 0.0) { tt = 0.0; }
                    if (tt > 1.0) { tt = 1.0; }
                    c = lerpColor(dark, bright, tt);
                }
                dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(gx - half, y, 2 * half, step);
            }

            // Frozen core glint
            if (fillH > r * 0.5 && !mFlatGlobes) {
                var coreY = (gy + r - fillH * 0.45).toNumber();
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.10), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.22).toNumber());
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.22), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.10).toNumber());
            }

            // Bright meniscus line
            var mHalf = chordHalf(r, surfaceY - gy);
            if (mHalf > 1) {
                dc.setPenWidth(2);
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.35), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - mHalf, surfaceY, gx + mHalf, surfaceY);
            }
        }

        // 4. Specular glass highlight
        if (available) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(gx - (r * 0.34).toNumber(), gy - (r * 0.42).toNumber(), (r * 0.12).toNumber());
        }

        // 5. Bezel
        drawWinterBezel(dc, gx, gy, r, (available && value > 0));
    }

    // Burn-in-safe globe: just a thin dim ring + a thin fluid-level line.
    function drawGlobeLowPower(dc as Dc, gx as Number, gy as Number, r as Number,
                               value as Number, available as Boolean, rim as Number) as Void {
        dc.setPenWidth(1);
        dc.setColor(scaleColor(rim, 0.45), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r);
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var surfaceY = ((gy + r) - (2.0 * r) * v / 100.0).toNumber();
            var half = chordHalf(r, surfaceY - gy);
            if (half > 1) {
                dc.setColor(scaleColor(rim, 0.65), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - half, surfaceY, gx + half, surfaceY);
            }
        }
    }

    // Steps progress bar
    function drawXpBar(dc as Dc, cx as Number, y as Number, barW as Number, barH as Number, frac as Float) as Void {
        var x = cx - barW / 2;
        var top = y - barH / 2;
        var rad = barH / 2;

        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var fw = (barW * frac).toNumber();

        if (mLowPower) {
            dc.setPenWidth(1);
            dc.setColor(scaleColor(C_XP_FILL, 0.40), Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, top, barW, barH, rad);
            if (fw > 2) {
                dc.setColor(scaleColor(C_XP_FILL, 0.55), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x + 2, y, x + fw - 2, y);
            }
            return;
        }

        // Track (dark slate)
        dc.setColor(C_XP_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, top, barW, barH, rad);

        // Fill (ice-blue progress)
        if (frac > 0.0) {
            if (fw < barH) { fw = barH; }
            if (fw > barW) { fw = barW; }
            dc.setColor(C_XP_FILL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top, fw, barH, rad);
        }

        // Frost frame + icy end caps
        dc.setPenWidth(1);
        dc.setColor(C_XP_BORDER, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, top, barW, barH, rad);

        dc.setColor(C_XP_BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 2, y, 3);
        dc.fillCircle(x + barW + 2, y, 3);
    }

    // ------------------------------------------------------------------- Data

    function getStepFraction() as Float {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        if (info == null || info.steps == null) { return 0.0; }
        var steps = info.steps;
        var goal = mStepGoalOverride;
        if (goal <= 0) {
            if (info.stepGoal != null && info.stepGoal > 0) {
                goal = info.stepGoal;
            } else {
                goal = 10000;
            }
        }
        if (goal <= 0) { return 0.0; }
        var f = steps.toFloat() / goal.toFloat();
        if (f > 1.0) { f = 1.0; }
        return f;
    }

    function getBodyBattery() as Number or Null {
        try {
            if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
                var iter = SensorHistory.getBodyBatteryHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST
                });
                if (iter != null) {
                    var sample = iter.next();
                    if (sample != null && sample.data != null) {
                        var v = sample.data.toNumber();
                        if (v < 0) { v = 0; }
                        if (v > 100) { v = 100; }
                        return v;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    // Current heart rate in BPM. The sensor reading is cached and refreshed at
    // most once every ~10 seconds to stay within the watch-face power budget.
    // Returns null when no recent reading is available.
    function getHeartRate() as Number or Null {
        var nowSec = Time.now().value();
        if (mCachedHr != null && (nowSec - mHrLastSec) < 10) {
            return mCachedHr;
        }
        mHrLastSec = nowSec;
        try {
            if (Toybox has :Activity) {
                var info = Activity.getActivityInfo();
                if (info != null && info.currentHeartRate != null) {
                    mCachedHr = info.currentHeartRate;
                    return mCachedHr;
                }
            }
            if ((Toybox has :ActivityMonitor) && (ActivityMonitor has :getHeartRateHistory)) {
                var it = ActivityMonitor.getHeartRateHistory(1, true);
                if (it != null) {
                    var s = it.next();
                    if (s != null && s.heartRate != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                        mCachedHr = s.heartRate;
                        return mCachedHr;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return mCachedHr;
    }

    function getDeviceBattery() as Number {
        var stats = System.getSystemStats();
        return (stats.battery != null) ? stats.battery.toNumber() : 0;
    }

    function getSteps() as Number {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        return (info != null && info.steps != null) ? info.steps : 0;
    }

    function getCalories() as Number {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        return (info != null && info.calories != null) ? info.calories : 0;
    }

    // --------------------------------------------------------- Complications

    // Draw one configurable complication (icon + value) centered on cx.
    private function drawComplication(dc as Dc, cx as Number, y as Number, opt as Number) as Void {
        if (opt == COMP_OFF) { return; }

        var valStr = "--";
        var level = -1;
        var accent = 0xFFFFFF;

        if (opt == COMP_HR) {
            var hr = getHeartRate();
            valStr = (hr != null) ? hr.format("%d") : "--";
            accent = 0x9FE8E0;            // icy mint heart
        } else if (opt == COMP_BODY) {
            var bb = getBodyBattery();
            valStr = (bb != null) ? bb.format("%d") + "%" : "--";
            accent = 0x7FD8C8;            // pale teal bolt
        } else if (opt == COMP_BATTERY) {
            var b = getDeviceBattery();
            valStr = b.format("%d") + "%";
            level = b;
            accent = 0x8FC4FF;            // glacier blue battery
        } else if (opt == COMP_STEPS) {
            valStr = getSteps().format("%d");
            accent = 0xCFE0F0;            // frost boot
        } else if (opt == COMP_CALORIES) {
            valStr = getCalories().format("%d");
            accent = 0xFFB088;            // cold-ember flame
        } else {
            return;
        }

        var textColor = mLowPower ? 0x6E6E6E : 0xFFFFFF;
        var iconColor = mLowPower ? 0x6E6E6E : accent;

        var textWidth = dc.getTextWidthInPixels(valStr, mFontLabel);
        var totalW = 16 + 6 + textWidth;
        var startX = cx - totalW / 2;

        drawComplicationIcon(dc, opt, startX + 8, y, iconColor, level);
        drawTextWithOutline(dc, startX + 22, y, mFontLabel, valStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER, textColor);
    }

    private function drawComplicationIcon(dc as Dc, kind as Number, x as Number, y as Number, color as Number, level as Number) as Void {
        if (kind == COMP_HR) {
            drawHeartIcon(dc, x, y, color);
        } else if (kind == COMP_BODY) {
            drawBoltIcon(dc, x, y, color);
        } else if (kind == COMP_BATTERY) {
            drawBatteryIcon(dc, x, y, color, level);
        } else if (kind == COMP_STEPS) {
            drawBootIcon(dc, x, y, color);
        } else if (kind == COMP_CALORIES) {
            drawFlameIcon(dc, x, y, color);
        }
    }

    // Body Battery -> lightning bolt (energy).
    private function drawBoltIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawBoltShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawBoltShape(dc, x - 1, y - 1);
        drawBoltShape(dc, x + 1, y - 1);
        drawBoltShape(dc, x - 1, y + 1);
        drawBoltShape(dc, x + 1, y + 1);
        drawBoltShape(dc, x - 1, y);
        drawBoltShape(dc, x + 1, y);
        drawBoltShape(dc, x,     y - 1);
        drawBoltShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawBoltShape(dc, x, y);
    }

    private function drawBoltShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([
            [x + 2, y - 8], [x - 5, y + 1], [x - 1, y + 1],
            [x - 2, y + 8], [x + 5, y - 2], [x + 1, y - 2]
        ] as Array<Array>);
    }

    // Steps -> winter boot.
    private function drawBootIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawBootShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawBootShape(dc, x - 1, y - 1);
        drawBootShape(dc, x + 1, y - 1);
        drawBootShape(dc, x - 1, y + 1);
        drawBootShape(dc, x + 1, y + 1);
        drawBootShape(dc, x - 1, y);
        drawBootShape(dc, x + 1, y);
        drawBootShape(dc, x,     y - 1);
        drawBootShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawBootShape(dc, x, y);
    }

    private function drawBootShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillRoundedRectangle(x - 4, y - 7, 6, 10, 2);  // leg
        dc.fillRoundedRectangle(x - 4, y + 1, 11, 4, 2);  // foot
    }

    // Calories -> flame.
    private function drawFlameIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawFlameShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawFlameShape(dc, x - 1, y - 1);
        drawFlameShape(dc, x + 1, y - 1);
        drawFlameShape(dc, x - 1, y + 1);
        drawFlameShape(dc, x + 1, y + 1);
        drawFlameShape(dc, x - 1, y);
        drawFlameShape(dc, x + 1, y);
        drawFlameShape(dc, x,     y - 1);
        drawFlameShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawFlameShape(dc, x, y);
    }

    private function drawFlameShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([
            [x, y - 8], [x + 5, y - 1], [x + 4, y + 4], [x - 4, y + 4], [x - 5, y - 1]
        ] as Array<Array>);
        dc.fillCircle(x, y + 2, 4);
    }

    // -------------------------------------------------------------- Critters
    //
    // Occasional winter visitors that cross the screen once in a while. At most
    // ONE is ever active. Everything is deterministic from the clock (no RNG, no
    // state), so a crossing renders identically each frame within a second, and
    // critters are only drawn in the active layer (never low-power/AOD) so they
    // never touch the partial-update budget. Each creature is outlined by drawing
    // its silhouette 4x at +/-1 diagonal offsets in black, then once in colour,
    // to stay legible over bright snow and dark sky alike.

    // Pick the active critter for this instant, or null. PERIOD = seconds between
    // possible visitors; CROSS = how long one crossing lasts. ~1 in 5 windows is
    // quiet (period % 5 == 0). Returns [type, dir, frac, seed].
    private function computeCritter(hour as Number, min as Number, sec as Number, isNight as Boolean) as Array or Null {
        var PERIOD = 38.0;
        var CROSS  = 8.0;

        var tDay = (hour * 3600 + min * 60 + sec).toFloat();
        var period = (tDay / PERIOD).toNumber();
        var local = tDay - period * PERIOD;

        if (period % 5 == 0) { return null; }   // quiet window
        if (local >= CROSS) { return null; }

        var frac = local / CROSS;               // 0..1 across the screen
        var dir = ((period * 31 + 7) % 2 == 0) ? 1 : -1;
        var sel = (period * 17 + 5) % 4;

        var type;
        if (isNight) {
            var nightPool = [CR_OWL, CR_ARCTIC_FOX, CR_WOLF, CR_STAG] as Array<Number>;
            type = nightPool[sel];
        } else {
            var dayPool = [CR_CARDINAL, CR_HARE, CR_FOX, CR_CHICKADEE] as Array<Number>;
            type = dayPool[sel];
        }
        return [type, dir, frac, period] as Array;
    }

    // Sky critters (cardinal, owl) draw up in the sky pass; everything else walks
    // on the snow and draws after the snowbank.
    private function isSkyCritter(type as Number) as Boolean {
        return type == CR_CARDINAL || type == CR_OWL;
    }

    // Position the active critter for its type and dispatch to its drawer.
    private function drawCritter(dc as Dc, crit as Array) as Void {
        var w = mWidth;
        var h = mHeight;
        var type = crit[0] as Number;
        var dir = crit[1] as Number;
        var frac = crit[2] as Float;

        var margin = (w * 0.18).toNumber();
        var span = w + 2 * margin;
        var x;
        if (dir == 1) {
            x = (-margin + frac * span).toNumber();
        } else {
            x = (w + margin - frac * span).toNumber();
        }

        if (type == CR_CARDINAL) {
            var y = (h * 0.22).toNumber() + (h * 0.04 * Math.sin(frac * Math.PI * 2.0)).toNumber();
            drawCardinal(dc, x, y, dir, Math.sin(frac * Math.PI * 9.0), (w * 0.045).toNumber());
        } else if (type == CR_OWL) {
            var y = (h * 0.20).toNumber() + (h * 0.03 * Math.sin(frac * Math.PI * 2.0)).toNumber();
            drawOwl(dc, x, y, dir, Math.sin(frac * Math.PI * 4.0), (w * 0.06).toNumber());
        } else if (type == CR_HARE) {
            var groundY = (h * 0.93).toNumber();
            var sv = Math.sin(frac * Math.PI * 7.0);
            if (sv < 0.0) { sv = -sv; }            // bounding hops
            var y = (groundY - (h * 0.05) * sv).toNumber();
            drawHare(dc, x, y, dir, (w * 0.045).toNumber());
        } else if (type == CR_FOX) {
            var groundY = (h * 0.93).toNumber();
            var y = groundY;
            var pounce = false;
            if (frac > 0.4 && frac < 0.6) {        // mid-screen snow-pounce
                var pf = (frac - 0.4) / 0.2;
                y = (groundY - (h * 0.07) * Math.sin(pf * Math.PI)).toNumber();
                pounce = true;
            }
            drawFoxFamily(dc, x, y, dir, pounce, (w * 0.05).toNumber(), 0xE0662A, 0xF4ECE0, 0x2A1A12);
        } else if (type == CR_ARCTIC_FOX) {
            var groundY = (h * 0.93).toNumber();
            drawFoxFamily(dc, x, groundY, dir, false, (w * 0.05).toNumber(), 0xEAF2FA, 0xFFFFFF, 0x9FB2C4);
        } else if (type == CR_CHICKADEE) {
            // sky -> snow -> sky: glide down, hop & peck, then flit off.
            var skyY = (h * 0.34).toNumber();
            var groundY = (h * 0.90).toNumber();
            var onGround = false;
            var y;
            if (frac < 0.35) {
                y = (skyY + (groundY - skyY) * (frac / 0.35)).toNumber();
            } else if (frac < 0.65) {
                y = groundY;
                onGround = true;
            } else {
                y = (groundY + (skyY - groundY) * ((frac - 0.65) / 0.35)).toNumber();
            }
            drawChickadee(dc, x, y, dir, frac, onGround, (w * 0.035).toNumber());
        } else if (type == CR_WOLF) {
            var groundY = (h * 0.93).toNumber();
            var howl = (frac > 0.45 && frac < 0.62);
            if (howl) {                            // pause mid-crossing to howl
                var pf = 0.45;
                x = (dir == 1) ? (-margin + pf * span).toNumber() : (w + margin - pf * span).toNumber();
            }
            drawWolf(dc, x, groundY, dir, howl, (w * 0.055).toNumber());
        } else if (type == CR_STAG) {
            var groundY = (h * 0.93).toNumber();
            drawStag(dc, x, groundY, dir, frac, (w * 0.06).toNumber());
        }
    }

    // ---- Cardinal (red songbird, flying) ----
    private function drawCardinal(dc as Dc, x as Number, y as Number, dir as Number, flap as Float, s as Number) as Void {
        if (s < 8) { s = 8; }
        cardinalSil(dc, x - 1, y - 1, dir, s, flap, 0x000000);
        cardinalSil(dc, x + 1, y - 1, dir, s, flap, 0x000000);
        cardinalSil(dc, x - 1, y + 1, dir, s, flap, 0x000000);
        cardinalSil(dc, x + 1, y + 1, dir, s, flap, 0x000000);
        cardinalSil(dc, x, y, dir, s, flap, 0xD4262A);   // crimson

        var hx = (x + dir * s * 0.55).toNumber();
        var hy = (y - s * 0.35).toNumber();
        dc.setColor(0x1A1010, Graphics.COLOR_TRANSPARENT);   // black face mask
        dc.fillCircle((hx + dir * s * 0.1).toNumber(), (hy + s * 0.2).toNumber(), (s * 0.18).toNumber());
        dc.setColor(0xF2A03A, Graphics.COLOR_TRANSPARENT);   // orange beak
        dc.fillPolygon([
            [(hx + dir * s * 0.3).toNumber(), (hy + s * 0.05).toNumber()],
            [(hx + dir * s * 0.7).toNumber(), (hy + s * 0.2).toNumber()],
            [(hx + dir * s * 0.3).toNumber(), (hy + s * 0.3).toNumber()]
        ] as Array<Array>);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(hx, (hy + s * 0.02).toNumber(), 1);    // eye glint
    }

    private function cardinalSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, flap as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, (s * 0.5).toNumber());           // body
        var hx = (x + dir * s * 0.55).toNumber();
        var hy = (y - s * 0.35).toNumber();
        dc.fillCircle(hx, hy, (s * 0.32).toNumber());        // head
        dc.fillPolygon([                                     // crest spike
            [(hx - dir * s * 0.1).toNumber(), (hy - s * 0.2).toNumber()],
            [(hx - dir * s * 0.4).toNumber(), (hy - s * 0.75).toNumber()],
            [(hx + dir * s * 0.15).toNumber(), (hy - s * 0.3).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([                                     // tail
            [(x - dir * s * 0.4).toNumber(), (y - s * 0.1).toNumber()],
            [(x - dir * s * 1.3).toNumber(), (y + s * 0.2).toNumber()],
            [(x - dir * s * 0.4).toNumber(), (y + s * 0.35).toNumber()]
        ] as Array<Array>);
        var wTipY = (y - flap * s * 0.7).toNumber();         // wing (flaps)
        dc.fillPolygon([
            [x, (y - s * 0.1).toNumber()],
            [(x - dir * s * 0.2).toNumber(), wTipY],
            [(x + dir * s * 0.45).toNumber(), (y + s * 0.1).toNumber()]
        ] as Array<Array>);
    }

    // ---- Snowy owl (glides across the night sky) ----
    private function drawOwl(dc as Dc, x as Number, y as Number, dir as Number, flap as Float, s as Number) as Void {
        if (s < 9) { s = 9; }
        owlSil(dc, x - 1, y - 1, dir, s, flap, 0x000000);
        owlSil(dc, x + 1, y - 1, dir, s, flap, 0x000000);
        owlSil(dc, x - 1, y + 1, dir, s, flap, 0x000000);
        owlSil(dc, x + 1, y + 1, dir, s, flap, 0x000000);
        owlSil(dc, x, y, dir, s, flap, 0xF0F4FA);            // pale snowy white

        dc.setColor(0xB8C2CE, Graphics.COLOR_TRANSPARENT);   // a few grey speckles
        dc.fillCircle((x - s * 0.2).toNumber(), (y + s * 0.1).toNumber(), 1);
        dc.fillCircle((x + s * 0.2).toNumber(), (y + s * 0.3).toNumber(), 1);
        dc.fillCircle(x, (y - s * 0.1).toNumber(), 1);

        var hy = (y - s * 0.7).toNumber();
        dc.setColor(0xF2C03A, Graphics.COLOR_TRANSPARENT);   // big yellow eyes
        dc.fillCircle((x - s * 0.22).toNumber(), hy, (s * 0.14).toNumber());
        dc.fillCircle((x + s * 0.22).toNumber(), hy, (s * 0.14).toNumber());
        dc.setColor(0x1A1410, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - s * 0.22).toNumber(), hy, (s * 0.06).toNumber() + 1);
        dc.fillCircle((x + s * 0.22).toNumber(), hy, (s * 0.06).toNumber() + 1);
        dc.setColor(0xF2A03A, Graphics.COLOR_TRANSPARENT);   // beak
        dc.fillPolygon([
            [x, (hy + s * 0.12).toNumber()],
            [(x - s * 0.08).toNumber(), (hy + s * 0.32).toNumber()],
            [(x + s * 0.08).toNumber(), (hy + s * 0.32).toNumber()]
        ] as Array<Array>);
    }

    private function owlSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, flap as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.5).toNumber(), (y - s * 0.4).toNumber(), (s * 1.0).toNumber(), (s * 1.1).toNumber(), (s * 0.4).toNumber());  // body
        dc.fillCircle(x, (y - s * 0.7).toNumber(), (s * 0.55).toNumber());   // big round head
        var tip = (flap * s * 0.5);                          // broad wings, tips dip slowly
        dc.fillPolygon([
            [x, (y - s * 0.2).toNumber()],
            [(x - s * 1.4).toNumber(), (y - s * 0.1 + tip).toNumber()],
            [(x - s * 0.3).toNumber(), (y + s * 0.4).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [x, (y - s * 0.2).toNumber()],
            [(x + s * 1.4).toNumber(), (y - s * 0.1 + tip).toNumber()],
            [(x + s * 0.3).toNumber(), (y + s * 0.4).toNumber()]
        ] as Array<Array>);
    }

    // ---- Snowshoe hare (bounds across the snow) ----
    private function drawHare(dc as Dc, x as Number, y as Number, dir as Number, s as Number) as Void {
        if (s < 8) { s = 8; }
        hareSil(dc, x - 1, y - 1, dir, s, 0x000000);
        hareSil(dc, x + 1, y - 1, dir, s, 0x000000);
        hareSil(dc, x - 1, y + 1, dir, s, 0x000000);
        hareSil(dc, x + 1, y + 1, dir, s, 0x000000);
        hareSil(dc, x, y, dir, s, 0xF4FAFF);                 // winter-white coat

        var hx = (x + dir * s * 0.7).toNumber();
        var hy = (y - s * 0.3).toNumber();
        dc.setColor(0x2A2A30, Graphics.COLOR_TRANSPARENT);   // eye
        dc.fillCircle(hx, hy, 1);
        dc.setColor(0xE6849A, Graphics.COLOR_TRANSPARENT);   // nose
        dc.fillCircle((hx + dir * s * 0.3).toNumber(), (hy + s * 0.15).toNumber(), 1);
    }

    private function hareSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.8).toNumber(), (y - s * 0.5).toNumber(), (s * 1.5).toNumber(), (s * 0.8).toNumber(), (s * 0.4).toNumber());  // body
        dc.fillCircle((x - dir * s * 0.5).toNumber(), (y - s * 0.1).toNumber(), (s * 0.45).toNumber());   // haunch
        dc.fillCircle((x + dir * s * 0.7).toNumber(), (y - s * 0.3).toNumber(), (s * 0.35).toNumber());   // head
        var ex = (x + dir * s * 0.6).toNumber();             // two long ears
        var ey = (y - s * 0.55).toNumber();
        dc.fillRoundedRectangle((ex - dir * s * 0.1).toNumber(), (ey - s * 0.7).toNumber(), (s * 0.18).toNumber(), (s * 0.8).toNumber(), (s * 0.09).toNumber());
        dc.fillRoundedRectangle((ex - dir * s * 0.35).toNumber(), (ey - s * 0.65).toNumber(), (s * 0.18).toNumber(), (s * 0.8).toNumber(), (s * 0.09).toNumber());
        dc.fillRoundedRectangle((x + dir * s * 0.3).toNumber(), (y + s * 0.15).toNumber(), (s * 0.5).toNumber(), (s * 0.2).toNumber(), (s * 0.1).toNumber());   // tucked feet
        dc.fillCircle((x - dir * s * 0.95).toNumber(), (y - s * 0.05).toNumber(), (s * 0.2).toNumber());  // tail puff
    }

    // ---- Fox (red fox by day, arctic fox by night); palette-driven ----
    private function drawFoxFamily(dc as Dc, x as Number, y as Number, dir as Number, pounce as Boolean, s as Number, body as Number, belly as Number, sock as Number) as Void {
        if (s < 8) { s = 8; }
        foxSil(dc, x - 1, y - 1, dir, s, pounce, 0x000000);
        foxSil(dc, x + 1, y - 1, dir, s, pounce, 0x000000);
        foxSil(dc, x - 1, y + 1, dir, s, pounce, 0x000000);
        foxSil(dc, x + 1, y + 1, dir, s, pounce, 0x000000);
        foxSil(dc, x, y, dir, s, pounce, body);

        dc.setColor(belly, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 0.95).toNumber(), (y - s * 0.1).toNumber(), (s * 0.2).toNumber());   // cheek/chest
        dc.fillCircle((x - dir * s * 1.5).toNumber(), (y - s * 0.45).toNumber(), (s * 0.22).toNumber());  // white tail tip
        dc.setColor(sock, Graphics.COLOR_TRANSPARENT);
        var hx = (x + dir * s * 1.2).toNumber();
        var hy = (y - s * 0.25).toNumber();
        dc.fillCircle((hx + dir * s * 0.1).toNumber(), (hy + s * 0.12).toNumber(), 1);   // nose
        dc.fillCircle((hx - dir * s * 0.2).toNumber(), (hy - s * 0.05).toNumber(), 1);   // eye
    }

    private function foxSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, pounce as Boolean, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.9).toNumber(), (y - s * 0.35).toNumber(), (s * 1.9).toNumber(), (s * 0.7).toNumber(), (s * 0.3).toNumber());  // body
        dc.setPenWidth((s > 12) ? 3 : 2);                    // legs (tucked during a pounce)
        var legLen = pounce ? 0.35 : 0.6;
        var legY2 = (y + s * legLen).toNumber();
        dc.drawLine((x + dir * s * 0.65).toNumber(), (y + s * 0.2).toNumber(), (x + dir * s * 0.65).toNumber(), legY2);
        dc.drawLine((x + dir * s * 0.2).toNumber(),  (y + s * 0.2).toNumber(), (x + dir * s * 0.2).toNumber(),  legY2);
        dc.drawLine((x - dir * s * 0.2).toNumber(),  (y + s * 0.2).toNumber(), (x - dir * s * 0.2).toNumber(),  legY2);
        dc.drawLine((x - dir * s * 0.65).toNumber(), (y + s * 0.2).toNumber(), (x - dir * s * 0.65).toNumber(), legY2);
        dc.setPenWidth(1);
        dc.fillPolygon([                                     // neck + head (snout)
            [(x + dir * s * 0.6).toNumber(),  (y - s * 0.3).toNumber()],
            [(x + dir * s * 1.35).toNumber(), (y - s * 0.35).toNumber()],
            [(x + dir * s * 1.25).toNumber(), (y).toNumber()],
            [(x + dir * s * 0.6).toNumber(),  (y + s * 0.1).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([                                     // ears
            [(x + dir * s * 0.75).toNumber(), (y - s * 0.3).toNumber()],
            [(x + dir * s * 0.7).toNumber(),  (y - s * 0.8).toNumber()],
            [(x + dir * s * 1.0).toNumber(),  (y - s * 0.35).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [(x + dir * s * 1.0).toNumber(),  (y - s * 0.3).toNumber()],
            [(x + dir * s * 1.05).toNumber(), (y - s * 0.8).toNumber()],
            [(x + dir * s * 1.25).toNumber(), (y - s * 0.35).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([                                     // bushy tail
            [(x - dir * s * 0.7).toNumber(), (y - s * 0.2).toNumber()],
            [(x - dir * s * 1.7).toNumber(), (y - s * 0.6).toNumber()],
            [(x - dir * s * 1.5).toNumber(), (y + s * 0.1).toNumber()],
            [(x - dir * s * 0.7).toNumber(), (y + s * 0.2).toNumber()]
        ] as Array<Array>);
    }

    // ---- Chickadee (flies in, lands and pecks, flits off) ----
    private function drawChickadee(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, onGround as Boolean, s as Number) as Void {
        if (s < 7) { s = 7; }
        var peck = 0.0;
        var flap = 0.0;
        if (onGround) {
            peck = Math.sin(frac * Math.PI * 16.0) * s * 0.2;   // head bobs to peck
        } else {
            flap = Math.sin(frac * Math.PI * 11.0);
        }
        var flying = !onGround;
        chickadeeSil(dc, x - 1, y - 1, dir, s, flap, peck, flying, 0x000000);
        chickadeeSil(dc, x + 1, y - 1, dir, s, flap, peck, flying, 0x000000);
        chickadeeSil(dc, x - 1, y + 1, dir, s, flap, peck, flying, 0x000000);
        chickadeeSil(dc, x + 1, y + 1, dir, s, flap, peck, flying, 0x000000);
        chickadeeSil(dc, x, y, dir, s, flap, peck, flying, 0xC8C0B0);   // buff-grey body

        var hx = (x + dir * s * 0.55).toNumber();
        var hy = (y - s * 0.35 + peck).toNumber();
        dc.setColor(0x1A1A1E, Graphics.COLOR_TRANSPARENT);   // black cap
        dc.fillCircle(hx, (hy - s * 0.15).toNumber(), (s * 0.28).toNumber());
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);   // white cheek
        dc.fillCircle((hx + dir * s * 0.05).toNumber(), (hy + s * 0.12).toNumber(), (s * 0.16).toNumber());
        dc.setColor(0x2A2A2E, Graphics.COLOR_TRANSPARENT);   // beak
        dc.fillPolygon([
            [(hx + dir * s * 0.25).toNumber(), (hy).toNumber()],
            [(hx + dir * s * 0.6).toNumber(),  (hy + s * 0.08).toNumber()],
            [(hx + dir * s * 0.25).toNumber(), (hy + s * 0.16).toNumber()]
        ] as Array<Array>);
    }

    private function chickadeeSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, flap as Float, peck as Float, flying as Boolean, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, (s * 0.5).toNumber());           // plump body
        dc.fillCircle((x + dir * s * 0.55).toNumber(), (y - s * 0.35 + peck).toNumber(), (s * 0.32).toNumber());  // head
        dc.fillPolygon([                                     // tail
            [(x - dir * s * 0.3).toNumber(), (y - s * 0.1).toNumber()],
            [(x - dir * s * 1.1).toNumber(), (y + s * 0.05).toNumber()],
            [(x - dir * s * 0.3).toNumber(), (y + s * 0.3).toNumber()]
        ] as Array<Array>);
        if (flying) {                                        // wing flaps in flight
            var wTipY = (y - flap * s * 0.6).toNumber();
            dc.fillPolygon([
                [x, (y - s * 0.1).toNumber()],
                [(x - dir * s * 0.1).toNumber(), wTipY],
                [(x + dir * s * 0.4).toNumber(), (y + s * 0.1).toNumber()]
            ] as Array<Array>);
        } else {                                             // folded on the ground
            dc.fillRoundedRectangle((x - s * 0.3).toNumber(), (y - s * 0.15).toNumber(), (s * 0.6).toNumber(), (s * 0.3).toNumber(), (s * 0.15).toNumber());
        }
    }

    // ---- Grey wolf (trots, then pauses mid-crossing to howl) ----
    private function drawWolf(dc as Dc, x as Number, y as Number, dir as Number, howl as Boolean, s as Number) as Void {
        if (s < 10) { s = 10; }
        wolfSil(dc, x - 1, y - 1, dir, s, howl, 0x000000);
        wolfSil(dc, x + 1, y - 1, dir, s, howl, 0x000000);
        wolfSil(dc, x - 1, y + 1, dir, s, howl, 0x000000);
        wolfSil(dc, x + 1, y + 1, dir, s, howl, 0x000000);
        wolfSil(dc, x, y, dir, s, howl, 0x8A8F99);           // grey coat

        dc.setColor(0xC2C6CE, Graphics.COLOR_TRANSPARENT);   // lighter muzzle
        if (howl) {
            dc.fillCircle((x + dir * s * 1.0).toNumber(), (y - s * 1.05).toNumber(), (s * 0.14).toNumber());
        } else {
            dc.fillCircle((x + dir * s * 1.3).toNumber(), (y - s * 0.15).toNumber(), (s * 0.14).toNumber());
        }
    }

    private function wolfSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, howl as Boolean, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.95).toNumber(), (y - s * 0.35).toNumber(), (s * 1.9).toNumber(), (s * 0.7).toNumber(), (s * 0.3).toNumber());  // body
        dc.setPenWidth((s > 12) ? 3 : 2);                    // legs
        var legY2 = (y + s * 0.65).toNumber();
        dc.drawLine((x + dir * s * 0.7).toNumber(),  (y + s * 0.2).toNumber(), (x + dir * s * 0.7).toNumber(),  legY2);
        dc.drawLine((x + dir * s * 0.25).toNumber(), (y + s * 0.2).toNumber(), (x + dir * s * 0.25).toNumber(), legY2);
        dc.drawLine((x - dir * s * 0.25).toNumber(), (y + s * 0.2).toNumber(), (x - dir * s * 0.25).toNumber(), legY2);
        dc.drawLine((x - dir * s * 0.7).toNumber(),  (y + s * 0.2).toNumber(), (x - dir * s * 0.7).toNumber(),  legY2);
        dc.setPenWidth(1);
        dc.fillPolygon([                                     // bushy tail (low)
            [(x - dir * s * 0.8).toNumber(), (y - s * 0.2).toNumber()],
            [(x - dir * s * 1.7).toNumber(), (y + s * 0.05).toNumber()],
            [(x - dir * s * 0.8).toNumber(), (y + s * 0.2).toNumber()]
        ] as Array<Array>);
        if (howl) {                                          // head raised, muzzle to the sky
            dc.fillPolygon([
                [(x + dir * s * 0.6).toNumber(),  (y - s * 0.3).toNumber()],
                [(x + dir * s * 0.85).toNumber(), (y - s * 1.1).toNumber()],
                [(x + dir * s * 1.2).toNumber(),  (y - s * 1.05).toNumber()],
                [(x + dir * s * 0.95).toNumber(), (y - s * 0.2).toNumber()]
            ] as Array<Array>);
            dc.fillCircle((x + dir * s * 1.0).toNumber(), (y - s * 1.05).toNumber(), (s * 0.25).toNumber());
            dc.fillPolygon([                                 // ear back
                [(x + dir * s * 0.85).toNumber(), (y - s * 1.0).toNumber()],
                [(x + dir * s * 0.7).toNumber(),  (y - s * 1.4).toNumber()],
                [(x + dir * s * 1.0).toNumber(),  (y - s * 1.1).toNumber()]
            ] as Array<Array>);
        } else {                                             // head forward, lowered
            dc.fillPolygon([
                [(x + dir * s * 0.6).toNumber(),  (y - s * 0.3).toNumber()],
                [(x + dir * s * 1.4).toNumber(),  (y - s * 0.4).toNumber()],
                [(x + dir * s * 1.35).toNumber(), (y + s * 0.05).toNumber()],
                [(x + dir * s * 0.6).toNumber(),  (y + s * 0.05).toNumber()]
            ] as Array<Array>);
            dc.fillCircle((x + dir * s * 1.3).toNumber(), (y - s * 0.2).toNumber(), (s * 0.28).toNumber());
            dc.fillPolygon([                                 // ear
                [(x + dir * s * 1.15).toNumber(), (y - s * 0.4).toNumber()],
                [(x + dir * s * 1.1).toNumber(),  (y - s * 0.8).toNumber()],
                [(x + dir * s * 1.35).toNumber(), (y - s * 0.45).toNumber()]
            ] as Array<Array>);
        }
    }

    // ---- Stag (antlered deer; walks across, breath steaming) ----
    private function drawStag(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 10) { s = 10; }
        stagSil(dc, x - 1, y - 1, dir, s, 0x000000);
        stagSil(dc, x + 1, y - 1, dir, s, 0x000000);
        stagSil(dc, x - 1, y + 1, dir, s, 0x000000);
        stagSil(dc, x + 1, y + 1, dir, s, 0x000000);
        stagSil(dc, x, y, dir, s, 0x6B4A2E);                 // brown coat

        dc.setColor(0xD8C4A8, Graphics.COLOR_TRANSPARENT);   // pale rump
        dc.fillCircle((x - dir * s * 0.8).toNumber(), (y - s * 0.05).toNumber(), (s * 0.18).toNumber());

        var bx = (x + dir * s * 1.5).toNumber();             // breath steam puffs
        var by = (y - s * 1.0).toNumber();
        dc.setColor(0xDCEAF8, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 3; i++) {
            var drift = ((frac * 30.0).toNumber() + i) % 4;
            dc.fillCircle((bx + dir * (i * s * 0.25)).toNumber(), (by - i * s * 0.12 - drift).toNumber(), (s * 0.1).toNumber());
        }
    }

    private function stagSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.85).toNumber(), (y - s * 0.4).toNumber(), (s * 1.7).toNumber(), (s * 0.7).toNumber(), (s * 0.25).toNumber());  // body
        dc.setPenWidth((s > 12) ? 3 : 2);                    // long slender legs
        var legY2 = (y + s * 0.85).toNumber();
        dc.drawLine((x + dir * s * 0.6).toNumber(),  (y + s * 0.2).toNumber(), (x + dir * s * 0.6).toNumber(),  legY2);
        dc.drawLine((x + dir * s * 0.25).toNumber(), (y + s * 0.2).toNumber(), (x + dir * s * 0.25).toNumber(), legY2);
        dc.drawLine((x - dir * s * 0.25).toNumber(), (y + s * 0.2).toNumber(), (x - dir * s * 0.25).toNumber(), legY2);
        dc.drawLine((x - dir * s * 0.6).toNumber(),  (y + s * 0.2).toNumber(), (x - dir * s * 0.6).toNumber(),  legY2);
        dc.setPenWidth(1);
        dc.fillPolygon([                                     // neck (up-forward)
            [(x + dir * s * 0.55).toNumber(), (y - s * 0.35).toNumber()],
            [(x + dir * s * 1.1).toNumber(),  (y - s * 1.0).toNumber()],
            [(x + dir * s * 1.35).toNumber(), (y - s * 0.9).toNumber()],
            [(x + dir * s * 0.85).toNumber(), (y - s * 0.2).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([                                     // head/muzzle
            [(x + dir * s * 1.1).toNumber(),  (y - s * 1.05).toNumber()],
            [(x + dir * s * 1.7).toNumber(),  (y - s * 0.95).toNumber()],
            [(x + dir * s * 1.35).toNumber(), (y - s * 0.75).toNumber()]
        ] as Array<Array>);
        dc.setPenWidth((s > 12) ? 3 : 2);                    // branching antlers
        var ax = (x + dir * s * 1.15).toNumber();
        var ay = (y - s * 1.05).toNumber();
        dc.drawLine(ax, ay, (ax - dir * s * 0.1).toNumber(), (ay - s * 0.8).toNumber());
        dc.drawLine((ax - dir * s * 0.1).toNumber(), (ay - s * 0.4).toNumber(), (ax + dir * s * 0.3).toNumber(), (ay - s * 0.6).toNumber());
        dc.drawLine((ax - dir * s * 0.1).toNumber(), (ay - s * 0.8).toNumber(), (ax + dir * s * 0.25).toNumber(), (ay - s * 1.0).toNumber());
        dc.drawLine((ax + dir * s * 0.2).toNumber(), ay, (ax + dir * s * 0.35).toNumber(), (ay - s * 0.7).toNumber());
        dc.drawLine((ax + dir * s * 0.35).toNumber(), (ay - s * 0.35).toNumber(), (ax + dir * s * 0.7).toNumber(), (ay - s * 0.5).toNumber());
        dc.setPenWidth(1);
        dc.fillPolygon([                                     // short tail
            [(x - dir * s * 0.8).toNumber(),  (y - s * 0.3).toNumber()],
            [(x - dir * s * 1.05).toNumber(), (y - s * 0.1).toNumber()],
            [(x - dir * s * 0.8).toNumber(),  (y + s * 0.05).toNumber()]
        ] as Array<Array>);
    }

    // ----------------------------------------------------------- Sun times

    // Recompute today's local sunrise/sunset from the watch's last-known
    // location. Cached per day; keeps the fixed winter fallback until a real
    // location fix is available, then stops recomputing for the day.
    private function updateSunTimes() as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var doy = dayOfYear(info.year, info.month, info.day);
        if (doy == mSunDay && mSunValid) { return; }
        if (doy != mSunDay) {
            mSunDay = doy;
            mSunrise = 7.5;
            mSunset = 16.5;
            mSunValid = false;
            mSunLastTry = -10000;   // retry immediately on the first frame of a new day
        }
        // Until we have a valid fix, throttle the (heavy) location + NOAA trig
        // retries to once per 60 s instead of re-running them every frame. (Fix #7)
        var nowSec = Time.now().value();
        if ((nowSec - mSunLastTry) < 60) { return; }
        mSunLastTry = nowSec;
        var loc = getLocationDeg();
        if (loc == null) { return; }
        var offset = System.getClockTime().timeZoneOffset.toFloat() / 3600.0;
        var sr = computeSunEvent(doy, loc[0], loc[1], offset, true);
        var ss = computeSunEvent(doy, loc[0], loc[1], offset, false);
        if (sr != null && ss != null && ss > sr) {
            mSunrise = sr;
            mSunset = ss;
            mSunValid = true;
        }
    }

    // Last-known location in degrees [lat, lon], or null. Prefers the activity
    // location, then the weather observation location - neither powers the GPS.
    private function getLocationDeg() as Array<Float> or Null {
        try {
            if (Toybox has :Activity) {
                var ai = Activity.getActivityInfo();
                if (ai != null && ai.currentLocation != null) {
                    var d = ai.currentLocation.toDegrees();
                    return [d[0].toFloat(), d[1].toFloat()];
                }
            }
        } catch (e) {
        }
        try {
            if (Toybox has :Weather) {
                var cc = Weather.getCurrentConditions();
                if (cc != null && cc.observationLocationPosition != null) {
                    var d = cc.observationLocationPosition.toDegrees();
                    return [d[0].toFloat(), d[1].toFloat()];
                }
            }
        } catch (e) {
        }
        return null;
    }

    // Standard sunrise/sunset algorithm (NOAA / Almanac). Returns local time in
    // hours (0-24) for the event, or null at extreme latitudes where the sun
    // does not rise/set on the given day.
    private function computeSunEvent(n as Number, lat as Float, lng as Float, offset as Float, sunrise as Boolean) as Float or Null {
        var ZENITH = 90.833;
        var D2R = Math.PI / 180.0;
        var R2D = 180.0 / Math.PI;

        var lngHour = lng / 15.0;
        var tt = sunrise ? (n + ((6.0 - lngHour) / 24.0)) : (n + ((18.0 - lngHour) / 24.0));

        var m = (0.9856 * tt) - 3.289;
        var l = m + (1.916 * Math.sin(m * D2R)) + (0.020 * Math.sin(2.0 * m * D2R)) + 282.634;
        l = normDeg(l);

        var ra = Math.atan(0.91764 * Math.tan(l * D2R)) * R2D;
        ra = normDeg(ra);
        var lQuad = (Math.floor(l / 90.0) * 90.0).toFloat();
        var raQuad = (Math.floor(ra / 90.0) * 90.0).toFloat();
        ra = ra + (lQuad - raQuad);
        ra = ra / 15.0;

        var sinDec = 0.39782 * Math.sin(l * D2R);
        var cosDec = Math.cos(Math.asin(sinDec));

        var cosH = (Math.cos(ZENITH * D2R) - (sinDec * Math.sin(lat * D2R))) / (cosDec * Math.cos(lat * D2R));
        if (cosH > 1.0 || cosH < -1.0) { return null; }

        var bigH = sunrise ? (360.0 - (Math.acos(cosH) * R2D)) : (Math.acos(cosH) * R2D);
        bigH = bigH / 15.0;

        var bigT = bigH + ra - (0.06571 * tt) - 6.622;
        var ut = normHour(bigT - lngHour);
        return normHour(ut + offset);
    }

    private function dayOfYear(year as Number, month as Number, day as Number) as Number {
        var cum = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334] as Array<Number>;
        var n = cum[month - 1] + day;
        if (month > 2 && isLeapYear(year)) { n += 1; }
        return n;
    }

    private function isLeapYear(y as Number) as Boolean {
        return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    }

    // Bounded modulo normalizers with a non-finite guard, so a stray NaN/Infinity
    // from the sun trig can never spin a subtract-in-a-loop forever (hard freeze).
    private function normDeg(a as Float) as Float {
        if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }  // guard NaN / Infinity
        var r = a - 360.0 * Math.floor(a / 360.0);
        if (r < 0.0) { r += 360.0; }
        if (r >= 360.0) { r -= 360.0; }
        return r;
    }

    private function normHour(a as Float) as Float {
        if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }  // guard NaN / Infinity
        var r = a - 24.0 * Math.floor(a / 24.0);
        if (r < 0.0) { r += 24.0; }
        if (r >= 24.0) { r -= 24.0; }
        return r;
    }

    // ------------------------------------------------------------ Color helpers

    function chordHalf(r as Number, dy as Number) as Number {
        var d = r * r - dy * dy;
        if (d <= 0) { return 0; }
        return Math.sqrt(d).toNumber();
    }

    function lerpColor(c1 as Number, c2 as Number, t as Float) as Number {
        if (t < 0.0) { t = 0.0; }
        if (t > 1.0) { t = 1.0; }
        var r1 = (c1 >> 16) & 0xFF;
        var g1 = (c1 >> 8) & 0xFF;
        var b1 = c1 & 0xFF;
        var r2 = (c2 >> 16) & 0xFF;
        var g2 = (c2 >> 8) & 0xFF;
        var b2 = c2 & 0xFF;
        var r = (r1 + ((r2 - r1) * t)).toNumber();
        var g = (g1 + ((g2 - g1) * t)).toNumber();
        var b = (b1 + ((b2 - b1) * t)).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    function scaleColor(c as Number, f as Float) as Number {
        return lerpColor(0x000000, c, f);
    }

    // Smoothly calculate winter sky colors based on hour of day.
    // Shorter days, colder hues: deep indigo night, cold rose dawn, pale blue
    // daylight, a brief cold-peach sunset, and twilight purple.
    private function getSkyColors(hour as Number, min as Number) as Array<Number> {
        var t = hour.toFloat() + min.toFloat() / 60.0;

        var sr = mSunrise;
        var ss = mSunset;
        var hours;
        var topColors;
        var bottomColors;

        // When the day is "normal", anchor the gradient keyframes to the real
        // sunrise/sunset so dawn glow, daylight, and the cold-peach sunset land
        // at the true times. Otherwise fall back to the fixed winter schedule.
        if (sr > 1.6 && ss < 22.4 && (ss - sr) > 4.0) {
            // Only the keyframe HOURS depend on the real sun times, so just this
            // array is built per frame; the color tables are hoisted consts.
            var mid = (sr + ss) / 2.0;
            hours        = [0.0, sr - 1.5, sr, sr + 1.5, mid, ss - 1.5, ss, ss + 1.5, 24.0];
            topColors    = SKY_TOP_REAL;
            bottomColors = SKY_BOTTOM_REAL;
        } else {
            hours        = SKY_HOURS_FB;
            topColors    = SKY_TOP_FB;
            bottomColors = SKY_BOTTOM_FB;
        }

        var idx = 0;
        for (var i = 0; i < hours.size() - 1; i++) {
            if (t >= hours[i] && t < hours[i+1]) {
                idx = i;
                break;
            }
        }

        var frac = (t - hours[idx]) / (hours[idx+1] - hours[idx]);
        var cTop = lerpColor(topColors[idx], topColors[idx+1], frac);
        var cBottom = lerpColor(bottomColors[idx], bottomColors[idx+1], frac);

        return [cTop, cBottom] as Array<Number>;
    }

    // Render the AMOLED sky gradient into a reusable BufferedBitmap and return it,
    // or null if buffers aren't supported / allocation failed (caller renders
    // directly). Allocated ONCE; only repainted in place when the gradient colors
    // change, so the per-row fill loop runs ~once/minute and we never churn the
    // graphics pool by recreating the buffer. (Fix #9 / #12)
    private function getSkyBitmap(w as Number, skyH as Number, cTop as Number, cBottom as Number) as Graphics.BufferedBitmap or Null {
        if (!(Graphics has :createBufferedBitmap)) { return null; }
        var bmp = (mSkyBufRef != null) ? mSkyBufRef.get() : null;  // null if pool reclaimed it
        if (bmp == null || w != mSkyKeyW || skyH != mSkyKeyH) {    // allocate ONCE (or after reclaim/resize)
            try {
                var ref = Graphics.createBufferedBitmap({ :width => w, :height => skyH });
                if (ref == null) { return null; }
                mSkyBufRef = ref;
                bmp = ref.get();
                if (bmp == null) { return null; }
            } catch (e) {
                mSkyBufRef = null;
                return null;
            }
            mSkyKeyW = w;
            mSkyKeyH = skyH;
            mSkyKeyTop = cTop + 1;   // invalidate so the fill below runs
        }
        if (cTop != mSkyKeyTop || cBottom != mSkyKeyBottom) {      // repaint IN PLACE
            drawSkyGradientDirect(bmp.getDc(), w, skyH, cTop, cBottom);
            mSkyKeyTop = cTop;
            mSkyKeyBottom = cBottom;
        }
        return bmp;
    }

    private function drawSkyGradientDirect(dc as Dc, w as Number, skyH as Number, cTop as Number, cBottom as Number) as Void {
        var step = 4;
        for (var y = 0; y < skyH; y += step) {
            var frac = y.toFloat() / skyH.toFloat();
            var c = lerpColor(cTop, cBottom, frac);
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, y, w, step);
        }
    }

    // ----------------------------------------------------------- Lifecycle

    function onHide() as Void {}

    function onExitSleep() as Void {
        mIsSleep = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        mIsSleep = true;
        mLastMin = -1;
        WatchUi.requestUpdate();
    }

    private function getWeatherString() as String or Null {
        try {
            if (Toybox has :Weather) {
                var conditions = Weather.getCurrentConditions();
                if (conditions != null && conditions.temperature != null) {
                    var temp = conditions.temperature;
                    var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
                    var isImperial = (settings has :temperatureUnits) && (settings.temperatureUnits != System.UNIT_METRIC);
                    if (isImperial) {
                        temp = (temp * 9.0 / 5.0 + 32.0).toNumber();
                        return temp.format("%d") + "°F";
                    } else {
                        return temp.format("%d") + "°C";
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    private function drawTextWithOutline(dc as Dc, x as Number, y as Number, font as Graphics.FontType, text as String, justify as Number, textColor as Number) as Void {
        if (mLowPower) {
            dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, text, justify);
            return;
        }
        // Outline pass count scales with adaptive quality (Fix #13): 8 offsets at
        // full detail, down to 0 (no outline) on hardware that can't keep up.
        var passes = (mQuality >= 3) ? 8 : (mQuality == 2) ? 4 : (mQuality == 1) ? 2 : 0;
        if (passes > 0) {
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            if (passes >= 4) {                       // 4 diagonal corners
                dc.drawText(x - 1, y - 1, font, text, justify);
                dc.drawText(x + 1, y - 1, font, text, justify);
                dc.drawText(x - 1, y + 1, font, text, justify);
                dc.drawText(x + 1, y + 1, font, text, justify);
            }
            if (passes >= 8) {                       // + 4 cardinals
                dc.drawText(x - 1, y,     font, text, justify);
                dc.drawText(x + 1, y,     font, text, justify);
                dc.drawText(x,     y - 1, font, text, justify);
                dc.drawText(x,     y + 1, font, text, justify);
            } else if (passes == 2) {                // light 2-pass drop outline
                dc.drawText(x + 1, y + 1, font, text, justify);
                dc.drawText(x - 1, y - 1, font, text, justify);
            }
        }
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, justify);
    }

    private function drawHeartIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawHeartShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawHeartShape(dc, x - 1, y - 1);
        drawHeartShape(dc, x + 1, y - 1);
        drawHeartShape(dc, x - 1, y + 1);
        drawHeartShape(dc, x + 1, y + 1);
        drawHeartShape(dc, x - 1, y);
        drawHeartShape(dc, x + 1, y);
        drawHeartShape(dc, x,     y - 1);
        drawHeartShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawHeartShape(dc, x, y);
    }

    private function drawHeartShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillCircle(x - 4, y - 3, 4);
        dc.fillCircle(x + 4, y - 3, 4);
        dc.fillPolygon([[x - 8, y - 3], [x + 8, y - 3], [x, y + 7]] as Array<Array>);
    }

    // Battery icon: a horizontal cell with a terminal nub and a fill bar whose
    // width tracks the live charge level (0-100). A black halo behind it keeps
    // the outline legible against the moving backdrop, matching the heart icon.
    private function drawBatteryIcon(dc as Dc, x as Number, y as Number, color as Number, level as Number) as Void {
        var bw = 14;
        var bh = 9;
        var left = x - bw / 2;
        var top = y - bh / 2;

        var lvl = level;
        if (lvl < 0) { lvl = 0; }
        if (lvl > 100) { lvl = 100; }

        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(left, top, bw, bh, 2);
            dc.fillRectangle(left + bw, y - 2, 2, 4);
            return;
        }

        // Black halo backing (shell + nub) for legibility.
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(left - 1, top - 1, bw + 2, bh + 2, 3);
        dc.fillRectangle(left + bw, y - 3, 4, 6);

        // Battery shell + terminal nub.
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(left, top, bw, bh, 2);
        dc.fillRectangle(left + bw, y - 2, 2, 4);

        // Inner fill bar proportional to the charge level.
        var innerMax = bw - 4;
        var fillW = (innerMax * lvl / 100).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(left + 2, top + 2, fillW, bh - 4);
        }
    }

    // Low-power partial update, called up to once per second in sleep mode.
    // Throttled to once per minute, and on AMOLED always-on it redraws only the
    // central time/date band (clipped) instead of the whole scene, keeping it
    // well inside the partial-update budget. (Fix #1 / #8)
    function onPartialUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();
        var min = clock.min;
        if (min == mLastMin) { return; }
        mLastMin = min;

        var settings = System.getDeviceSettings();
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        var aod = hasBurnIn && mIsSleep;

        // MIP (or no clip support): the sleep frame is the FULL colour scene and
        // MIP also calls onPartialUpdate, so a clipped clear would paint a black
        // band across the middle every minute. Keep the original full redraw. (Fix #8)
        if (!aod || !(dc has :setClip)) {
            onUpdate(dc);
            return;
        }

        // AMOLED always-on: clip to just the time/date band and redraw that.
        mLowPower = true;
        mFlatGlobes = false;
        mSettings = settings;   // cache for drawTime / drawDate this frame
        mClock = clock;
        mActInfo = null;

        var shift = computeBurnInShift();   // same anti-burn-in nudge as onUpdate
        var cx = mCenterX + shift[0];
        var cy = mCenterY + shift[1];

        var clipY = (mHeight * 0.30).toNumber();
        var clipH = (mHeight * 0.34).toNumber();
        dc.setClip(0, clipY, mWidth, clipH);

        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();
        drawTime(dc, cx, cy - (mHeight * 0.05).toNumber());
        if (mShowDate) { drawDate(dc, cx, cy + (mHeight * 0.06).toNumber()); }

        if (dc has :clearClip) { dc.clearClip(); }
    }
}
