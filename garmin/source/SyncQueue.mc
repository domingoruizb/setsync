import Toybox.Lang;

// specs/modules/01-garmin-app.md §4: local FIFO queue of SET_COMPLETED
// payloads pending a SYNC_ACK. Held in volatile memory only (one of the two
// options §4 allows).
class SyncQueue {

    private var _items as Array<Dictionary> = [];

    function enqueue(payload as Dictionary) as Void {
        _items.add(payload);
    }

    function peekFront() as Dictionary? {
        return (_items.size() > 0) ? _items[0] : null;
    }

    // §4: "Al recibir SYNC_ACK desde el iPhone, se remueve el ítem
    // confirmado de la cola" — removes the queued payload whose
    // payload.setId matches, regardless of queue position.
    function removeById(setId as String) as Void {
        for (var i = 0; i < _items.size(); i++) {
            var item = _items[i];
            var payload = item["payload"] as Dictionary;
            var itemSetId = payload["setId"];
            if ((itemSetId != null) && itemSetId.equals(setId)) {
                _items.remove(item);
                return;
            }
        }
    }

    function isEmpty() as Boolean {
        return _items.size() == 0;
    }

    function size() as Number {
        return _items.size();
    }
}
