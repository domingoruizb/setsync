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
    // forget (no FIFO queue/retry): §4's offline queue is specified for
    // SET_COMPLETED specifically, and there is no ACK defined for
    // SESSION_EVENT to track against. Uses its own ConnectionListener
    // rather than `self`, so it can't stomp on `_transmitInFlight` if a
    // SET_COMPLETED happens to be in flight at the same moment.
    function sendSessionEvent(action as String) as Void {
        var message = {
            "msgType" => "SESSION_EVENT",
            "payload" => {
                "action" => action,
                "timestamp" => SetCompletedPayload.unixTimestampSec()
            }
        };
        Communications.transmit(message, null, new SessionEventListener());
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

// Dedicated no-op listener for sendSessionEvent()'s fire-and-forget
// transmit, kept separate from CommunicationsService's own
// _transmitInFlight bookkeeping (see sendSessionEvent's comment).
class SessionEventListener extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }

    function onComplete() as Void {
    }

    function onError() as Void {
    }
}
