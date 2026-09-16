import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

// specs/modules/01-garmin-app.md §4: Toybox.Communications.transmit()
// sender for SET_COMPLETED payloads, backed by a local FIFO queue with a
// 10 s periodic retry while the queue is non-empty and a link is available.
class CommunicationsService extends Communications.ConnectionListener {

    private const RETRY_INTERVAL_MS = 10000;

    private var _queue as SyncQueue = new SyncQueue();
    private var _retryTimer as Timer.Timer = new Timer.Timer();
    private var _transmitInFlight as Boolean = false;

    function initialize() {
        Communications.ConnectionListener.initialize();
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        }
        _retryTimer.start(method(:onRetryTick), RETRY_INTERVAL_MS, true);
    }

    // specs/01-system-spec.md §2.1: builds and enqueues a SET_COMPLETED
    // payload for the just-confirmed set, then attempts an immediate send.
    function enqueueSetCompleted(reps as Number, weightKg as Float, durationSec as Number, restSec as Number) as Void {
        _queue.enqueue(SetCompletedPayload.build(reps, weightKg, durationSec, restSec));
        attemptTransmit();
    }

    function onRetryTick() as Void {
        attemptTransmit();
    }

    // specs/01-system-spec.md §2.2: SESSION_EVENT (Garmin -> iOS), sent on
    // the FSM's IDLE <-> RESTING session boundary transitions. Fire-and-
    // forget in the sense of no FIFO queue/retry (§4's offline queue is
    // specified for SET_COMPLETED specifically, and there is no ACK
    // defined for SESSION_EVENT to track against), but the caller can
    // still pass `onFinished` to know when the transmit attempt has
    // settled (success or failure) — needed so the app can hold off
    // System.exit() until the STOP event has actually left the device
    // (field-test fix, see SetSyncView's RESTING -> IDLE handling). Uses
    // its own ConnectionListener rather than `self`, so it can't stomp on
    // `_transmitInFlight` if a SET_COMPLETED happens to be in flight at
    // the same moment.
    function sendSessionEvent(action as String, onFinished as Method?) as Void {
        var message = {
            "msgType" => "SESSION_EVENT",
            "payload" => {
                "action" => action,
                "timestamp" => SetCompletedPayload.unixTimestampSec()
            }
        };
        Communications.transmit(message, null, new SessionEventListener(onFinished));
    }

    // §4: only send when the queue is non-empty and the link is up; never
    // more than one transmit in flight at a time.
    private function attemptTransmit() as Void {
        if (_transmitInFlight || _queue.isEmpty()) {
            return;
        }
        if (!System.getDeviceSettings().connectionAvailable) {
            return;
        }
        var next = _queue.peekFront();
        if (next == null) {
            return;
        }
        _transmitInFlight = true;
        Communications.transmit(next, null, self);
    }

    // Reaching the phone's Bluetooth stack is not confirmation the app
    // processed the set: the queue item is only removed on SYNC_ACK (§4).
    function onComplete() as Void {
        _transmitInFlight = false;
    }

    function onError() as Void {
        _transmitInFlight = false;
    }

    // specs/01-system-spec.md §2.3: SYNC_ACK (iOS -> Garmin).
    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        var data = msg.data;
        if (!(data instanceof Dictionary)) {
            return;
        }
        var message = data as Dictionary;
        var msgType = message["msgType"];
        if ((msgType == null) || !msgType.equals("SYNC_ACK")) {
            return;
        }
        var ackPayload = message["payload"] as Dictionary;
        var setId = ackPayload["setId"];
        if (setId != null) {
            _queue.removeById(setId);
        }
    }
}

// Listener for sendSessionEvent()'s transmit, kept separate from
// CommunicationsService's own _transmitInFlight bookkeeping (see
// sendSessionEvent's comment). Invokes the optional onFinished callback on
// either outcome: the caller only needs to know the attempt settled, not
// whether it succeeded (there's no retry to decide between here).
class SessionEventListener extends Communications.ConnectionListener {
    private var _onFinished as Method?;

    function initialize(onFinished as Method?) {
        Communications.ConnectionListener.initialize();
        _onFinished = onFinished;
    }

    function onComplete() as Void {
        if (_onFinished != null) {
            _onFinished.invoke();
        }
    }

    function onError() as Void {
        if (_onFinished != null) {
            _onFinished.invoke();
        }
    }
}
