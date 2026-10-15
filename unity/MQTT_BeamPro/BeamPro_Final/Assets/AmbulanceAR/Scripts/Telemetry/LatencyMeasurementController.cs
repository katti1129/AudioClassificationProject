using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace AmbulanceAR
{
    public sealed class LatencyMeasurementController : MonoBehaviour
    {
        [Tooltip("Research only. Also start Jetson with --measure-latency. Restart Play/app after changing.")]
        public bool measureLatency;
        public AmbulanceMqttSubscriber subscriber;
        [Range(2, 120)] public float observationSeconds = 10;
        public string Status { get; private set; } = "OFF";
        public string CsvPath => logger?.Path;
        readonly LatencyClock clock = new LatencyClock();
        readonly Dictionary<string, Trial> trials = new Dictionary<string, Trial>();
        readonly HashSet<string> completed = new HashSet<string>();
        readonly Dictionary<long, Frame> frames = new Dictionary<long, Frame>();
        readonly Dictionary<long, Result> results = new Dictionary<long, Result>();
        LatencyTelemetryClient client;
        LatencyCsvLogger logger;
        Coroutine routine;
        long pendingStamp;
        double pendingReceived;
        double pendingConfidence = double.NaN;
        bool pendingWarning, pendingArrow;
        bool warningWasVisible, arrowWasVisible;
        double warningStarted, arrowStarted;
        int dropped;
        int lastEpoch;

        sealed class Trial
        {
            public string Session, Id, Method, Invalid = "";
            public double T0, Started;
            public Frame Warning, Arrow;
            public Result WarningResult;
            public double Offset = double.NaN, Rtt = double.NaN, Age = double.NaN, ArrowTotal = double.NaN;
            public int JetsonDropped;
            public bool HadResult, HadSiren;
        }
        sealed class Result
        {
            public string Key, Class;
            public long Stamp, Inference;
            public double T1, T2, Arrived;
        }
        sealed class Frame
        {
            public double Received, Warning = double.NaN, Arrow = double.NaN, Last;
            public double WarningStarted, ArrowStarted;
            public double WarningConfidence = double.NaN, ArrowConfidence = double.NaN;
        }
        void OnEnable()
        {
            if (!measureLatency) return;
            if (!subscriber) subscriber = GetComponent<AmbulanceMqttSubscriber>();
            if (!subscriber) { Status = "missing subscriber"; return; }
            frames.Clear(); results.Clear(); trials.Clear(); completed.Clear(); clock.Reset();
            pendingStamp = 0; dropped = 0; lastEpoch = subscriber.Epoch;
            warningWasVisible = arrowWasVisible = false;
            logger = new LatencyCsvLogger(Path.Combine(Application.persistentDataPath, "Latency"));
            client = new LatencyTelemetryClient(subscriber.brokerHost, subscriber.brokerPort, subscriber.topic);
            if (Application.isPlaying) routine = StartCoroutine(EndOfFrames());
            Debug.Log("[Latency] CSV: " + logger.Path + "; frame-end estimate, not optical display time.");
        }
        void Update()
        {
            if (client == null) return;
            if (subscriber.Epoch != lastEpoch)
            { MarkInterrupted("state_connection_changed"); lastEpoch = subscriber.Epoch; }
            for (int i = 0; i < 128 && client.TryDequeue(out var message); i++) Handle(message);
            double now = ReceiveClock.Now;
            foreach (var pair in results) Match(pair.Value, now);
            foreach (var key in new List<string>(trials.Keys))
                if (now - trials[key].Started >= observationSeconds) Finish(key, "");
            foreach (long key in new List<long>(frames.Keys))
                if (now - frames[key].Last > observationSeconds + 5) frames.Remove(key);
            foreach (long key in new List<long>(results.Keys))
                if (now - results[key].Arrived > observationSeconds + 5) results.Remove(key);
            bool synced = clock.TryGet(clock.Session, now, out _, out var rtt, out _);
            Status = logger.Error ?? (client.Status + (synced ? $" | sync RTT {rtt * 1000:F1} ms" : " | waiting for sync")
                + $" | dropped {dropped + client.Dropped + logger.Dropped}");
        }
        void MarkInterrupted(string reason)
        {
            foreach (var trial in trials.Values) trial.Invalid = reason;
            frames.Clear(); results.Clear(); pendingStamp = 0;
        }
        static double Number(JObject json, string name)
        {
            var token = json[name];
            if (token == null || (token.Type != JTokenType.Float && token.Type != JTokenType.Integer))
                throw new FormatException(name);
            double value = token.Value<double>();
            if (!LatencyClock.Finite(value)) throw new FormatException(name);
            return value;
        }
        static string Text(JObject json, string name)
        {
            var token = json[name];
            if (token?.Type != JTokenType.String || token.Value<string>().Length > 128) throw new FormatException(name);
            return token.Value<string>();
        }
        void Handle(LatencyTelemetryClient.Message message)
        {
            if (message.Kind == "reset") { clock.Reset(); MarkInterrupted("telemetry_connection_changed"); return; }
            try
            {
                var json = JObject.Parse(message.Json);
                string session = Text(json, "session");
                if (message.Kind == "sync/response")
                {
                    if (client.TakeRequest(Text(json, "id"), out double sent))
                    {
                        if (clock.Session != null && clock.Session != session) MarkInterrupted("jetson_restarted");
                        clock.Add(session, sent, Number(json, "s2"), Number(json, "s3"), message.ReceivedAt);
                    }
                    return;
                }
                if (message.Kind != "event" && message.Kind != "result") return;
                string id = Text(json, "trial_id"), key = session + ":" + id;
                if (completed.Contains(key)) return;
                double t0 = Number(json, "t0");
                string method = Text(json, "onset_method"), invalid = Text(json, "invalid");
                if (!trials.TryGetValue(key, out var trial))
                {
                    if (trials.Count >= 128) { dropped++; return; }
                    trials[key] = trial = new Trial { Session = session, Id = id, T0 = t0,
                        Method = method, Started = message.ReceivedAt };
                }
                if (trial.T0 != t0) trial.Invalid = "onset_mismatch";
                if (invalid.Length > 0) trial.Invalid = invalid;
                if (message.Kind == "event") return;
                var result = new Result { Key = key, Stamp = checked((long)Number(json, "timestamp_ms")),
                    Inference = checked((long)Number(json, "inference_id")), T1 = Number(json, "t1"),
                    T2 = Number(json, "t2"), Class = Text(json, "final_class"), Arrived = message.ReceivedAt };
                if (result.Stamp <= 0 || result.T2 < result.T1 || result.T1 < t0) throw new FormatException("time order");
                trial.HadResult = true;
                trial.HadSiren |= result.Class == "siren";
                trial.JetsonDropped = checked((int)Number(json, "telemetry_dropped"));
                if (results.TryGetValue(result.Stamp, out var previous) && (previous.Key != key || previous.Inference != result.Inference))
                { trial.Invalid = "duplicate_timestamp"; return; }
                if (results.Count >= 1024) { trial.Invalid = "result_capacity"; dropped++; return; }
                results[result.Stamp] = result;
                Match(result, ReceiveClock.Now);
            }
            catch (Exception ex) when (ex is Newtonsoft.Json.JsonException || ex is FormatException || ex is OverflowException || ex is InvalidCastException)
            { dropped++; }
        }
        // Called after the normal Present methods. No telemetry/network wait in the display path.
        public void ObservePresentation(long stamp, double received, bool warning, bool arrow, double confidencePct = double.NaN)
        {
            if (!measureLatency || logger == null) return;
            pendingStamp = stamp; pendingReceived = received; pendingWarning = warning; pendingArrow = arrow;
            pendingConfidence = LatencyClock.Finite(confidencePct) && confidencePct >= 0 && confidencePct <= 100
                ? Math.Round(confidencePct, 3) : double.NaN;
        }
        IEnumerator EndOfFrames()
        {
            var wait = new WaitForEndOfFrame();
            while (true)
            {
                yield return wait;
                RecordFrameEnd(ReceiveClock.Now);
            }
        }
        void RecordFrameEnd(double now)
        {
                if (pendingStamp <= 0) { warningWasVisible = arrowWasVisible = false; return; }
                if (pendingWarning && !warningWasVisible) warningStarted = now;
                if (pendingArrow && !arrowWasVisible) arrowStarted = now;
                warningWasVisible = pendingWarning; arrowWasVisible = pendingArrow;
                if (!frames.TryGetValue(pendingStamp, out var frame))
                {
                    if (frames.Count >= 1024) { dropped++; return; }
                    frames[pendingStamp] = frame = new Frame { Received = pendingReceived };
                }
                frame.Last = now;
                if (pendingWarning && double.IsNaN(frame.Warning))
                { frame.Warning = now; frame.WarningStarted = warningStarted; frame.WarningConfidence = pendingConfidence; }
                if (pendingArrow && double.IsNaN(frame.Arrow))
                { frame.Arrow = now; frame.ArrowStarted = arrowStarted; frame.ArrowConfidence = pendingConfidence; }
                if (results.TryGetValue(pendingStamp, out var result)) Match(result, now);
                pendingStamp = 0;
        }
        void Match(Result result, double now)
        {
            if (result.Class != "siren" || !trials.TryGetValue(result.Key, out var trial)
                || !frames.TryGetValue(result.Stamp, out var frame)) return;
            if (LatencyClock.Finite(frame.Warning) && (trial.Warning == null || frame.Warning < trial.Warning.Warning))
            {
                trial.Warning = new Frame { Received = frame.Received, Warning = frame.Warning,
                    WarningStarted = frame.WarningStarted, WarningConfidence = frame.WarningConfidence };
                trial.WarningResult = result;
                if (clock.TryGet(trial.Session, now, out double offset, out double rtt, out double age))
                { trial.Offset = offset; trial.Rtt = rtt; trial.Age = age; }
            }
            if (LatencyClock.Finite(frame.Arrow) && (trial.Arrow == null || frame.Arrow < trial.Arrow.Arrow))
                trial.Arrow = new Frame { Received = frame.Received, Arrow = frame.Arrow,
                    ArrowStarted = frame.ArrowStarted, ArrowConfidence = frame.ArrowConfidence };
            // Metadata can precede sync. Fill a missing estimate while this trial is still open.
            if (trial.Warning != null && !LatencyClock.Finite(trial.Offset)
                && clock.TryGet(trial.Session, now, out double o, out double r, out double a))
            { trial.Offset = o; trial.Rtt = r; trial.Age = a; }
            if (trial.Arrow != null && LatencyClock.Finite(trial.Offset))
                trial.ArrowTotal = trial.Arrow.Arrow - (trial.T0 - trial.Offset);
        }
        void Finish(string key, string reason)
        {
            var t = trials[key];
            var w = t.Warning; var m = t.WarningResult;
            LatencyDurations durations = null;
            string status = t.Invalid.Length > 0 ? "invalid" : reason.Length > 0 ? "incomplete" :
                w == null ? (t.HadResult ? "no_warning" : "no_result_metadata") : t.Arrow == null ? "no_arrow" : "ok";
            string notes = t.Invalid.Length > 0 ? t.Invalid : reason;
            if (w != null && !LatencyDurations.TryCalculate(t.T0, m.T1, m.T2, w.Received, w.Warning, t.Offset, out durations))
            { status = "invalid"; notes += " unsynchronized_or_invalid_time"; }
            if (t.ArrowTotal < 0) { status = "invalid"; notes += " negative_arrow_time"; }
            if (w != null && w.WarningStarted < w.Warning)
            { status = "invalid"; notes += " warning_preexisting_or_initial_metadata_missing"; durations = null; }
            if (t.Arrow != null && t.Arrow.ArrowStarted < t.Arrow.Arrow)
            { status = "invalid"; notes += " arrow_preexisting_or_initial_metadata_missing"; }
            if (t.Invalid.Length > 0 || reason.Length > 0) durations = null;
            logger.Submit(t.Session, t.Id, status, t.Method, m?.Inference, m?.Stamp, t.T0, m?.T1, m?.T2,
                w?.Received, w?.Warning, t.Arrow?.Arrow, durations?.Detection, durations?.SendWait,
                durations?.Transport, durations?.Unity, durations?.Total,
                status == "invalid" || reason.Length > 0 ? (object)null : t.ArrowTotal,
                t.Offset, t.Rtt, t.Age, t.JetsonDropped, dropped + (client?.Dropped ?? 0) + logger.Dropped,
                notes + (t.HadSiren ? "" : " no_siren_result_observed"), observationSeconds,
                w?.WarningConfidence, t.Arrow?.ArrowConfidence);
            trials.Remove(key);
            completed.Add(key);
            if (completed.Count > 4096) completed.Clear();
        }
        void OnDisable()
        {
            if (routine != null) StopCoroutine(routine);
            if (logger != null)
                foreach (var key in new List<string>(trials.Keys)) Finish(key, "measurement_stopped");
            client?.Dispose(); client = null;
            logger?.Dispose(); logger = null;
            Status = "OFF";
        }
    }
}
