using NUnit.Framework;
using TMPro;
using UnityEngine;

namespace AmbulanceAR.Tests
{
    public class AcousticPresentationTests
    {
        GameObject root;
        AmbulanceAlertView view;
        static AmbulanceState State(string name, bool detected = false, float doa = 270) =>
            new AmbulanceState { class_name = name, detected = detected, doa_deg = doa, confidence_pct = 98 };

        [SetUp]
        public void SetUp()
        {
            root = new GameObject("Acoustic view test");
            view = root.AddComponent<AmbulanceAlertView>();
            TMP_Text Text(string name)
            {
                var text = new GameObject(name).AddComponent<TextMeshPro>();
                text.transform.SetParent(root.transform); return text;
            }
            view.warningText = Text("Warning"); view.warningRoot = view.warningText.gameObject;
            view.statusText = Text("Status"); view.guidanceText = Text("Guidance"); view.connectionText = Text("Connection");
        }
        [TearDown] public void TearDown() => Object.DestroyImmediate(root);

        [TestCase("silence", "SURROUNDINGS QUIET")]
        [TestCase("other", "SOUND DETECTED")]
        public void AmbientStatusWaitsUntilStable(string name, string text)
        {
            var state = State(name);
            view.Present(state, true, true, "live", now: 10);
            Assert.AreEqual("AUDIO STATUS UNAVAILABLE", view.statusText.text);
            view.Present(state, true, true, "live", now: 10.74);
            Assert.AreEqual(AcousticStatus.Unavailable, view.DisplayedStatus);
            view.Present(state, true, true, "live", now: 10.75);
            Assert.AreEqual(text, view.statusText.text);
            Assert.False(view.warningRoot.activeSelf);
            Assert.False(view.guidanceText.gameObject.activeSelf);
            Assert.AreEqual(name == "silence" ? view.quietColor : view.soundColor, view.statusText.color);
        }

        [Test]
        public void BriefAlternationDoesNotFlickerAndSirenInterruptsImmediately()
        {
            view.Present(State("silence"), true, true, "live", now: 0);
            view.Present(State("silence"), true, true, "live", now: .75);
            view.Present(State("other"), true, true, "live", now: .8);
            view.Present(State("silence"), true, true, "live", now: 1.1);
            view.Present(State("other"), true, true, "live", now: 1.2);
            view.Present(State("other"), true, true, "live", now: 1.8);
            Assert.AreEqual(AcousticStatus.Quiet, view.DisplayedStatus);
            view.Present(State("siren", true), true, true, "live", now: 1.81);
            Assert.True(view.warningRoot.activeSelf);
            Assert.AreEqual(AcousticStatus.Siren, view.DisplayedStatus);
            Assert.AreEqual(view.sirenColor, view.warningText.color);
            view.Present(State("other"), true, true, "live", now: 1.82);
            Assert.False(view.warningRoot.activeSelf, "Do not retain a cleared siren during debounce");
        }

        [TestCase("silence", true, AcousticStatus.Quiet)]
        [TestCase("other", true, AcousticStatus.Sound)]
        [TestCase("siren", false, AcousticStatus.Sound)]
        [TestCase("siren", true, AcousticStatus.Siren)]
        [TestCase("unrecognized", true, AcousticStatus.Unavailable)]
        public void ClassAndDetectionMustAgreeForSiren(string name, bool detected, AcousticStatus expected)
        {
            Assert.AreEqual(expected, AcousticStatusFilter.Classify(State(name, detected), true));
            Assert.AreEqual(expected == AcousticStatus.Siren, AcousticStatusFilter.IsSiren(State(name, detected)));
        }

