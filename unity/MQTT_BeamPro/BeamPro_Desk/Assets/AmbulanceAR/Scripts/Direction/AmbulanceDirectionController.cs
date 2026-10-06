using UnityEngine;

namespace AmbulanceAR
{
    public sealed class AmbulanceDirectionController : MonoBehaviour
    {
        public bool invertDoa = true;
        public float doaOffsetDeg = 270;
        [Min(0)] public float smoothingSeconds = .12f;
        public Vector3 WorldDirection { get; private set; }
        public bool HasDirection { get; private set; }
        Vector3 target;

        public static float Normalize360(float angle) => (angle % 360 + 360) % 360;
        public static Vector3 ToWorld(float rawDoa, bool invert, float offset, Quaternion microphoneYaw)
        {
            float radians = Normalize360((invert ? -rawDoa : rawDoa) + offset) * Mathf.Deg2Rad;
            return microphoneYaw * new Vector3(Mathf.Sin(radians), 0, Mathf.Cos(radians));
        }
        public static bool TryYaw(Vector3 forward, out Quaternion yaw)
        {
            forward = Vector3.ProjectOnPlane(forward, Vector3.up);
            if (forward.sqrMagnitude < .0001f) { yaw = Quaternion.identity; return false; }
            yaw = Quaternion.LookRotation(forward.normalized, Vector3.up);
            return true;
        }
        public void Accept(float rawDoa, Quaternion microphoneYaw)
        {
            target = ToWorld(rawDoa, invertDoa, doaOffsetDeg, microphoneYaw);
            if (!HasDirection) WorldDirection = target;
            HasDirection = true;
        }
        public void Step(float deltaTime)
        {
            if (!HasDirection) return;
            float amount = smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-deltaTime / smoothingSeconds);
            // Quaternion slerp gives shortest circular motion, even at 359/1 or
            // antipodal 180 degrees; averaging opposite vectors could become zero.
            var rotation = Quaternion.Slerp(Quaternion.LookRotation(WorldDirection, Vector3.up),
                Quaternion.LookRotation(target, Vector3.up), amount);
            WorldDirection = rotation * Vector3.forward;
        }
        public void Clear() { HasDirection = false; }
    }
}
