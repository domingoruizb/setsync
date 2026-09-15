import Toybox.Lang;

// specs/modules/01-garmin-app.md §1: Finite State Machine states.
module WorkoutState {
    enum State {
        IDLE,
        RESTING,
        ACTIVE_SET,
        EDIT_SET
    }
}
