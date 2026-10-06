using System.Collections;
using NUnit.Framework;
using TMPro;
using UnityEngine;
using UnityEngine.TestTools;

namespace AmbulanceAR.Tests
{
    public class DisplayIntegrationTests
    {
        [UnityTest]
        public IEnumerator SimulationDrivesViewsForDetectionUnknownStaleAndHeadTurn()
        {
            var root = new GameObject("Display integration");
            try
            {
                var head = new GameObject("Head"); head.transform.SetParent(root.transform);
                var arrowObject = new GameObject("Arrow"); arrowObject.transform.SetParent(root.transform);
                var arrow = arrowObject.AddComponent<AmbulanceArrowView>(); arrow.arrowRenderer = arrowObject.AddComponent<MeshRenderer>();
                var hud = new GameObject("HUD"); hud.transform.SetParent(root.transform);
                var alert = hud.AddComponent<AmbulanceAlertView>();
                alert.warningRoot = new GameObject("Warning"); alert.warningRoot.transform.SetParent(hud.transform);
                alert.warningText = alert.warningRoot.AddComponent<TextMeshPro>();
                alert.connectionText = new GameObject("Connection").AddComponent<TextMeshPro>(); alert.connectionText.transform.SetParent(hud.transform);
                var system = root.AddComponent<AmbulanceSystemController>();
                system.subscriber = root.AddComponent<AmbulanceMqttSubscriber>();
                system.direction = root.AddComponent<AmbulanceDirectionController>(); system.direction.smoothingSeconds = 0;
                system.poses = root.AddComponent<HeadPoseHistory>(); system.poses.head = head.transform;
                system.arrow = arrow; system.alert = alert; system.editorSimulation = true;
                system.simulatedWorldBearing = 180;
                system.lockSimulatedWorldSource = false;
                system.simulatedRawDoa = 90; // Stationary desk mic, stationary source behind the starting view.
                void Tick() => system.ProcessFrame();
                Tick(); Assert.False(arrow.arrowRenderer.enabled); Assert.True(alert.warningRoot.activeSelf);
                Vector3 original = system.direction.WorldDirection;
                double wait = ReceiveClock.Now + .12; while (ReceiveClock.Now < wait) yield return null;
                system.simulatedHeadYaw = 180; Tick();
                Assert.That(Vector3.Distance(original, system.direction.WorldDirection), Is.LessThan(.001));
                Assert.True(arrow.arrowRenderer.enabled);
                Assert.AreEqual(90, system.simulatedRawDoa, "Turning the wearer must not change desk DOA");
                Assert.Greater(Vector3.Dot(head.transform.forward, system.direction.WorldDirection), .99);
                wait = ReceiveClock.Now + .12; while (ReceiveClock.Now < wait) yield return null;
                system.simulateUnknown = true; Tick(); Assert.False(arrow.arrowRenderer.enabled); Assert.True(alert.warningRoot.activeSelf);
                Assert.That(alert.warningText.text, Does.Contain("UNKNOWN"));
                wait = ReceiveClock.Now + .12; while (ReceiveClock.Now < wait) yield return null;
                system.simulatedDetected = false; Tick(); Assert.False(arrow.arrowRenderer.enabled); Assert.False(alert.warningRoot.activeSelf);
                wait = ReceiveClock.Now + .12; while (ReceiveClock.Now < wait) yield return null;
                system.simulatedDetected = true; system.simulateUnknown = false; Tick(); Assert.True(arrow.arrowRenderer.enabled);
                system.pauseSimulatedPackets = true;
                wait = ReceiveClock.Now + 1.6; while (ReceiveClock.Now < wait) yield return null;
                Tick(); Assert.False(arrow.arrowRenderer.enabled); Assert.False(alert.warningRoot.activeSelf);
                Assert.That(alert.connectionText.text, Does.Contain("STALE"));
                system.pauseSimulatedPackets = false;
                Tick(); Assert.True(arrow.arrowRenderer.enabled);
                // Switch to a disconnected real subscriber: stale simulation must not survive.
                system.subscriber.brokerHost = "127.0.0.1"; system.subscriber.brokerPort = 1;
                system.editorSimulation = false; Tick();
                Assert.False(arrow.arrowRenderer.enabled);
                Assert.False(alert.warningRoot.activeSelf);
                Assert.AreEqual(AcousticStatus.Unavailable, alert.DisplayedStatus);
            }
            finally { Object.DestroyImmediate(root); }
        }
    }
}
