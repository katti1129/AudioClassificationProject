using NUnit.Framework;
using TMPro;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;

namespace AmbulanceAR.Tests
{
    public class DeskMicrophoneTests
    {
        GameObject root;
        FixedMicrophoneReference reference;
        static Vector3 Forward(float yaw) => Quaternion.Euler(0, yaw, 0) * Vector3.forward;
        [SetUp] public void SetUp() { root = new GameObject("Desk reference"); reference = root.AddComponent<FixedMicrophoneReference>(); }
        [TearDown] public void TearDown() => Object.DestroyImmediate(root);

        [Test]
        public void CalibrationWaitsForStableTrackedForward()
        {
            reference.Sample(false, Forward(40), 0);
            Assert.False(reference.IsCalibrated);
            reference.Sample(true, Forward(40), 10);
            reference.Sample(true, Forward(41), 14.99);
            Assert.False(reference.IsCalibrated);
            reference.Sample(true, Forward(41), 15);
            Assert.True(reference.IsCalibrated);
            Assert.Less(Vector3.Distance(reference.WorldYaw * Vector3.forward, Forward(41)), .001);
        }

        [Test]
        public void MovingDuringAlignmentRestartsCountdown()
        {
            reference.Sample(true, Forward(0), 0);
            reference.Sample(true, Forward(10), 4);
            reference.Sample(true, Forward(10), 5);
            Assert.False(reference.IsCalibrated);
            reference.Sample(true, Forward(10), 9);
            Assert.True(reference.IsCalibrated);
        }

        [TestCase(0)] [TestCase(75)] [TestCase(359)]
        public void FixedRawBehindBecomesVisibleWhenOnlyHeadTurns(float micYaw)
        {
            reference.Sample(true, Forward(micYaw), 0, true);
            var direction = root.AddComponent<AmbulanceDirectionController>();
            direction.smoothingSeconds = 0;
            direction.Accept(90, reference.WorldYaw); direction.Step(1);
            var source = direction.WorldDirection;
            Assert.AreEqual(DirectionCue.Behind, SourceGuidance.Evaluate(source, Forward(micYaw), Forward(micYaw + 90), 25));
            reference.Sample(true, Forward(micYaw + 180), 1); // Same DOA, only the wearer moves.
            direction.Accept(90, reference.WorldYaw); direction.Step(1);
            Assert.Less(Vector3.Distance(source, direction.WorldDirection), .001);
            Assert.AreEqual(DirectionCue.None, SourceGuidance.Evaluate(direction.WorldDirection, Forward(micYaw + 180), Forward(micYaw + 270), 25));
        }

        [Test]
        public void MovingSourceStillUpdatesBearingInFixedMicFrame()
        {
            reference.Sample(true, Forward(30), 0, true);
            var front = AmbulanceDirectionController.ToWorld(270, true, 270, reference.WorldYaw);
            var right = AmbulanceDirectionController.ToWorld(180, true, 270, reference.WorldYaw);
            Assert.Less(Vector3.Distance(front, Forward(30)), .001);
            Assert.Less(Vector3.Distance(right, Forward(120)), .001);
        }

        [Test]
        public void TrackingLossAndResetRequireNewAlignment()
        {
            reference.Sample(true, Forward(20), 0, true);
            reference.Sample(false, Forward(20), 1);
            Assert.False(reference.IsCalibrated);
            reference.Sample(true, Forward(90), 2);
            Assert.False(reference.IsCalibrated);
            reference.Sample(true, Forward(90), 7);
            Assert.True(reference.IsCalibrated);
            Assert.Less(Vector3.Distance(reference.WorldYaw * Vector3.forward, Forward(90)), .001);
            reference.ResetCalibration();
            Assert.False(reference.IsCalibrated);
        }

        [Test]
        public void VerticalLookCannotCalibrateAndZeroCrossingIsStable()
        {
            reference.Sample(true, Vector3.up, 0, true);
            Assert.False(reference.IsCalibrated);
            reference.Sample(true, Forward(359), 0);
            reference.Sample(true, Forward(1), 5);
            Assert.True(reference.IsCalibrated);
        }

        [Test]
        public void SirenRemainsVisibleWhileCalibrationSuppressesGuidance()
        {
            var view = root.AddComponent<AmbulanceAlertView>();
            TMP_Text Text(string name)
            { var text = new GameObject(name).AddComponent<TextMeshPro>(); text.transform.SetParent(root.transform); return text; }
            view.warningText = Text("Warning"); view.warningRoot = view.warningText.gameObject;
            view.connectionText = Text("Connection"); view.guidanceText = Text("Guidance"); view.calibrationText = Text("Calibration");
            var state = new AmbulanceState { class_name = "siren", detected = true, doa_deg = 90 };
            view.Present(state, true, true, "live", DirectionCue.Behind, 0, false);
            view.PresentCalibration(reference, true);
            Assert.True(view.warningRoot.activeSelf);
            Assert.That(view.warningText.text, Does.Contain("CALIBRATION REQUIRED"));
            Assert.False(view.guidanceText.gameObject.activeSelf);
            Assert.True(view.calibrationText.gameObject.activeSelf);
            reference.Sample(true, Vector3.forward, 0, true);
            view.PresentCalibration(reference, true);
            Assert.False(view.calibrationText.gameObject.activeSelf);
        }

        [Test]
        public void DeskAppCanCoexistWithHeadMountedApp()
        {
            Assert.AreEqual("jp.research.ambulancear.desk", PlayerSettings.GetApplicationIdentifier(NamedBuildTarget.Android));
            Assert.AreEqual("Ambulance AR Desk", PlayerSettings.productName);
        }
    }
}
