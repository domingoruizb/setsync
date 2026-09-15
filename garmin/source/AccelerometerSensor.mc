import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;

// specs/modules/01-garmin-app.md §2: registers the 25 Hz accelerometer
// listener and feeds each raw sample's 3D vector magnitude into a
// RepDetector. Sampling config only — not wired into the FSM/UI yet
// (that integration belongs to later tasks).
class AccelerometerSensor {

    private const SAMPLE_RATE_HZ = 25;
    private const MILLI_G_PER_G = 1000.0;

    private var _repDetector as RepDetector;

    function initialize(repDetector as RepDetector) {
        _repDetector = repDetector;
    }

    function start() as Void {
        var options = {
            :period => 1,
            :accelerometer => {
                :enabled => true,
                :sampleRate => SAMPLE_RATE_HZ,
                :includeTimestamps => true
            }
        };
        try {
            Sensor.registerSensorDataListener(method(:onAccelerometerData), options);
        } catch (e) {
            System.println(e.getErrorMessage());
        }
    }

    function stop() as Void {
        Sensor.unregisterSensorDataListener();
    }

    // specs/modules/01-garmin-app.md §2: a(t) = sqrt(x(t)^2 + y(t)^2 + z(t)^2),
    // converted from milli-G (raw AccelerometerData units) to g.
    function onAccelerometerData(sensorData as SensorData) as Void {
        var accel = sensorData.accelerometerData;
        if (accel == null) {
            return;
        }

        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        var timestamps = accel.timestamp;
        if (xs == null || ys == null || zs == null) {
            return;
        }

        for (var i = 0; i < xs.size(); i++) {
            var magnitudeG = Math.sqrt(
                Math.pow(xs[i] / MILLI_G_PER_G, 2) +
                Math.pow(ys[i] / MILLI_G_PER_G, 2) +
                Math.pow(zs[i] / MILLI_G_PER_G, 2)
            ).toFloat();
            var timestampMs = (timestamps != null) ? timestamps[i] : System.getTimer();
            _repDetector.processSample(magnitudeG, timestampMs);
        }
    }
}
