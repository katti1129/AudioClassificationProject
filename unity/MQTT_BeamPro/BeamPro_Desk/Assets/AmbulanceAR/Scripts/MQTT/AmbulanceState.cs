using System;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace AmbulanceAR
{
    [Serializable]
    public sealed class AmbulanceState
    {
        public int version = 1;
        public bool detected;
        public string class_name;
        public float confidence_pct;
        public float doa_deg = -1;
        public float rms;
        public float inference_ms;
        public long timestamp_ms;

        public static bool TryParse(string json, out AmbulanceState state)
        {
            state = null;
            if (string.IsNullOrWhiteSpace(json) || json.Length > 4096) return false;
            try
            {
                var obj = JObject.Parse(json, new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error });
                if (obj["version"]?.Type != JTokenType.Integer || (int)obj["version"] != 1 ||
                    obj["detected"]?.Type != JTokenType.Boolean || obj["class_name"]?.Type != JTokenType.String ||
                    obj["timestamp_ms"]?.Type != JTokenType.Integer) return false;
                foreach (string key in new[] { "confidence_pct", "doa_deg", "rms", "inference_ms" })
                {
                    var token = obj[key];
                    if (token == null || (token.Type != JTokenType.Float && token.Type != JTokenType.Integer)) return false;
                    double value = (double)token;
                    if (double.IsNaN(value) || double.IsInfinity(value) || Math.Abs(value) > float.MaxValue) return false;
                }
                var parsed = obj.ToObject<AmbulanceState>();
                if (parsed == null || string.IsNullOrWhiteSpace(parsed.class_name) || parsed.class_name.Length > 80 ||
                    parsed.confidence_pct < 0 || parsed.confidence_pct > 100 || parsed.doa_deg >= 360 ||
                    parsed.rms < 0 || parsed.inference_ms < 0 || parsed.timestamp_ms <= 0) return false;
                state = parsed;
                return true;
            }
            catch (Exception exception) when (exception is JsonException || exception is FormatException || exception is OverflowException || exception is ArgumentException)
            { return false; }
        }
    }

    // Shared monotonic time base for MQTT receipt, pose history and stale expiry.
    public static class ReceiveClock
    {
        public static double Now => (double)System.Diagnostics.Stopwatch.GetTimestamp() / System.Diagnostics.Stopwatch.Frequency;
    }

    public sealed class StateFreshness
    {
        public AmbulanceState Current { get; private set; }
        public double ReceivedAt { get; private set; } = double.NegativeInfinity;
        public bool Accept(string json, double receivedAt)
        {
            if (!AmbulanceState.TryParse(json, out var state)) return false;
            // Do not refresh warning age by replaying the same sample.
            if (Current != null && state.timestamp_ms <= Current.timestamp_ms) return false;
            Current = state;
            ReceivedAt = receivedAt;
            return true;
        }
        public bool Fresh(double now, double timeout) => Current != null && now >= ReceivedAt && now - ReceivedAt < timeout;
        public void Clear() { Current = null; ReceivedAt = double.NegativeInfinity; }
    }
}
