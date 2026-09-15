import Toybox.Lang;

// specs/modules/01-garmin-app.md §2: SMA filtering (5-sample circular buffer)
// plus hysteresis peak detection (1.2g dynamic threshold, 800 ms refractory
// lockout, 0.9g valley confirmation) to count repetitions.
class RepDetector {

    private const SMA_WINDOW_SIZE = 5;
    private const PEAK_THRESHOLD_G = 1.2;
    private const VALLEY_THRESHOLD_G = 0.9;
    private const REFRACTORY_MS = 800;

    // Circular buffer of the last SMA_WINDOW_SIZE raw magnitude samples (g).
    private var _buffer as Array<Float>;
    private var _bufferIndex as Number = 0;
    private var _bufferFilled as Number = 0;
    private var _bufferSum as Float = 0.0;

    private var _repCount as Number = 0;
    private var _armed as Boolean = true;
    private var _aboveThreshold as Boolean = false;
    private var _lastPeakTimestampMs as Number = -1000000;

    function initialize() {
        _buffer = new Array<Float>[SMA_WINDOW_SIZE];
        reset();
    }

    function reset() as Void {
        for (var i = 0; i < SMA_WINDOW_SIZE; i++) {
            _buffer[i] = 0.0;
        }
        _bufferIndex = 0;
        _bufferFilled = 0;
        _bufferSum = 0.0;
        _repCount = 0;
        _armed = true;
        _aboveThreshold = false;
        _lastPeakTimestampMs = -1000000;
    }

    function getRepCount() as Number {
        return _repCount;
    }

    // magnitudeG: 3D vector magnitude a(t) = sqrt(x^2 + y^2 + z^2) of one raw
    // accelerometer sample, in g. timestampMs: sample timestamp in ms.
    function processSample(magnitudeG as Float, timestampMs as Number) as Void {
        var smoothed = pushAndAverage(magnitudeG);
        evaluatePeak(smoothed, timestampMs);
    }

    // 5-sample circular-buffer Simple Moving Average.
    private function pushAndAverage(magnitudeG as Float) as Float {
        _bufferSum -= _buffer[_bufferIndex];
        _buffer[_bufferIndex] = magnitudeG;
        _bufferSum += magnitudeG;
        _bufferIndex = (_bufferIndex + 1) % SMA_WINDOW_SIZE;
        if (_bufferFilled < SMA_WINDOW_SIZE) {
            _bufferFilled++;
        }
        return _bufferSum / _bufferFilled;
    }

    private function evaluatePeak(smoothedG as Float, timestampMs as Number) as Void {
        // Valley confirmation: only re-arm once acceleration has dropped
        // below 0.9g since the last counted peak.
        if (!_armed) {
            if (smoothedG < VALLEY_THRESHOLD_G) {
                _armed = true;
            }
            return;
        }

        // Dynamic threshold: track that we are above the 1.2g baseline.
        if (smoothedG > PEAK_THRESHOLD_G) {
            _aboveThreshold = true;
            return;
        }

        // The smoothed signal has fallen back through the threshold: the
        // local maximum has passed. Count it unless still within the 800 ms
        // refractory lockout (same stroke as the previous counted peak).
        if (_aboveThreshold) {
            _aboveThreshold = false;
            if ((timestampMs - _lastPeakTimestampMs) >= REFRACTORY_MS) {
                _repCount++;
                _lastPeakTimestampMs = timestampMs;
                _armed = false;
            }
        }
    }
}
