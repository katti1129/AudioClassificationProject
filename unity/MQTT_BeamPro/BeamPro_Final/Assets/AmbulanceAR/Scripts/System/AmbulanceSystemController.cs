using UnityEngine;

namespace AmbulanceAR
{
    [DefaultExecutionOrder(100)]
    public sealed class AmbulanceSystemController : MonoBehaviour
    {
        public AmbulanceMqttSubscriber subscriber;
        public AmbulanceDirectionController direction;
        public HeadPoseHistory poses;
        public AmbulanceArrowView arrow;
        public AmbulanceAlertView alert;
        [Min(.1f)] public float staleTimeout = 1.5f;
        public StateFreshness State { get; } = new StateFreshness();
        int lastEpoch = -1;
        bool wasTracked;
#if UNITY_EDITOR
        public bool editorSimulation = true;
        public bool simulatedDetected = true;
        [Range(0, 359)] public float simulatedRawDoa = 270;
        [Range(0, 100)] public float simulatedConfidence = 98;
        [Range(-180, 180)] public float simulatedHeadYaw;
        public bool lockSimulatedWorldSource = true;
        [Range(0, 359)] public float simulatedWorldBearing;
        public bool simulateUnknown;
        public bool pauseSimulatedPackets;
        double nextSimulation;
        bool wasSimulation;
        long simulatedTimestamp;

        void Awake()
        {
            if (editorSimulation)
            {
                subscriber.connectOnStart = false;
                var driver = poses.head.GetComponent<UnityEngine.InputSystem.XR.TrackedPoseDriver>();
                if (driver) driver.enabled = false;
            }
        }
#endif
        void LateUpdate() => ProcessFrame();

        public void ProcessFrame()
        {
            double now = ReceiveClock.Now;
            bool simulation = false;
#if UNITY_EDITOR
            simulation = editorSimulation;
            if (simulation != wasSimulation)
            {
                State.Clear(); direction.Clear();
                var driver = poses.head.GetComponent<UnityEngine.InputSystem.XR.TrackedPoseDriver>();
                if (driver) driver.enabled = !simulation;
                if (!simulation) subscriber.Begin();
                wasSimulation = simulation;
            }
            if (simulation)
            {
                poses.head.localPosition = new Vector3(0, 1.6f, 0);
                poses.head.localRotation = Quaternion.Euler(0, simulatedHeadYaw, 0);
            }
#endif
            poses.Sample(now, simulation);
            if (!poses.Tracked || !wasTracked) direction.Clear();
            wasTracked = poses.Tracked;
            if (!simulation)
            {
                if (subscriber.Epoch != lastEpoch)
                { State.Clear(); direction.Clear(); lastEpoch = subscriber.Epoch; }
                while (subscriber.TryDequeue(out var packet))
                {
                    if (packet.Epoch != subscriber.Epoch || now - packet.ReceivedAt >= staleTimeout) continue;
                    if (State.Accept(packet.Json, packet.ReceivedAt)) ApplyDirection(packet.ReceivedAt);
                }
            }
#if UNITY_EDITOR
            else if (!pauseSimulatedPackets && now >= nextSimulation)
            {
                nextSimulation = now + .1;
                if (lockSimulatedWorldSource)
                {
                    float local = AmbulanceDirectionController.Normalize360(simulatedWorldBearing - simulatedHeadYaw);
                    float signed = local - direction.doaOffsetDeg;
                    simulatedRawDoa = AmbulanceDirectionController.Normalize360(direction.invertDoa ? -signed : signed);
                }
                var sample = new AmbulanceState { detected = simulatedDetected, class_name = simulatedDetected ? "siren" : "other",
                    confidence_pct = simulatedConfidence, doa_deg = simulateUnknown ? -1 : simulatedRawDoa,
                    rms = .041f, inference_ms = 23.8f, timestamp_ms = ++simulatedTimestamp };
                if (State.Accept(JsonUtility.ToJson(sample), now)) ApplyDirection(now);
            }
#endif
            bool connected = simulation || subscriber.Connected;
            bool fresh = connected && State.Fresh(now, staleTimeout);
            bool detected = fresh && State.Current.detected;
            if (!fresh || !detected) direction.Clear();
            direction.Step(Time.unscaledDeltaTime);
            arrow.Present(detected && poses.Tracked && direction.HasDirection, poses.head.position,
                direction.HasDirection ? direction.WorldDirection : Vector3.forward,
                State.Current?.confidence_pct ?? 0, Time.unscaledTime);
            string status = !connected ? subscriber.Status : fresh ? (simulation ? "EDITOR SIMULATION" : "MQTT: live") : "MQTT: STALE / waiting";
            alert.Present(State.Current, fresh, poses.Tracked, status);
        }
        void ApplyDirection(double receivedAt)
        {
            if (!State.Current.detected || State.Current.doa_deg < 0) { direction.Clear(); return; }
            if (poses.TryAt(receivedAt, out var yaw)) direction.Accept(State.Current.doa_deg, yaw);
            else direction.Clear();
        }
#if UNITY_EDITOR
        void OnGUI()
        {
            if (!editorSimulation) return;
            GUILayout.BeginArea(new Rect(12, 12, 290, 390), GUI.skin.box);
            GUILayout.Label("AMBULANCE / EDITOR SIMULATION");
            simulatedDetected = GUILayout.Toggle(simulatedDetected, "Siren detected");
            lockSimulatedWorldSource = GUILayout.Toggle(lockSimulatedWorldSource, "Fixed world source (DOA follows head)");
            GUILayout.Label($"Head Yaw: {simulatedHeadYaw:F0}");
            simulatedHeadYaw = GUILayout.HorizontalSlider(simulatedHeadYaw, -180, 180);
            GUILayout.Label($"Raw DOA: {simulatedRawDoa:F0}");
            if (!lockSimulatedWorldSource) simulatedRawDoa = GUILayout.HorizontalSlider(simulatedRawDoa, 0, 359);
            GUILayout.Label($"Confidence: {simulatedConfidence:F1}%");
            simulatedConfidence = GUILayout.HorizontalSlider(simulatedConfidence, 0, 100);
            GUILayout.BeginHorizontal();
            string[] names = { "Front", "Right", "Back", "Left" };
            float[] raw = { 270, 180, 90, 0 };
            for (int i = 0; i < names.Length; i++) if (GUILayout.Button(names[i]))
            { simulatedWorldBearing = i * 90; simulatedRawDoa = raw[i]; }
            GUILayout.EndHorizontal();
            simulateUnknown = GUILayout.Toggle(simulateUnknown, "Unknown DOA");
            pauseSimulatedPackets = GUILayout.Toggle(pauseSimulatedPackets, "Stop packets (stale after 1.5s)");
            alert.showDebugDetails = GUILayout.Toggle(alert.showDebugDetails, "Show HUD debug values");
            GUILayout.Label("Preset = world bearing when locked.\nTurn head to 180 to see a back source.");
            GUILayout.EndArea();
        }
#endif
    }
}
