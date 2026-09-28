using TMPro;
using UnityEngine;

namespace AmbulanceAR
{
    public sealed class AmbulanceAlertView : MonoBehaviour
    {
        public GameObject warningRoot;
        public TMP_Text warningText;
        public TMP_Text connectionText;
        [Tooltip("Research debug only: raw DOA / confidence, hidden from wearer by default.")]
        public bool showDebugDetails;

        public void Present(AmbulanceState state, bool fresh, bool tracked, string connection)
        {
            connectionText.text = connection + (tracked ? "" : " | HEAD TRACKING UNAVAILABLE");
            bool detected = fresh && state != null && state.detected;
            warningRoot.SetActive(detected);
            if (!detected) return;
            string title = state.confidence_pct >= 80 ? "AMBULANCE" : "POSSIBLE AMBULANCE";
            warningText.color = AmbulanceArrowView.ConfidenceColor(state.confidence_pct);
            warningText.text = $"<b>{title}</b>\n<size=65%>SIREN DETECTED" +
                (state.doa_deg < 0 ? "  |  DIRECTION UNKNOWN" : "  |  CHECK ARROW DIRECTION") + "</size>";
            if (showDebugDetails)
                warningText.text += $"\n<size=55%>Confidence: {state.confidence_pct:F1}%  DOA: {state.doa_deg:F0} deg</size>";
        }
    }
}
