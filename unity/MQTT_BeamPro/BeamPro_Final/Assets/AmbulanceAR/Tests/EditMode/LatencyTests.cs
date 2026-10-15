using System;
using System.IO;
using System.Reflection;
using Newtonsoft.Json.Linq;
using NUnit.Framework;
using UnityEngine;

namespace AmbulanceAR.Tests
{
    public class LatencyTests
    {
        static void Call(object target, string name, params object[] args) => target.GetType()
            .GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(target, args);
        static FieldInfo Field(string name) => typeof(LatencyMeasurementController)
            .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic);

        [TestCase(true, true, "ok", false)]
        [TestCase(false, true, "ok", false)]
        [TestCase(true, false, "no_arrow", false)]
        [TestCase(true, true, "invalid", true)]
        public void MetadataAndFrameOrderDoesNotChangeFirstWarning(bool metadataFirst, bool arrow, string expected, bool preexisting)
        {
            string directory = Path.Combine(Path.GetTempPath(), "latency-order-" + Guid.NewGuid().ToString("N"));
            var go = new GameObject("Latency ordering");
            try
            {
                var c = go.AddComponent<LatencyMeasurementController>(); c.measureLatency = true;
                var logger = new LatencyCsvLogger(directory); Field("logger").SetValue(c, logger);
                double now = ReceiveClock.Now;
                if (preexisting)
                {
                    c.ObservePresentation(122, now - .6, true, true);
                    Call(c, "RecordFrameEnd", now - .5);
                }
                var clock = (LatencyClock)Field("clock").GetValue(c);
                Assert.True(clock.Add("a", now - .2, now + 99.81, now + 99.81, now - .18));
                var json = new JObject { ["session"] = "a", ["trial_id"] = "1", ["t0"] = now + 98,
                    ["onset_method"] = "adc_mapped", ["invalid"] = "", ["timestamp_ms"] = 123,
                    ["inference_id"] = 7, ["t1"] = now + 99, ["t2"] = now + 99.5,
                    ["final_class"] = "siren", ["telemetry_dropped"] = 0 };
                void Metadata()
                {
                    Call(c, "Handle", new LatencyTelemetryClient.Message("result", json.ToString(), now));
                    var next = (JObject)json.DeepClone(); next["timestamp_ms"] = 124; next["inference_id"] = 8;
                    Call(c, "Handle", new LatencyTelemetryClient.Message("result", next.ToString(), now));
                }
                void Frame()
                {
                    c.ObservePresentation(123, now - .4, true, false, 98.1f);
                    Call(c, "RecordFrameEnd", now - .3);
                    c.ObservePresentation(124, now - .25, true, arrow, 99.3f);
                    Call(c, "RecordFrameEnd", now - .2);
                    // Later values must not overwrite the first warning/arrow's confidence.
                    c.ObservePresentation(124, now - .25, true, arrow, 97);
                    Call(c, "RecordFrameEnd", now - .1);
                }
                if (metadataFirst) { Metadata(); Frame(); } else { Frame(); Metadata(); }
                Metadata(); // duplicate side-channel delivery must not create another trial.
                Call(c, "Finish", "a:1", "");
                Call(c, "OnDisable");
                var lines = File.ReadAllLines(logger.Path);
                Assert.AreEqual(2, lines.Length);
                var columns = lines[1].Split(',');
                Assert.AreEqual("\"" + expected + "\"", columns[2]);
                Assert.AreEqual(lines[0].Split(',').Length, columns.Length);
                Assert.AreEqual("\"98.1\"", columns[25]);
                Assert.AreEqual(arrow ? "\"99.3\"" : "", columns[26]);
                if (preexisting) { Assert.AreEqual("", columns[16]); return; }
                Assert.That(double.Parse(columns[16].Trim('"'), System.Globalization.CultureInfo.InvariantCulture), Is.EqualTo(1.7).Within(.00001));
                if (arrow) Assert.That(double.Parse(columns[17].Trim('"'), System.Globalization.CultureInfo.InvariantCulture), Is.EqualTo(1.8).Within(.00001));
                else Assert.AreEqual("", columns[17]);
            }
            finally { UnityEngine.Object.DestroyImmediate(go); if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        }

        [Test]
        public void MissingResultAndMalformedMetadataCannotBecomeSuccessfulMeasurement()
        {
            string directory = Path.Combine(Path.GetTempPath(), "latency-missing-" + Guid.NewGuid().ToString("N"));
            var go = new GameObject("Latency missing");
            try
            {
                var c = go.AddComponent<LatencyMeasurementController>(); c.measureLatency = true;
                var logger = new LatencyCsvLogger(directory); Field("logger").SetValue(c, logger);
                Call(c, "Handle", new LatencyTelemetryClient.Message("result", "{broken", ReceiveClock.Now));
                Call(c, "Handle", new LatencyTelemetryClient.Message("event",
                    "{\"session\":\"a\",\"trial_id\":\"1\",\"t0\":100,\"onset_method\":\"adc_mapped\",\"invalid\":\"\"}", ReceiveClock.Now));
                Call(c, "Finish", "a:1", "");
                Call(c, "OnDisable");
                var columns = File.ReadAllLines(logger.Path)[1].Split(',');
                Assert.AreEqual("\"no_result_metadata\"", columns[2]);
                Assert.AreEqual("", columns[16]);
                Assert.AreEqual("", columns[25]);
                Assert.AreEqual("", columns[26]);
            }
            finally { UnityEngine.Object.DestroyImmediate(go); if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        }
        [Test]
        public void FourTimestampSyncCorrectsOffsetAndExpires()
        {
            var clock = new LatencyClock();
            Assert.True(clock.Add("a", 10, 110.01, 110.012, 10.022));
            Assert.True(clock.TryGet("a", 11, out var offset, out var rtt, out var age));
            Assert.That(offset, Is.EqualTo(100).Within(1e-9));
            Assert.That(rtt, Is.EqualTo(.02).Within(1e-9));
            Assert.That(age, Is.GreaterThan(0));
            Assert.False(clock.TryGet("a", 21, out _, out _, out _));
            Assert.False(clock.TryGet("other", 11, out _, out _, out _));
        }
        [Test]
        public void BadSyncAndRestartDoNotReuseOldClock()
        {
            var clock = new LatencyClock();
            Assert.False(clock.Add("a", 1, 10, 10, 2));
            Assert.False(clock.Add("a", 1, double.NaN, 10, 1.1));
            Assert.False(clock.Add("a", 1, 10, 9, 1.1));
            Assert.True(clock.Add("a", 1, 10.01, 10.01, 1.02));
            Assert.True(clock.Add("b", 2, 20.01, 20.01, 2.02));
            Assert.False(clock.TryGet("a", 3, out _, out _, out _));
            clock.Reset();
            Assert.False(clock.TryGet("b", 3, out _, out _, out _));
        }
        [Test]
        public void StageDurationsSumToTotalAcrossDifferentClockOrigins()
        {
            Assert.True(LatencyDurations.TryCalculate(100, 101, 101.1, 1.15, 1.17, 100, out var d));
            Assert.That(d.Detection, Is.EqualTo(1).Within(1e-9));
            Assert.That(d.SendWait, Is.EqualTo(.1).Within(1e-9));
            Assert.That(d.Transport, Is.EqualTo(.05).Within(1e-9));
            Assert.That(d.Unity, Is.EqualTo(.02).Within(1e-9));
            Assert.That(d.Total, Is.EqualTo(d.Detection + d.SendWait + d.Transport + d.Unity).Within(1e-9));
        }
        [Test]
        public void NegativeOrUnsynchronizedTimesAreNotReportedAsZero()
        {
            Assert.False(LatencyDurations.TryCalculate(100, 101, 101.1, 1, 1.2, 100, out _));
            Assert.False(LatencyDurations.TryCalculate(100, 101, 101.1, 1.15, 1.2, double.NaN, out _));
            Assert.False(LatencyDurations.TryCalculate(100, 99, 101.1, 1.15, 1.2, 100, out _));
        }
        [Test]
        public void CsvDrainsAndEscapesMissingValues()
        {
            string directory = Path.Combine(Path.GetTempPath(), "latency-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                var logger = new LatencyCsvLogger(directory);
                logger.Submit("trial", "quoted,\"text\"", double.NaN, null);
                logger.Dispose();
                Assert.IsNull(logger.Error);
                var lines = File.ReadAllLines(logger.Path);
                Assert.AreEqual(2, lines.Length);
                Assert.That(lines[1], Does.Contain("\"quoted,\"\"text\"\"\""));
                Assert.That(lines[1], Does.EndWith(",,"));
            }
            finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        }
        [Test]
        public void MeasurementDefaultsOffAndDoesNotCreateLogger()
        {
            var go = new GameObject("Latency off");
            try
            {
                var controller = go.AddComponent<LatencyMeasurementController>();
                Assert.False(controller.measureLatency);
                Assert.IsNull(controller.CsvPath);
                Assert.AreEqual("OFF", controller.Status);
            }
            finally { UnityEngine.Object.DestroyImmediate(go); }
        }
    }
}
