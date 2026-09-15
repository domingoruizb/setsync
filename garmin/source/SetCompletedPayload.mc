import Toybox.Lang;
import Toybox.Time;

// specs/01-system-spec.md §2.1: SET_COMPLETED payload (Garmin -> iOS). Keys
// and nesting must match this schema exactly ("invarianza de payloads",
// specs/RULES.md §3) — never change these key names independently of
// specs/01-system-spec.md.
module SetCompletedPayload {

    // Toybox.Time epoch is 1989-12-31T00:00:00Z, not the Unix epoch used by
    // the iOS side of the contract; this is the fixed offset (seconds)
    // between the two so "timestamp" is a standard Unix timestamp.
    const GARMIN_TO_UNIX_EPOCH_OFFSET_SEC = 631065600;

    function build(reps as Number, weightKg as Float, durationSec as Number, restSec as Number) as Dictionary {
        var unixTimestampSec = Time.now().value() + GARMIN_TO_UNIX_EPOCH_OFFSET_SEC;
        var setId = (unixTimestampSec * 1000).toString();

        return {
            "msgType" => "SET_COMPLETED",
            "payload" => {
                "setId" => setId,
                "reps" => reps,
                "weightKg" => weightKg,
                "durationSec" => durationSec,
                "restSec" => restSec,
                "timestamp" => unixTimestampSec
            }
        };
    }
}