        [TestCase(-70, DirectionCue.Left, "TURN LEFT")]
        [TestCase(70, DirectionCue.Right, "TURN RIGHT")]
        [TestCase(180, DirectionCue.Behind, "BEHIND YOU")]
        [TestCase(-140, DirectionCue.Behind, "BEHIND YOU")]
        public void OffscreenSourceUsesHeadRelativeHud(float bearing, DirectionCue expected, string text)
        {
            var direction = Quaternion.Euler(0, bearing, 0) * Vector3.forward;
            var cue = SourceGuidance.Evaluate(direction, Vector3.forward, Vector3.right, 25);
            Assert.AreEqual(expected, cue);
            view.Present(State("siren", true), true, true, "live", cue, 0);
            Assert.True(view.guidanceText.gameObject.activeSelf);
            Assert.That(view.guidanceText.text, Does.Contain(text));
            var head = Quaternion.Euler(0, bearing, 0);
            cue = SourceGuidance.Evaluate(direction, head * Vector3.forward, head * Vector3.right, 25);
            Assert.AreEqual(DirectionCue.None, cue);
            view.Present(State("siren", true), true, true, "live", cue, .1);
            Assert.False(view.guidanceText.gameObject.activeSelf);
        }

        [Test]
        public void VisibilityAngleIsAdjustableAndCrossesZeroContinuously()
        {
            var direction = Quaternion.Euler(0, 30, 0) * Vector3.forward;
            Assert.AreEqual(DirectionCue.Right, SourceGuidance.Evaluate(direction, Vector3.forward, Vector3.right, 25));
            Assert.AreEqual(DirectionCue.None, SourceGuidance.Evaluate(direction, Vector3.forward, Vector3.right, 35));
            var head = Quaternion.Euler(0, 359, 0);
            Assert.AreEqual(DirectionCue.None, SourceGuidance.Evaluate(Quaternion.Euler(0, 1, 0) * Vector3.forward,
                head * Vector3.forward, head * Vector3.right, 25));
        }

        [Test]
        public void UnknownAndUntrackedNeverShowGuidance()
        {
            view.Present(State("siren", true, -1), true, true, "live", DirectionCue.Behind, 0);
            Assert.True(view.warningRoot.activeSelf);
            Assert.That(view.warningText.text, Does.Contain("DIRECTION UNKNOWN"));
            Assert.False(view.guidanceText.gameObject.activeSelf);
            view.Present(State("siren", true), true, false, "live", DirectionCue.Left, .1);
            Assert.False(view.guidanceText.gameObject.activeSelf);
        }

        [TestCase("MQTT: STALE / waiting")]
        [TestCase("MQTT: disconnected")]
        public void UnavailableImmediatelyClearsWarningAndGuidance(string connection)
        {
            view.Present(State("siren", true), true, true, "live", DirectionCue.Right, 0);
            view.Present(State("siren", true), false, true, connection, DirectionCue.Right, .01);
            Assert.False(view.warningRoot.activeSelf);
            Assert.False(view.guidanceText.gameObject.activeSelf);
            Assert.AreEqual("AUDIO STATUS UNAVAILABLE", view.statusText.text);
            Assert.AreEqual(view.unavailableColor, view.statusText.color);
        }

        [Test]
        public void ArrowColorEmissionScaleAndTiltAreConfigurable()
        {
            var arrowObject = new GameObject("Arrow"); arrowObject.transform.SetParent(root.transform);
            var arrow = arrowObject.AddComponent<AmbulanceArrowView>(); arrow.arrowRenderer = arrowObject.AddComponent<MeshRenderer>();
            arrow.radius = 2; arrow.heightOffset = -.1f; arrow.tiltDegrees = 45; arrow.baseScale = 1.5f;
            arrow.highConfidenceColor = Color.magenta; arrow.emissionIntensity = 2;
            arrow.Present(true, Vector3.zero, Vector3.forward, 99, .5f);
            Assert.That(arrow.transform.position, Is.EqualTo(new Vector3(0, -.1f, 2)));
            Assert.That(arrow.transform.localScale.x, Is.EqualTo(1.8f).Within(.001));
            Assert.That(arrow.transform.forward.y, Is.EqualTo(Mathf.Sin(45 * Mathf.Deg2Rad)).Within(.001));
            var properties = new MaterialPropertyBlock(); arrow.arrowRenderer.GetPropertyBlock(properties);
            Assert.AreEqual(Color.magenta, properties.GetColor("_BaseColor"));
            Assert.AreEqual(Color.magenta * 2, properties.GetColor("_EmissionColor"));
        }
    }
}
