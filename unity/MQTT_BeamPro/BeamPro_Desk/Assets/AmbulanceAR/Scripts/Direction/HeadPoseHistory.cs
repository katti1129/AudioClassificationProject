using UnityEngine;
using UnityEngine.XR;

namespace AmbulanceAR
{
    public sealed class HeadPoseHistory : MonoBehaviour
    {
        public Transform head;
        [Range(0, .3f)] public float poseLookbackSeconds;
        public bool Tracked { get; private set; }
        readonly double[] times = new double[256];
        readonly Quaternion[] yaws = new Quaternion[256];
        int next, count;
        public void Sample(double now, bool editorSimulation)
        {
            bool tracking = editorSimulation;
            if (!tracking)
            {
                var device = InputDevices.GetDeviceAtXRNode(XRNode.Head);
                tracking = device.isValid && device.TryGetFeatureValue(CommonUsages.isTracked, out bool valid) && valid &&
                    device.TryGetFeatureValue(CommonUsages.trackingState, out InputTrackingState flags) &&
                    (flags & (InputTrackingState.Position | InputTrackingState.Rotation)) == (InputTrackingState.Position | InputTrackingState.Rotation);
            }
            Tracked = head && tracking && AmbulanceDirectionController.TryYaw(head.forward, out _);
            if (!Tracked) { count = next = 0; return; }
            AmbulanceDirectionController.TryYaw(head.forward, out var yaw);
            times[next] = now;
            yaws[next] = yaw;
            next = (next + 1) % times.Length;
            count = Mathf.Min(count + 1, times.Length);
        }
        public bool TryAt(double receivedAt, out Quaternion yaw)
        {
            yaw = Quaternion.identity;
            if (!Tracked || count == 0) return false;
            double wanted = receivedAt - poseLookbackSeconds;
            int newest = (next - 1 + times.Length) % times.Length;
            for (int step = 0; step < count; step++)
            {
                int index = (newest - step + times.Length) % times.Length;
                if (times[index] <= wanted)
                {
                    yaw = yaws[index];
                    if (step > 0)
                    {
                        int later = (index + 1) % times.Length;
                        float amount = (float)((wanted - times[index]) / (times[later] - times[index]));
                        yaw = Quaternion.Slerp(yaws[index], yaws[later], amount);
                    }
                    return wanted - times[index] < .3;
                }
            }
            return false; // No historical pose: wait for next fresh message.
        }
    }
}
