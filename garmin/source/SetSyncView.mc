import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// specs/modules/01-garmin-app.md §1 (per-state screens) + §3 (button
// semantics). Orchestrates the FSM, the sensor/rep-detection engine, and the
// EDIT_SET reps/weight editing UI; SetSyncDelegate forwards raw input here.
class SetSyncView extends WatchUi.View {

    private const REP_STEP = 1;
    private const WEIGHT_WHOLE_STEP_KG = 1.0;
    private const WEIGHT_DECIMAL_STEP_KG = 0.5;
    private const DEFAULT_WEIGHT_KG = 20.0;

    private var _stateMachine as WorkoutStateMachine = new WorkoutStateMachine();
    private var _repDetector as RepDetector = new RepDetector();
    private var _accelerometerSensor as AccelerometerSensor = new AccelerometerSensor(_repDetector);
    private var _communicationsService as CommunicationsService = new CommunicationsService();
    private var _uiTimer as Timer.Timer = new Timer.Timer();

    private var _restStartMs as Number = 0;
    private var _activeSetStartMs as Number = 0;

    // RESTING "last set summary" (§1); -1 reps means "no sets yet this session".
    private var _lastSetReps as Number = -1;
    private var _lastSetWeightKg as Float = DEFAULT_WEIGHT_KG;

    // Captured at ACTIVE_SET -> EDIT_SET (set duration) and RESTING ->
    // ACTIVE_SET (preceding rest duration), for the SET_COMPLETED payload
    // (specs/01-system-spec.md §2.1 durationSec/restSec) built on confirm.
    private var _lastSetDurationSec as Number = 0;
    private var _lastRestDurationSec as Number = 0;

