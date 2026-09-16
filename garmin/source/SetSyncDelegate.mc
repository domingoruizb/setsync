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

    // How long UP/DOWN must be held (measured by hand via onKeyPressed/
    // onKeyReleased below) before it counts as a hold rather than a short
    // press. `Toybox.WatchUi.InputDelegate.onHold()` was tried first, but
    // the SDK's own API metadata (api.debug.xml) confirms it only ever
    // fires for a *touch screen* hold (its parameter is a `ClickEvent`,
    // not a `KeyEvent`) — physical-button long-press detection has no
    // built-in equivalent and has to be timed by hand.
    private const HOLD_THRESHOLD_MS = 600;

    // Which physical key is currently down, and when it went down — set
    // by onKeyPressed, read/cleared by onKeyReleased.
    private var _pressedKey as Number = -1;
    private var _keyPressStartMs as Number = 0;

    // Set by onKeyReleased when it already dispatched a hold action for
    // this release; checked (and always reset) by onKey/onPreviousPage/
    // onNextPage below so a held UP/DOWN never *also* applies the normal
    // short-press step for the same physical press. This project's two
    // UP/DOWN dispatch paths (raw onKey vs. the onPreviousPage/onNextPage
    // behavior-level fallback) are believed mutually exclusive per device
    // (see the comment on onKey below), but onKeyPressed/onKeyReleased are
    // lower-level raw hooks that may or may not fire independently of
    // either — this flag makes the outcome correct either way: if
    // onKeyPressed/onKeyReleased never fire on a given device, this stays
    // false forever and behavior is byte-for-byte what it was before this
    // change.
    private var _lastHoldConsumed as Boolean = false;

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
            dispatchShortPressUnlessHoldConsumed(:up);
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            dispatchShortPressUnlessHoldConsumed(:down);
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
        dispatchShortPressUnlessHoldConsumed(:up);
        return true;
    }

    function onNextPage() as Boolean {
        dispatchShortPressUnlessHoldConsumed(:down);
        return true;
    }

    private function dispatchShortPressUnlessHoldConsumed(direction as Symbol) as Void {
        if (!_lastHoldConsumed) {
            if (direction == :up) {
                _view.onUpPressed();
            } else {
                _view.onDownPressed();
            }
        }
        _lastHoldConsumed = false;
    }

    // Raw press/release hooks (available since API 1.1.2, independent of
    // the onKey/onPreviousPage-onNextPage dispatch above): the only way to
    // measure how long UP/DOWN was actually held. Never consumes the
    // event itself (always returns false) — onKey/onPreviousPage/
    // onNextPage above still run on release exactly as before; a detected
    // hold just marks `_lastHoldConsumed` so those don't also apply the
    // short-press step for the same press.
    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN) {
            _pressedKey = key;
            _keyPressStartMs = System.getTimer();
            _lastHoldConsumed = false;
        }
        return false;
    }

    // Long-press UP/DOWN on EDIT_SET's weight-whole field: +/-5 kg instead
    // of the usual +/-1 kg short-press step. `SetSyncView.onWeightWholeHold()`
    // itself checks state/focus and returns false when it doesn't apply
    // (wrong field, or not in EDIT_SET at all) — in that case
    // `_lastHoldConsumed` stays false, so the normal short-press action
    // still runs once the same as any other press, "no interfiriendo con
    // el comportamiento por defecto" per this task's explicit request.
    function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if ((key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN) && key == _pressedKey) {
            var heldMs = System.getTimer() - _keyPressStartMs;
            _pressedKey = -1;
            if (heldMs >= HOLD_THRESHOLD_MS) {
                var delta = (key == WatchUi.KEY_UP) ? 5 : -5;
                _lastHoldConsumed = _view.onWeightWholeHold(delta);
            }
        }
        return false;
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
