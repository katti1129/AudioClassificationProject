using System;
using NUnit.Framework;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace AmbulanceAR.Tests
{
    public class AmbulanceTests
    {
        static string Json(long timestamp = 100, bool detected = true, float doa = 270) =>
            JsonUtility.ToJson(new AmbulanceState { detected = detected, doa_deg = doa, confidence_pct = 98.1f,
                class_name = detected ? "siren" : "other", rms = .041f, inference_ms = 23.8f, timestamp_ms = timestamp });

        [TestCase(270, 0, 0, 1)] [TestCase(180, 0, 1, 0)]
        [TestCase(90, 0, 0, -1)] [TestCase(0, 0, -1, 0)]
        [TestCase(0, 90, 0, 1)] [TestCase(90, 180, 0, 1)]
        public void MicrophoneReferenceAndRawMapToWorld(float raw, float yaw, float x, float z)
        {
            var actual = AmbulanceDirectionController.ToWorld(raw, true, 270, Quaternion.Euler(0, yaw, 0));
            Assert.That(Vector3.Distance(actual, new Vector3(x, 0, z)), Is.LessThan(.0001));
        }
        [Test]
        public void PitchRollAreRemovedAndVerticalLookIsRejected()
        {
            Assert.True(AmbulanceDirectionController.TryYaw(Quaternion.Euler(40, 80, 30) * Vector3.forward, out var yaw));
            Assert.That(Vector3.Distance(yaw * Vector3.forward, Quaternion.Euler(0, 80, 0) * Vector3.forward), Is.LessThan(.0001));
            Assert.False(AmbulanceDirectionController.TryYaw(Vector3.up, out _));
        }
        [TestCase("{")] [TestCase("{}")] [TestCase("[]")] [TestCase("null")]
        [TestCase("{\"detected\":true,\"direction\":45,\"confidence\":0.9}")]
        public void MalformedOrLegacyJsonIsRejected(string value) => Assert.False(AmbulanceState.TryParse(value, out _));

        [Test]
        public void InvalidTypesRangesAndDuplicateKeysAreRejected()
        {
            string json = Json();
            string Mutate(string key, JToken value) { var obj = JObject.Parse(json); obj[key] = value; return obj.ToString(); }
            foreach (string invalid in new[] { json.Replace("\"version\":1", "\"version\":2"),
                json.Replace("\"detected\":true", "\"detected\":\"true\""),
                Mutate("confidence_pct", 101),
                Mutate("confidence_pct", double.NaN),
                json.Replace("\"version\":1", "\"version\":1,\"version\":1") })
                Assert.False(AmbulanceState.TryParse(invalid, out _), invalid);
        }
        [Test]
        public void OffAndUnknownAreValidButDoNotImplyKnownDirection()
        {
            Assert.True(AmbulanceState.TryParse(Json(detected: false), out var off)); Assert.False(off.detected);
            Assert.True(AmbulanceState.TryParse(Json(doa: -1), out var unknown)); Assert.True(unknown.detected); Assert.Less(unknown.doa_deg, 0);
        }
        [Test]
        public void StaleInvalidAndReplayDoNotRefreshAge()
        {
            var state = new StateFreshness(); Assert.False(state.Fresh(10, 1.5));
            Assert.True(state.Accept(Json(), 10)); Assert.True(state.Fresh(11.49, 1.5)); Assert.False(state.Fresh(11.5, 1.5));
            Assert.False(state.Accept("broken", 11.6)); Assert.False(state.Accept(Json(), 12)); Assert.False(state.Fresh(12, 1.5));
            state.Clear(); Assert.True(state.Accept(Json(timestamp: 1), 13)); Assert.True(state.Fresh(13, 1.5));
        }
        [Test]
        public void CircularSmoothingCrossesZeroAndHandlesOppositeDirections()
        {
            var go = new GameObject();
            try
            {
                var dir = go.AddComponent<AmbulanceDirectionController>(); dir.invertDoa = false; dir.doaOffsetDeg = 0;
                dir.Accept(359, Quaternion.identity); dir.Accept(1, Quaternion.identity); dir.Step(.12f);
                Assert.Greater(dir.WorldDirection.z, .99f);
                dir.Accept(180, Quaternion.identity); dir.Step(.12f);
                Assert.That(dir.WorldDirection.magnitude, Is.EqualTo(1).Within(.0001));
                dir.Clear(); Assert.False(dir.HasDirection);
            }
            finally { UnityEngine.Object.DestroyImmediate(go); }
        }
        [Test]
        public void ArrowIsHorizontalThreeDimensionalAndFollowsTranslation()
        {
            var go = new GameObject(); Mesh mesh = null;
            try
            {
                mesh = AmbulanceArrowView.CreateMesh(); Assert.Greater(mesh.bounds.size.y, .12f);
                Assert.Greater(mesh.bounds.size.z, 1); Assert.Greater(mesh.bounds.size.x, .7f);
                var view = go.AddComponent<AmbulanceArrowView>(); view.arrowRenderer = go.AddComponent<MeshRenderer>();
                Vector3 head = new Vector3(4, 1.6f, 3);
                view.Present(true, head, Vector3.back, 98, 0);
                Assert.That(Vector3.Distance(go.transform.position, head + Vector3.back * 1.8f + Vector3.down * .25f), Is.LessThan(.0001));
                Assert.That(Vector3.Dot(Vector3.ProjectOnPlane(go.transform.forward, Vector3.up).normalized, Vector3.back), Is.GreaterThan(.999f));
                Assert.That(go.transform.forward.y, Is.EqualTo(Mathf.Sin(35 * Mathf.Deg2Rad)).Within(.0001));
                view.Present(true, head, Vector3.back, 98, .5f); Assert.That(go.transform.localScale.x, Is.EqualTo(1.2f).Within(.0001));
                view.Present(false, head, Vector3.back, 98, 3); Assert.False(view.arrowRenderer.enabled);
            }
            finally { if (mesh) UnityEngine.Object.DestroyImmediate(mesh); UnityEngine.Object.DestroyImmediate(go); }
        }
        [Test]
        public void ConfidenceColorsChangeAtSpecifiedBoundaries()
        {
            Assert.AreEqual(AmbulanceArrowView.ConfidenceColor(0), AmbulanceArrowView.ConfidenceColor(49.9f));
            Assert.AreNotEqual(AmbulanceArrowView.ConfidenceColor(49.9f), AmbulanceArrowView.ConfidenceColor(50));
            Assert.AreNotEqual(AmbulanceArrowView.ConfidenceColor(79.9f), AmbulanceArrowView.ConfidenceColor(80));
        }
    }
}
