using TMPro;
using UnityEngine;

namespace AmbulanceAR
{
    public sealed class AmbulanceAlertView : MonoBehaviour
    {
        public GameObject warningRoot;
        public TMP_Text warningText;
        public TMP_Text connectionText;
        public TMP_Text statusText;
        public TMP_Text guidanceText;
        public HudDirectionIcon guidanceIcon;
        [Min(0)] public float statusStableSeconds = .75f;
        public Color quietColor = new Color(.55f, .7f, .6f);
        public Color soundColor = new Color(.95f, .92f, .75f);
        public Color sirenColor = new Color(1, .22f, .12f);
        public Color unavailableColor = new Color(.6f, .65f, .7f);
        readonly AcousticStatusFilter filter = new AcousticStatusFilter();
        public AcousticStatus DisplayedStatus => filter.Current;
        [Tooltip("Research debug only: raw DOA / confidence, hidden from wearer by default.")]
        public bool showDebugDetails;

        public void ResetState() => filter.Reset();

        public void Present(AmbulanceState state, bool fresh, bool tracked, string connection,
            DirectionCue cue = DirectionCue.None, double now = -1)
        {
            connectionText.text = connection + (tracked ? "" : " | HEAD TRACKING UNAVAILABLE");
            var status = filter.Update(state, fresh, now < 0 ? ReceiveClock.Now : now, statusStableSeconds);
            bool detected = status == AcousticStatus.Siren;
            warningRoot.SetActive(detected);
            if (statusText)
            {
                statusText.gameObject.SetActive(!detected);
                statusText.text = status == AcousticStatus.Quiet ? "SURROUNDINGS QUIET" :
                    status == AcousticStatus.Sound ? "SOUND DETECTED" : "AUDIO STATUS UNAVAILABLE";
                statusText.color = status == AcousticStatus.Quiet ? quietColor :
                    status == AcousticStatus.Sound ? soundColor : unavailableColor;
            }
            if (guidanceText)
            {
                bool guide = detected && tracked && state.doa_deg >= 0 && cue != DirectionCue.None;
                guidanceText.gameObject.SetActive(guide);
                string label = guide ? SourceGuidance.Label(cue) : "";
                guidanceText.text = guidanceIcon ? label.Replace("←", "").Replace("→", "").Replace("↻", "").Trim() : label;
                guidanceText.color = sirenColor;
                if (guidanceIcon) guidanceIcon.Present(guide ? cue : DirectionCue.None, sirenColor);
            }
            if (!detected) return;
            warningText.color = sirenColor;
            warningText.text = "<b>AMBULANCE</b>\n<size=65%>SIREN DETECTED" +
                (state.doa_deg < 0 ? "  |  DIRECTION UNKNOWN" : !tracked ? "  |  HEAD TRACKING UNAVAILABLE" :
                    cue == DirectionCue.None ? "  |  CHECK ARROW DIRECTION" : "") + "</size>";
            if (showDebugDetails)
                warningText.text += $"\n<size=55%>Confidence: {state.confidence_pct:F1}%  DOA: {state.doa_deg:F0} deg</size>";
        }
    }
}
