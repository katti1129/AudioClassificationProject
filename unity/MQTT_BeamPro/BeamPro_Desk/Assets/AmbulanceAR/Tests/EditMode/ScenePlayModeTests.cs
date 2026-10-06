using System.Collections;
using NUnit.Framework;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.TestTools;

namespace AmbulanceAR.Tests
{
    public class ScenePlayModeTests
    {
        [UnityTest]
        public IEnumerator SavedSceneRunsSimulationThroughUnityLifecycle()
        {
            EditorSceneManager.OpenScene("Assets/AmbulanceAR/Scenes/AmbulanceARScene.unity");
            yield return new EnterPlayMode();
            yield return new WaitForSecondsRealtime(.25f);
            var system = Object.FindFirstObjectByType<AmbulanceSystemController>();
            Assert.NotNull(system);
            Assert.True(system.editorSimulation);
            Assert.True(system.arrow.arrowRenderer.enabled);
            Assert.True(system.alert.warningRoot.activeInHierarchy);
            Assert.NotNull(system.arrow.GetComponent<MeshFilter>().sharedMesh);
            Assert.IsNull(system.arrow.transform.parent);
            Assert.False(system.alert.showDebugDetails);
            Assert.That(system.alert.transform.localPosition.y, Is.GreaterThan(0));
            Assert.NotNull(system.alert.guidanceText.transform.Find("Direction Icon").GetComponent<CanvasRenderer>());

            system.simulatedHeadYaw = 90;
            yield return new WaitForSecondsRealtime(.25f);
            Assert.AreEqual(270, system.simulatedRawDoa, "Desk microphone does not rotate with the head");
            Assert.Greater(Vector3.Dot(system.direction.WorldDirection, Vector3.forward), .999f);
            Assert.False(system.arrow.arrowRenderer.enabled);
            Assert.That(system.alert.guidanceText.text, Does.Contain("TURN LEFT"));
            system.simulatedHeadYaw = 0;
            yield return new WaitForSecondsRealtime(.2f);
            Assert.False(system.alert.guidanceText.gameObject.activeSelf);
            Assert.True(system.arrow.arrowRenderer.enabled);
            system.lockSimulatedWorldSource = false;
            system.simulatedRawDoa = 90;
            yield return new WaitForSecondsRealtime(.7f);
            Assert.That(system.alert.guidanceText.text, Does.Contain("BEHIND YOU"));
            Assert.False(system.arrow.arrowRenderer.enabled);
            system.simulatedHeadYaw = 180;
            yield return new WaitForSecondsRealtime(.25f);
            Assert.AreEqual(90, system.simulatedRawDoa);
            Assert.True(system.arrow.arrowRenderer.enabled);
            Assert.False(system.alert.guidanceText.gameObject.activeSelf);
            system.simulateUnknown = true;
            yield return new WaitForSecondsRealtime(.2f);
            Assert.False(system.arrow.arrowRenderer.enabled);
            Assert.True(system.alert.warningRoot.activeInHierarchy);
            Assert.That(system.alert.warningText.text, Does.Contain("UNKNOWN"));
            system.simulatedDetected = false;
            yield return new WaitForSecondsRealtime(1.0f);
            Assert.False(system.alert.warningRoot.activeInHierarchy);
            Assert.False(system.arrow.arrowRenderer.enabled);
            Assert.AreEqual("SOUND DETECTED", system.alert.statusText.text);
            system.simulateSilence = true;
            yield return new WaitForSecondsRealtime(1.0f);
            Assert.AreEqual("SURROUNDINGS QUIET", system.alert.statusText.text);
            Assert.False(system.arrow.arrowRenderer.enabled);
            system.simulatedDetected = true;
            system.simulateUnknown = false;
            yield return new WaitForSecondsRealtime(.2f);
            Assert.True(system.arrow.arrowRenderer.enabled);
            system.pauseSimulatedPackets = true;
            yield return new WaitForSecondsRealtime(1.6f);
            Assert.False(system.arrow.arrowRenderer.enabled);
            Assert.False(system.alert.warningRoot.activeInHierarchy);
            Assert.AreEqual("AUDIO STATUS UNAVAILABLE", system.alert.statusText.text);
            yield return new ExitPlayMode();
        }

        [UnityTearDown]
        public IEnumerator LeavePlayMode()
        {
            if (Application.isPlaying) yield return new ExitPlayMode();
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        }
    }
}
