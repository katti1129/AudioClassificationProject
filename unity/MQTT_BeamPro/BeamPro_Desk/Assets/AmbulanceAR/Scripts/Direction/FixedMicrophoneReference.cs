using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR;

namespace AmbulanceAR
{
    // The microphone stays on the desk. Capture its forward axis once per XR session.
    public sealed class FixedMicrophoneReference : MonoBehaviour
    {
        [Min(1)] public float alignmentSeconds = 5;
        [Range(.5f, 10)] public float maximumDriftDegrees = 3;
        public bool IsCalibrated { get; private set; }
        public Quaternion WorldYaw { get; private set; } = Quaternion.identity;
        public float RemainingSeconds { get; private set; }
        bool waiting;
        double since;
        Quaternion candidate;
        readonly List<XRInputSubsystem> found = new List<XRInputSubsystem>();
        readonly List<XRInputSubsystem> observed = new List<XRInputSubsystem>();

        public void Sample(bool tracked, Vector3 headForward, double now, bool editorInstant = false)
        {
            found.Clear(); SubsystemManager.GetSubsystems(found);
            foreach (var subsystem in found)
                if (!observed.Contains(subsystem))
                { subsystem.trackingOriginUpdated += OriginChanged; observed.Add(subsystem); }
            if (!tracked || !AmbulanceDirectionController.TryYaw(headForward, out var yaw))
            { ResetCalibration(); return; }
            if (IsCalibrated) return; // Head motion must never rotate the fixed microphone frame.
            if (!waiting || Quaternion.Angle(candidate, yaw) > maximumDriftDegrees)
            { waiting = true; candidate = yaw; since = now; }
            RemainingSeconds = Mathf.Max(0, alignmentSeconds - (float)(now - since));
            if (editorInstant || RemainingSeconds <= 0)
            { WorldYaw = yaw; IsCalibrated = true; RemainingSeconds = 0; }
        }

        public void ResetCalibration()
        { IsCalibrated = waiting = false; WorldYaw = Quaternion.identity; RemainingSeconds = alignmentSeconds; }
        void OriginChanged(XRInputSubsystem _) => ResetCalibration();
        void OnDisable()
        {
            foreach (var subsystem in observed) subsystem.trackingOriginUpdated -= OriginChanged;
            observed.Clear(); ResetCalibration();
        }
    }
}
