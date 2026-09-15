import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// specs/modules/01-garmin-app.md §1 (per-state screens) + §3 (button
// semantics). Orchestrates the FSM, the sensor/rep-detection engine, and the
// EDIT_SET reps/weight editing UI; SetSyncDelegate forwards raw input here.
class SetSyncView extends WatchUi.View {

    private const REP_STEP = 1;
    private const WEIGHT_STEP_KG = 1.0;
    private const DEFAULT_WEIGHT_KG = 20.0;

    private var _stateMachine as WorkoutStateMachine = new WorkoutStateMachine();
    private var _repDetector as RepDetector = new RepDetector();
    private var _accelerometerSensor as AccelerometerSensor = new AccelerometerSensor(_repDetector);
    private var _uiTimer as Timer.Timer = new Timer.Timer();

    private var _restStartMs as Number = 0;
    private var _activeSetStartMs as Number = 0;

    // RESTING "last set summary" (§1); -1 reps means "no sets yet this session".
    private var _lastSetReps as Number = -1;
    private var _lastSetWeightKg as Float = DEFAULT_WEIGHT_KG;

    // EDIT_SET editable fields and which one UP/DOWN currently adjusts.
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
    // there (see specs/implementation-plan.md Task 2.4 decision).
    function onBackShortPressed() as Void {
        if (_stateMachine.canAdjustSet()) {
            _editFocus = (_editFocus == :reps) ? :weight : :reps;
            WatchUi.requestUpdate();
        }
    }

    // Touch equivalent of onBackShortPressed: tapping a field selects it.
    function onFieldTapped(field as Symbol) as Void {
        if (_stateMachine.canAdjustSet()) {
            _editFocus = field;
            WatchUi.requestUpdate();
        }
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
            var newWeight = _editWeightKg + (direction * WEIGHT_STEP_KG);
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
        } else if (from == WorkoutState.RESTING && to == WorkoutState.ACTIVE_SET) {
            _repDetector.reset();
            _accelerometerSensor.start();
            _activeSetStartMs = System.getTimer();
        } else if (from == WorkoutState.ACTIVE_SET && to == WorkoutState.EDIT_SET) {
            _accelerometerSensor.stop();
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(50, 200)]);
            }
            _editReps = _repDetector.getRepCount();
            _editWeightKg = _lastSetWeightKg;
            _editFocus = :reps;
        } else if (from == WorkoutState.EDIT_SET && to == WorkoutState.RESTING) {
            _lastSetReps = _editReps;
            _lastSetWeightKg = _editWeightKg;
            _restStartMs = System.getTimer();
        }
    }

    //
    // --- Per-state rendering ---
    //

    private function drawIdle(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        dc.drawText(width / 2, height / 2 - 20, Graphics.FONT_MEDIUM, "SetSync", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, height / 2 + 20, Graphics.FONT_SMALL, "START to begin workout", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawResting(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.drawText(width / 2, 40, Graphics.FONT_MEDIUM, "RESTING", Graphics.TEXT_JUSTIFY_CENTER);

        var summary = (_lastSetReps < 0) ? "No sets yet" : (_lastSetReps + " reps @ " + _lastSetWeightKg.format("%.1f") + " kg");
        dc.drawText(width / 2, height / 2 - 30, Graphics.FONT_SMALL, summary, Graphics.TEXT_JUSTIFY_CENTER);

        var restSeconds = (System.getTimer() - _restStartMs) / 1000;
        dc.drawText(width / 2, height / 2 + 10, Graphics.FONT_NUMBER_MEDIUM, formatMmSs(restSeconds), Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(width / 2, height - 40, Graphics.FONT_XTINY, "START to begin set", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawActiveSet(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.drawText(width / 2, 40, Graphics.FONT_MEDIUM, "ACTIVE SET", Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(width / 2, height / 2 - 40, Graphics.FONT_NUMBER_HOT, _repDetector.getRepCount().toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, height / 2 + 40, Graphics.FONT_XTINY, "reps", Graphics.TEXT_JUSTIFY_CENTER);

        var setSeconds = (System.getTimer() - _activeSetStartMs) / 1000;
        dc.drawText(width / 2, height / 2 + 70, Graphics.FONT_SMALL, formatMmSs(setSeconds), Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(width / 2, height - 40, Graphics.FONT_XTINY, "STOP to finish set", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawEditSet(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.drawText(width / 2, 30, Graphics.FONT_SMALL, "EDIT SET", Graphics.TEXT_JUSTIFY_CENTER);

        var repsColor = (_editFocus == :reps) ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE;
        dc.setColor(repsColor, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, height / 2 - 90, Graphics.FONT_TINY, "REPS", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, height / 2 - 60, Graphics.FONT_NUMBER_MEDIUM, _editReps.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        var weightColor = (_editFocus == :weight) ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE;
        dc.setColor(weightColor, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, height / 2 + 10, Graphics.FONT_TINY, "WEIGHT (kg)", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, height / 2 + 40, Graphics.FONT_NUMBER_MEDIUM, _editWeightKg.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, height - 30, Graphics.FONT_XTINY, "UP/DOWN adjust  BACK/tap switch  START confirm", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function formatMmSs(totalSeconds as Number) as String {
        var minutes = totalSeconds / 60;
        var seconds = totalSeconds % 60;
        return minutes.format("%02d") + ":" + seconds.format("%02d");
    }

    //
    // --- Layout helpers for SetSyncDelegate's tap hit-testing ---
    //

    // EDIT_SET splits the screen into an upper "reps" half and a lower
    // "weight" half; used by onFieldTapped's caller to translate a tap
    // y-coordinate into a field symbol.
    function editSetFieldAt(y as Number, screenHeight as Number) as Symbol {
        return (y < (screenHeight / 2)) ? :reps : :weight;
    }

    function getStateMachine() as WorkoutStateMachine {
        return _stateMachine;
    }
}