    // EDIT_SET editable fields and which one UP/DOWN currently adjusts:
    // :reps -> :weightWhole -> :weightDecimal -> :reps (see
    // specs/implementation-plan.md Task 2.4 3-way focus-cycle decision).
    private var _editReps as Number = 0;
    private var _editWeightKg as Float = DEFAULT_WEIGHT_KG;
    private var _editFocus as Symbol = :reps;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _uiTimer.start(method(:onTimerTick), 1000, true);
    }

    function onTimerTick() as Void {
        // Refreshes the live rep-timer/rest-timer displays every second.
        if (_stateMachine.getState() == WorkoutState.ACTIVE_SET ||
            _stateMachine.getState() == WorkoutState.RESTING) {
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var state = _stateMachine.getState();
        if (state == WorkoutState.IDLE) {
            drawIdle(dc);
        } else if (state == WorkoutState.RESTING) {
            drawResting(dc);
        } else if (state == WorkoutState.ACTIVE_SET) {
            drawActiveSet(dc);
        } else if (state == WorkoutState.EDIT_SET) {
            drawEditSet(dc);
        }
    }

    //
    // --- Input entry points, called by SetSyncDelegate ---
    //

    function onStartStopPressed() as Void {
        var previousState = _stateMachine.getState();
        _stateMachine.onStartStopPressed();
        handleTransition(previousState, _stateMachine.getState());
        WatchUi.requestUpdate();
    }

    function onBackHoldPressed() as Void {
        var previousState = _stateMachine.getState();
        _stateMachine.onBackHoldPressed();
        handleTransition(previousState, _stateMachine.getState());
        WatchUi.requestUpdate();
    }

    // Short BACK press in EDIT_SET: no dedicated table entry for a focus
    // toggle button, so this reuses BACK's otherwise-unbound short press
    // there (see specs/implementation-plan.md Task 2.4 decision). Cycles
    // REPS -> WEIGHT (whole kg) -> WEIGHT (0.5 kg) -> REPS.
    function onBackShortPressed() as Void {
        cycleFocus();
    }

    // Touch equivalent of onBackShortPressed: a tap advances the same
    // 3-way cycle (fr165 is touch-capable) rather than selecting a field
    // directly, keeping the EDIT_SET screen free of hit-testing regions.
    function onCycleFocusRequested() as Void {
        cycleFocus();
    }

    private function cycleFocus() as Void {
        if (!_stateMachine.canAdjustSet()) {
            return;
        }
        if (_editFocus == :reps) {
            _editFocus = :weightWhole;
        } else if (_editFocus == :weightWhole) {
            _editFocus = :weightDecimal;
        } else {
            _editFocus = :reps;
        }
        WatchUi.requestUpdate();
    }

    function onUpPressed() as Void {
        adjustFocusedField(1);
    }

    function onDownPressed() as Void {
        adjustFocusedField(-1);
    }

    private function adjustFocusedField(direction as Number) as Void {
        if (!_stateMachine.canAdjustSet()) {
            return;
        }
        if (_editFocus == :reps) {
            var newReps = _editReps + (direction * REP_STEP);
            _editReps = (newReps < 0) ? 0 : newReps;
        } else {
            var step = (_editFocus == :weightWhole) ? WEIGHT_WHOLE_STEP_KG : WEIGHT_DECIMAL_STEP_KG;
            var newWeight = _editWeightKg + (direction * step);
            _editWeightKg = (newWeight < 0.0) ? 0.0 : newWeight;
        }
        WatchUi.requestUpdate();
    }

    //
    // --- State-transition side effects (sensor, vibration, snapshots) ---
    //

    private function handleTransition(from as WorkoutState.State, to as WorkoutState.State) as Void {
        if (from == WorkoutState.IDLE && to == WorkoutState.RESTING) {
            _lastSetReps = -1;
            _restStartMs = System.getTimer();
            // specs/01-system-spec.md §2.2: session start (§3 "Inicia
            // sesión (SESSION_EVENT: START)"). Was left unimplemented in
            // Task 2.5; closed here so a WorkoutSession actually exists on
            // the iOS side before any SET_COMPLETED arrives for it.
            _communicationsService.sendSessionEvent("START");
        } else if (from == WorkoutState.RESTING && to == WorkoutState.ACTIVE_SET) {
            _lastRestDurationSec = (System.getTimer() - _restStartMs) / 1000;
            _repDetector.reset();
            _accelerometerSensor.start();
            _activeSetStartMs = System.getTimer();
        } else if (from == WorkoutState.ACTIVE_SET && to == WorkoutState.EDIT_SET) {
            _accelerometerSensor.stop();
            _lastSetDurationSec = (System.getTimer() - _activeSetStartMs) / 1000;
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(50, 200)]);
            }
            _editReps = _repDetector.getRepCount();
            _editWeightKg = _lastSetWeightKg;
            _editFocus = :reps;
            // Rest starts the instant the set ends, not when EDIT_SET is
            // confirmed: time spent adjusting reps/weight is part of the
            // athlete's rest (see specs/implementation-plan.md Task 2.4
            // rest-timer fix).
            _restStartMs = System.getTimer();
        } else if (from == WorkoutState.EDIT_SET && to == WorkoutState.RESTING) {
            _lastSetReps = _editReps;
            _lastSetWeightKg = _editWeightKg;
            _communicationsService.enqueueSetCompleted(_editReps, _editWeightKg, _lastSetDurationSec, _lastRestDurationSec);
        } else if (from == WorkoutState.RESTING && to == WorkoutState.IDLE) {
            // Session end (§3 "BACK (Hold)" row), driven by
            // SetSyncDelegate's manually-timed BACK hold. Any
            // SET_COMPLETED payload still sitting in
            // CommunicationsService's queue (not yet SYNC_ACK'd) is
            // deliberately left untouched here: the queue and its 10s
            // retry timer are independent of the FSM state (see Task 2.5)
            // and keep retrying in the background regardless of which
            // screen is shown, so nothing pending is lost by returning to
            // IDLE.
            // specs/01-system-spec.md §2.2: session end (§3 "SESSION_EVENT:
            // STOP"), closing the same gap as the START event above.
            _communicationsService.sendSessionEvent("STOP");
        }
    }

    //
    // --- Per-state rendering ---
    //

    private function drawIdle(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        var titleFont = Graphics.FONT_MEDIUM;
        var promptFont = Graphics.FONT_SMALL;
        var hintFont = Graphics.FONT_XTINY;

        // Stack each line below the previous using its actual measured
        // height (dc.getFontHeight) instead of guessed offsets, so
        // "SetSync"/"START" can never collide regardless of font metrics.
        var titleHeight = dc.getFontHeight(titleFont);
        var promptHeight = dc.getFontHeight(promptFont);

        var titleY = (height / 2) - titleHeight - 10;
        var dividerY = titleY + titleHeight + 14;
        var promptY = dividerY + 14;
        var hintY = promptY + promptHeight + 4;

        // IDLE accent: subtle gray/white only, no state color.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(centerX, titleY, titleFont, "SetSync", Graphics.TEXT_JUSTIFY_CENTER);

        drawDivider(dc, dividerY);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(centerX, promptY, promptFont, "START", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(centerX, hintY, hintFont, "to begin workout", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Vertical padding kept between any text's measured edge and an
    // adjacent divider line, so a line can never touch/cross a glyph.
    // Reduced from 10 (this padding, stacked twice or more per screen, was
    // partly what pushed EDIT_SET's weight value past the bottom bezel).
    private const DIVIDER_PADDING = 6;

    private function drawResting(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        // RESTING accent: soft blue, denoting recovery. Divider cleared
        // using the header's own measured height, not a guessed offset.
        var headerFont = Graphics.FONT_SMALL;
        var headerY = 28;
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_BLACK);
        dc.drawText(centerX, headerY, headerFont, "RESTING", Graphics.TEXT_JUSTIFY_CENTER);
        drawDivider(dc, headerY + dc.getFontHeight(headerFont) + DIVIDER_PADDING);

        // Key metric: the rest timer, large and central — it must dominate.
        var restSeconds = (System.getTimer() - _restStartMs) / 1000;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(centerX, height / 2 - 70, Graphics.FONT_NUMBER_HOT, formatMmSs(restSeconds), Graphics.TEXT_JUSTIFY_CENTER);

        // Secondary: last-set summary, numbers in white, units/separator in
        // light gray — no "@", a clean structured "N reps  •  W kg".
        var summaryY = height / 2 + 60;
        if (_lastSetReps < 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(centerX, summaryY, Graphics.FONT_TINY, "No sets yet", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            drawSegments(dc, centerX, summaryY, Graphics.FONT_TINY, [
                [_lastSetReps.toString(), Graphics.COLOR_WHITE],
                [" reps", Graphics.COLOR_LT_GRAY],
                ["  •  ", Graphics.COLOR_LT_GRAY],
                [_lastSetWeightKg.format("%.1f"), Graphics.COLOR_WHITE],
                [" kg", Graphics.COLOR_LT_GRAY]
            ]);
        }

        // Discreet footer: transition hint, small and muted. Raised well
        // clear of the round bezel's bottom (was height - 52, too close).
        var footerFont = Graphics.FONT_XTINY;
        var footerY = height - 68;
        drawDivider(dc, footerY - DIVIDER_PADDING);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(centerX, footerY, footerFont, "START to begin set", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawActiveSet(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        // ACTIVE_SET accent: green, denoting live activity. Same
        // measured-height divider clearance as RESTING (identical layout
        // shape, so the same overlap would otherwise apply here too).
        var headerFont = Graphics.FONT_SMALL;
        var headerY = 28;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        dc.drawText(centerX, headerY, headerFont, "ACTIVE SET", Graphics.TEXT_JUSTIFY_CENTER);
        drawDivider(dc, headerY + dc.getFontHeight(headerFont) + DIVIDER_PADDING);

        // Key metric: the live rep count is the absolute visual focus.
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        dc.drawText(centerX, height / 2 - 80, Graphics.FONT_NUMBER_HOT, _repDetector.getRepCount().toString(), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(centerX, height / 2 + 35, Graphics.FONT_XTINY, "reps", Graphics.TEXT_JUSTIFY_CENTER);

        var setSeconds = (System.getTimer() - _activeSetStartMs) / 1000;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(centerX, height / 2 + 60, Graphics.FONT_SMALL, formatMmSs(setSeconds), Graphics.TEXT_JUSTIFY_CENTER);

        // Same footer position as RESTING (identical layout, so the same
        // too-close-to-the-bezel issue applied here too).
        var footerFont = Graphics.FONT_XTINY;
        var footerY = height - 68;
        drawDivider(dc, footerY - DIVIDER_PADDING);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(centerX, footerY, footerFont, "STOP to finish set", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // The weight value's bottom edge must never pass this y (round-bezel
    // safe area for a 390x390 display), regardless of how the accumulated
    // layout above it measures on a given device.
    private const EDIT_SET_WEIGHT_VALUE_MAX_BOTTOM_Y = 330;

    // No bottom help text by design (specs/implementation-plan.md Task 2.4
    // minimalist-UI decision) — the only affordance is the yellow
    // highlight on whichever field BACK/tap currently cycles.
    private function drawEditSet(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var centerX = width / 2;

        var titleFont = Graphics.FONT_SMALL;
        var labelFont = Graphics.FONT_TINY;
        var valueFont = Graphics.FONT_NUMBER_MEDIUM;

        // Every element's y is derived from the previous element's own
        // measured height (dc.getFontHeight) plus a fixed padding, so a
        // divider can never land on top of the text above or below it —
        // regardless of actual font metrics on a given device. Title
        // raised to 25 and gaps tightened (10px -> DIVIDER_PADDING=6, plus
        // the weight value's hard ceiling below) to keep everything clear
        // of the round bezel's bottom.
        var y = 25;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(centerX, y, titleFont, "EDIT SET", Graphics.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(titleFont) + DIVIDER_PADDING;
        drawDivider(dc, y);
        y += DIVIDER_PADDING;

        // Inactive fields dim gray, the focused field bright yellow.
        var repsColor = (_editFocus == :reps) ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY;
        dc.setColor(repsColor, Graphics.COLOR_BLACK);
        dc.drawText(centerX, y, labelFont, "REPS", Graphics.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(labelFont) + 4;

        dc.drawText(centerX, y, valueFont, _editReps.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(valueFont) + DIVIDER_PADDING;

        drawDivider(dc, y);
        y += DIVIDER_PADDING;

        var weightActive = (_editFocus == :weightWhole) || (_editFocus == :weightDecimal);
        dc.setColor(weightActive ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(centerX, y, labelFont, "WEIGHT (kg)", Graphics.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(labelFont) + 4;

        // Hard ceiling, independent of the (possibly larger than assumed)
        // accumulated offset above: clamp so the weight value's own
        // measured height never pushes its bottom edge past y = 330.
        var weightValueMaxY = EDIT_SET_WEIGHT_VALUE_MAX_BOTTOM_Y - dc.getFontHeight(valueFont);
        if (y > weightValueMaxY) {
            y = weightValueMaxY;
        }

        drawWeightValue(dc, centerX, y);
    }

    // Renders the weight as "<whole>.<decimal>" with each part colored
    // independently, so only the digits UP/DOWN currently affects are
    // highlighted (:weightWhole vs. :weightDecimal focus).
    private function drawWeightValue(dc as Graphics.Dc, centerX as Number, y as Number) as Void {
        var font = Graphics.FONT_NUMBER_MEDIUM;
        var weightStr = _editWeightKg.format("%.1f");
        var dotIndex = weightStr.find(".");
        var wholeStr = weightStr.substring(0, dotIndex);
        var decimalStr = weightStr.substring(dotIndex, weightStr.length());

        var wholeColor = (_editFocus == :weightWhole) ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY;
        var decimalColor = (_editFocus == :weightDecimal) ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY;

        drawSegments(dc, centerX, y, font, [
            [wholeStr, wholeColor],
            [decimalStr, decimalColor]
        ]);
    }

    // Draws a horizontal run of [text, color] pairs as one visually
    // contiguous, centered line, each segment colored independently (used
    // for the RESTING summary and the EDIT_SET weight value).
    private function drawSegments(dc as Graphics.Dc, centerX as Number, y as Number, font as Graphics.FontType, segments as Array) as Void {
        var totalWidth = 0;
        for (var i = 0; i < segments.size(); i++) {
            var segment = segments[i] as Array;
            totalWidth += dc.getTextWidthInPixels(segment[0] as String, font);
        }
        var x = centerX - (totalWidth / 2);
        for (var i = 0; i < segments.size(); i++) {
            var segment = segments[i] as Array;
            var text = segment[0] as String;
            dc.setColor(segment[1] as Number, Graphics.COLOR_BLACK);
            dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(text, font);
        }
    }

    // Horizontal divider inset from the round 390x390 bezel: half-width is
    // computed from the actual circle geometry (with a small margin) so it
    // never touches the curved edge, at any y.
    private function drawDivider(dc as Graphics.Dc, y as Number) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var radius = width / 2;
        var dy = y - (height / 2);
        var underRoot = (radius * radius) - (dy * dy);
        if (underRoot <= 0) {
            return;
        }
        var halfChord = Math.sqrt(underRoot).toNumber() - 15;
        if (halfChord <= 0) {
            return;
        }
        var centerX = width / 2;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(centerX - halfChord, y, centerX + halfChord, y);
    }

    private function formatMmSs(totalSeconds as Number) as String {
        var minutes = totalSeconds / 60;
        var seconds = totalSeconds % 60;
        return minutes.format("%02d") + ":" + seconds.format("%02d");
    }

    function getStateMachine() as WorkoutStateMachine {
        return _stateMachine;
    }
}
