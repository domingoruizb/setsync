import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// specs/modules/01-garmin-app.md §3: maps the fr165's physical buttons
// (START/STOP, UP, DOWN, BACK) and, for EDIT_SET focus selection, touch
// taps, onto SetSyncView's FSM-driving entry points.
class SetSyncDelegate extends WatchUi.BehaviorDelegate {

    // BACK must be held this long to count as "BACK (Hold)" (§3) and end
    // the session; a shorter release is treated as a short press. Not
    // specified exactly by the spec; raised from 1000ms to 1500ms (a more
    // standard hold-to-confirm duration) so an accidental firm tap can't
    // end the session/discard the in-progress rest.
    private const BACK_HOLD_THRESHOLD_MS = 1500;

    private var _view as SetSyncView;
    // Null until a KEY_ESC down is actually observed, so onKeyReleased can
    // defensively detect (and ignore) a release with no matching press.
    private var _backPressedAtMs as Number?;

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
            var pressedAtMs = _backPressedAtMs;
            _backPressedAtMs = null;
            // Defensive: a release with no recorded press (e.g. the press
            // was consumed elsewhere, or event ordering on some device)
            // must not compute a bogus multi-hour "held" duration — treat
            // it as a short press instead.
            if (pressedAtMs == null) {
                _view.onBackShortPressed();
                return true;
            }
            var heldMs = System.getTimer() - pressedAtMs;
            if (heldMs >= BACK_HOLD_THRESHOLD_MS) {
                _view.onBackHoldPressed();
            } else {
                _view.onBackShortPressed();
            }
            return true;
        }
        return false;
    }

    // The default BehaviorDelegate.onBack() calls WatchUi.popView(), which
    // crashes a single-screen device app (nothing on the view stack to pop
    // to — this was the simulator's blue-triangle reset). BACK is already
    // fully handled above via onKeyPressed/onKeyReleased timing, so this
    // just consumes the behavior-level dispatch without popping anything.
    function onBack() as Boolean {
        return true;
    }

    // Touch equivalent of the BACK short press: a tap advances the same
    // REPS -> WEIGHT (whole) -> WEIGHT (0.5) cycle (fr165 is touch-capable).
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        _view.onCycleFocusRequested();
        return true;
    }
}
