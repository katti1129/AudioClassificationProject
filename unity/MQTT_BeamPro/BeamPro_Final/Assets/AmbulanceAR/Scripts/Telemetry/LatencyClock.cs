using System;
using System.Collections.Generic;

namespace AmbulanceAR
{
    // Offset = Jetson monotonic clock - Unity ReceiveClock. No wall-clock subtraction.
    public sealed class LatencyClock
    {
        struct Sample { public double At, Offset, Rtt; }
        readonly List<Sample> samples = new List<Sample>();
        public string Session { get; private set; }
        public void Reset() { samples.Clear(); Session = null; }
        public static bool Finite(double value) => !double.IsNaN(value) && !double.IsInfinity(value);
        public bool Add(string session, double t1, double s2, double s3, double t4)
        {
            if (string.IsNullOrEmpty(session) || !Finite(t1) || !Finite(s2) || !Finite(s3) || !Finite(t4)
                || t4 < t1 || s3 < s2) return false;
            double rtt = (t4 - t1) - (s3 - s2);
            if (rtt < 0 || rtt > .25) return false;
            if (Session != session) { Reset(); Session = session; }
            samples.Add(new Sample { At = t4, Rtt = rtt, Offset = ((s2 - t1) + (s3 - t4)) / 2 });
            if (samples.Count > 16) samples.RemoveAt(0);
            return true;
        }
        public bool TryGet(string session, double now, out double offset, out double rtt, out double age)
        {
            offset = rtt = age = double.NaN;
            if (Session != session) return false;
            double best = double.PositiveInfinity;
            foreach (var sample in samples)
                if (now >= sample.At && now - sample.At <= 10 && sample.Rtt < best)
                { best = sample.Rtt; offset = sample.Offset; rtt = sample.Rtt; age = now - sample.At; }
            return Finite(offset);
        }
    }

    public sealed class LatencyDurations
    {
        public double Detection, SendWait, Transport, Unity, Total;
        public static bool TryCalculate(double t0, double t1, double t2, double t3, double t4,
            double offset, out LatencyDurations result)
        {
            result = null;
            foreach (double value in new[] { t0, t1, t2, t3, t4, offset })
                if (!LatencyClock.Finite(value)) return false;
            if (t1 < t0 || t2 < t1 || t4 < t3) return false;
            result = new LatencyDurations { Detection = t1 - t0, SendWait = t2 - t1,
                Transport = t3 - (t2 - offset), Unity = t4 - t3, Total = t4 - (t0 - offset) };
            // Negative cross-device times indicate that this estimate is unusable; never clamp to zero.
            if (result.Transport < 0 || result.Total < 0) { result = null; return false; }
            return true;
        }
    }
}
