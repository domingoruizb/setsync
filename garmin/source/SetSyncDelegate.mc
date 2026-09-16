import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// specs/modules/01-garmin-app.md §3: maps the fr165's physical buttons
// (START/STOP, UP, DOWN, BACK) and, for EDIT_SET focus selection, touch
// taps, onto SetSyncView's FSM-driving entry points.
class SetSyncDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SetSyncView;

    function initialize(view as SetSyncView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Physical button pressed and released as a single click (§3:
    // START/STOP, UP, DOWN rows all fire on a normal press). Devices vary
    // in whether the START/STOP button surfaces as KEY_START or KEY_ENTER,
    // so both are accepted; onSelect()/onNextPage()/onPreviousPage() below
    // cover the behavior-level dispatch path some devices use instead of
    // raw key events for the same physical buttons.
    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START || key == WatchUi.KEY_ENTER) {
            _view.onStartStopPressed();
            return true;
        } else if (key == WatchUi.KEY_UP) {
            _view.onUpPressed();
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            _view.onDownPressed();
            return true;
        } else if (key == WatchUi.KEY_ESC) {
            return handleBackPressed();
        }
        return false;
    }

    // Behavior-level fallback for START/STOP: some devices dispatch the
    // select/enter button here instead of (or in addition to) onKey().
    function onSelect() as Boolean {
        _view.onStartStopPressed();
        return true;
    }

    // Behavior-level fallback for UP/DOWN. Garmin's convention maps the
    // physical UP button to "previous" and DOWN to "next".
    function onPreviousPage() as Boolean {
        _view.onUpPressed();
        return true;
    }

    function onNextPage() as Boolean {
        _view.onDownPressed();
        return true;
    }

    // Field-tested on a real fr165 (not just the simulator): holding BACK
    // in RESTING never reached the app at all — the firmware intercepts a
    // genuine BACK hold before it is ever delivered, so there was no down/
    // up-timing threshold that could have made the old hold-detection
    // approach work. BACK's action is now driven purely by state, from a
    // single combined press+release event (both the physical key here and
    // the touch swipe-right gesture via onBack() below), no timing at all:
    //  - RESTING: ends the session immediately (was "BACK (Hold)" in §3;
    //    a plain press is the only mechanism that is actually delivered).
    //  - EDIT_SET: cycles the reps/weight focus (unchanged from before).
    //  - IDLE: exits the app back to the watch face via System.exit() —
    //    the default BehaviorDelegate.onBack() would otherwise call
    //    WatchUi.popView(), which crashes this single-view device app.
    //  - ACTIVE_SET: no defined BACK behavior (§3); swallowed as a no-op.
    private function handleBackPressed() as Boolean {
        var state = _view.getStateMachine().getState();
        if (state == WorkoutState.RESTING) {
            _view.onEndSessionRequested();
        } else if (state == WorkoutState.EDIT_SET) {
            _view.onBackShortPressed();
        } else if (state == WorkoutState.IDLE) {
            // Field-test fix: don't tear the process down while the just-
            // sent SESSION_EVENT: STOP transmit (and its "Session Saved"
            // legibility window) is still pending — see
            // SetSyncView.canExitApp()/handleTransition.
            if (_view.canExitApp()) {
                System.exit();
            }
        }
        return true;
    }

    // Touch equivalent of the physical BACK button (fr165 recognizes a
    // swipe-right gesture as "back"): routed through the same state-driven
    // handler so both input sources behave identically.
    function onBack() as Boolean {
        return handleBackPressed();
    }

    // Touch equivalent of the BACK short press: a tap advances the same
    // REPS -> WEIGHT (whole) -> WEIGHT (0.5) cycle (fr165 is touch-capable).
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        _view.onCycleFocusRequested();
        return true;
    }
}
