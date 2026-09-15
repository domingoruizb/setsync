import Toybox.Lang;

// specs/modules/01-garmin-app.md §3: valid state transitions per physical button.
// Any trigger not defined for the current state is a no-op, keeping the FSM
// well-defined (no undefined/implicit transitions).
class WorkoutStateMachine {

    private var _state as WorkoutState.State;

    function initialize() {
        _state = WorkoutState.IDLE;
    }

    function getState() as WorkoutState.State {
        return _state;
    }

    // START/STOP row: IDLE -> RESTING -> ACTIVE_SET -> EDIT_SET -> RESTING.
    function onStartStopPressed() as Void {
        if (_state == WorkoutState.IDLE) {
            _state = WorkoutState.RESTING;
        } else if (_state == WorkoutState.RESTING) {
            _state = WorkoutState.ACTIVE_SET;
        } else if (_state == WorkoutState.ACTIVE_SET) {
            _state = WorkoutState.EDIT_SET;
        } else if (_state == WorkoutState.EDIT_SET) {
            _state = WorkoutState.RESTING;
        }
    }

    // BACK (Hold) row: RESTING -> IDLE only.
    function onBackHoldPressed() as Void {
        if (_state == WorkoutState.RESTING) {
            _state = WorkoutState.IDLE;
        }
    }

    // UP/DOWN row: only meaningful in EDIT_SET and never changes state.
    function canAdjustSet() as Boolean {
        return _state == WorkoutState.EDIT_SET;
    }
}
