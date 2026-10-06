using UnityEngine;

namespace AmbulanceAR
{
    public enum AcousticStatus { Unavailable, Quiet, Sound, Siren }
    public enum DirectionCue { None, Left, Right, Behind }

    // Only quiet/ordinary sound transitions wait. Never hold an old siren warning.
    public sealed class AcousticStatusFilter
    {
        public AcousticStatus Current { get; private set; } = AcousticStatus.Unavailable;
        AcousticStatus candidate = AcousticStatus.Unavailable;
        double candidateSince;

        public static bool IsSiren(AmbulanceState state) =>
            state != null && state.class_name == "siren" && state.detected;

        public static AcousticStatus Classify(AmbulanceState state, bool fresh)
        {
            if (!fresh || state == null) return AcousticStatus.Unavailable;
            if (IsSiren(state)) return AcousticStatus.Siren;
            if (state.class_name == "silence") return AcousticStatus.Quiet;
            if (state.class_name == "other" || state.class_name == "siren") return AcousticStatus.Sound;
            return AcousticStatus.Unavailable;
        }

        public AcousticStatus Update(AmbulanceState state, bool fresh, double now, float stableSeconds)
        {
            var next = Classify(state, fresh);
            if (next == AcousticStatus.Siren || next == AcousticStatus.Unavailable)
            {
                Current = candidate = next;
                candidateSince = now;
                return Current;
            }
            if (Current == AcousticStatus.Siren) Current = AcousticStatus.Unavailable;
            if (candidate != next) { candidate = next; candidateSince = now; }
            if (now - candidateSince >= Mathf.Max(0, stableSeconds)) Current = candidate;
            return Current;
        }

        public void Reset() { Current = candidate = AcousticStatus.Unavailable; candidateSince = 0; }
    }

    public static class SourceGuidance
    {
        // Horizontal field of view; WorldDirection is already horizontal/yaw compensated.
        public static DirectionCue Evaluate(Vector3 worldDirection, Vector3 forward, Vector3 right, float halfAngle)
        {
            var direction = Vector3.ProjectOnPlane(worldDirection, Vector3.up).normalized;
            forward = Vector3.ProjectOnPlane(forward, Vector3.up).normalized;
            right = Vector3.ProjectOnPlane(right, Vector3.up).normalized;
            float front = Vector3.Dot(direction, forward);
            float side = Vector3.Dot(direction, right);
            float angle = Mathf.Atan2(side, front) * Mathf.Rad2Deg;
            if (Mathf.Abs(angle) <= Mathf.Clamp(halfAngle, 1, 89)) return DirectionCue.None;
            if (front < -.001f) return DirectionCue.Behind;
            return side < 0 ? DirectionCue.Left : DirectionCue.Right;
        }

        public static string Label(DirectionCue cue) => cue == DirectionCue.Left ? "← TURN LEFT" :
            cue == DirectionCue.Right ? "TURN RIGHT →" : cue == DirectionCue.Behind ? "↻ BEHIND YOU" : "";
    }
}
