using System;
using System.Collections;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using MQTTnet;
using MQTTnet.Server;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace AmbulanceAR.Tests
{
    public class LatencyLoopbackTests
    {
        static void Call(object target, string name, params object[] args) => target.GetType()
            .GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(target, args);
        static bool HasRow(string path)
        {
            if (!File.Exists(path)) return false;
            using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var reader = new StreamReader(file)) { reader.ReadLine(); return reader.ReadLine() != null; }
        }

        [UnityTest]
        public IEnumerator PythonStateAndSideChannelJoinToCsvThroughRealBroker()
        {
            var ancestor = new DirectoryInfo(Application.dataPath);
            while (ancestor != null && !Directory.Exists(Path.Combine(ancestor.FullName, "mqtt_xreal_system/Jetson_Final")))
                ancestor = ancestor.Parent;
            if (ancestor == null) Assert.Ignore("Run this test from a checkout of AudioClassificationProject.");
            string repo = ancestor.FullName;
            string python = Path.Combine(repo, "mqtt_xreal_system/Jetson_Final/.venv-latency/Scripts/python.exe");
            if (!File.Exists(python)) Assert.Ignore("Create Jetson_Final/.venv-latency with numpy and paho-mqtt for this cross-language test.");
            var reservation = new TcpListener(IPAddress.Loopback, 0); reservation.Start();
            int port = ((IPEndPoint)reservation.LocalEndpoint).Port; reservation.Stop();
            using (var server = new MqttFactory().CreateMqttServer(new MqttServerOptionsBuilder().WithDefaultEndpoint()
                .WithDefaultEndpointBoundIPAddress(IPAddress.Loopback).WithDefaultEndpointPort(port).Build()))
            {
                var start = server.StartAsync();
                while (!start.IsCompleted) yield return null;
                start.GetAwaiter().GetResult();
                var go = new GameObject("Latency loopback"); go.SetActive(false);
                System.Diagnostics.Process sender = null;
                string csv = null;
                try
                {
                    var subscriber = go.AddComponent<AmbulanceMqttSubscriber>();
                    subscriber.brokerHost = "127.0.0.1"; subscriber.brokerPort = port;
                    subscriber.topic = "test/latency/state"; subscriber.connectOnStart = false;
                    var measurement = go.AddComponent<LatencyMeasurementController>();
                    measurement.subscriber = subscriber; measurement.measureLatency = true; measurement.observationSeconds = 5;
                    go.SetActive(true);
                    Call(measurement, "OnEnable"); // EditMode does not invoke MonoBehaviour lifecycle automatically.
                    subscriber.Begin();
                    csv = measurement.CsvPath;
                    sender = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(python,
                        "-m mqtt_xreal_system.Jetson_Final.tests.latency_loopback_sender " + port)
                    { WorkingDirectory = repo, UseShellExecute = false, CreateNoWindow = true, WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden });
                    double deadline = ReceiveClock.Now + 20;
                    bool received = false;
                    while (ReceiveClock.Now < deadline)
                    {
                        Call(measurement, "Update");
                        while (subscriber.TryDequeue(out var packet))
                        {
                            Assert.True(AmbulanceState.TryParse(packet.Json, out var state));
                            received = true;
                            measurement.ObservePresentation(state.timestamp_ms, packet.ReceivedAt, true, false, state.confidence_pct);
                            // Explicit software frame boundary: EditMode/batch does not run WaitForEndOfFrame.
                            Call(measurement, "RecordFrameEnd", ReceiveClock.Now);
                            measurement.ObservePresentation(state.timestamp_ms, packet.ReceivedAt, true, true, state.confidence_pct);
                            Call(measurement, "RecordFrameEnd", ReceiveClock.Now + .001);
                        }
                        if (sender.HasExited && HasRow(csv)) break;
                        yield return null;
                    }
                    Assert.True(received, "Normal state topic should still reach the subscriber");
                    Assert.True(sender.HasExited, "Synthetic Python sender completed");
                    Assert.AreEqual(0, sender.ExitCode);
                    Assert.That(measurement.Status, Does.Contain("sync RTT"));
                    Call(measurement, "OnDisable"); // Drain CSV before reading.
                    var lines = File.ReadAllLines(csv);
                    Assert.AreEqual(2, lines.Length, "Exactly one onset trial; repeats must not duplicate it");
                    Assert.That(lines[1], Does.Contain("\"ok\""), lines[1]);
                    Assert.That(lines[1], Does.Not.Contain("NaN"));
                    var columns = lines[1].Split(',');
                    double warning = double.Parse(columns[16].Trim('"'), System.Globalization.CultureInfo.InvariantCulture);
                    double arrow = double.Parse(columns[17].Trim('"'), System.Globalization.CultureInfo.InvariantCulture);
                    Assert.Greater(warning, 0);
                    Assert.GreaterOrEqual(arrow, warning);
                    Assert.AreEqual("\"99\"", columns[25]);
                    Assert.AreEqual("\"99\"", columns[26]);
                }
                finally
                {
                    var measurement = go.GetComponent<LatencyMeasurementController>();
                    if (measurement) Call(measurement, "OnDisable");
                    UnityEngine.Object.DestroyImmediate(go);
                    if (sender != null) { if (!sender.HasExited) sender.Kill(); sender.Dispose(); }
                    // Keep the synthetic result in persistentDataPath for inspection.
                }
            }
        }
    }
}
