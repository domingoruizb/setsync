import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// specs/modules/01-garmin-app.md §3: maps the fr165's physical buttons
// (START/STOP, UP, DOWN, BACK) and, for EDIT_SET focus selection, touch
// taps, onto SetSyncView's FSM-driving entry points.
class SetSyncDelegate extends WatchUi.BehaviorDelegate {

    // BACK must be held this long to count as "BACK (Hold)" (§3); a
    // shorter release is treated as a short press. Not specified exactly
    // by the spec, so a conventional 1 s hold duration is used.
    private const BACK_HOLD_THRESHOLD_MS = 1000;

    private var _view as SetSyncView;
    private var _backPressedAtMs as Number = 0;

    function initialize(view as SetSyncView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Physical button pressed and released as a single click (§3:
    // START/STOP, UP, DOWN rows all fire on a normal press).
    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START) {
            _view.onStartStopPressed();
            return true;
        } else if (key == WatchUi.KEY_UP) {
            _view.onUpPressed();
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            _view.onDownPressed();
            return true;
        }
        return false;
    }

    // BACK is timed manually (down -> up) to distinguish a short press
    // (EDIT_SET focus toggle) from BACK (Hold) (RESTING -> IDLE, §3).
    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_ESC) {
            _backPressedAtMs = System.getTimer();
            return true;
        }
        return false;
    }

    function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_ESC) {
            var heldMs = System.getTimer() - _backPressedAtMs;
            if (heldMs >= BACK_HOLD_THRESHOLD_MS) {
                _view.onBackHoldPressed();
            } else {
                _view.onBackShortPressed();
            }
            return true;
        }
        return false;
    }

    // Touch equivalent of the BACK short press: tapping the REPS or WEIGHT
    // area in EDIT_SET selects that field directly (fr165 is touch-capable).
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        var coordinates = clickEvent.getCoordinates();
        var screenHeight = System.getDeviceSettings().screenHeight;
        var field = _view.editSetFieldAt(coordinates[1], screenHeight);
        _view.onFieldTapped(field);
        return true;
    }
}
