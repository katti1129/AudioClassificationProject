using UnityEngine;
using UnityEngine.UI;

namespace AmbulanceAR
{
    // Geometry instead of font glyphs: the bundled font does not contain U+21BB.
    [RequireComponent(typeof(CanvasRenderer))]
    public sealed class HudDirectionIcon : MaskableGraphic
    {
        DirectionCue cue;
        public void Present(DirectionCue value, Color tint)
        {
            cue = value; color = tint;
            rectTransform.anchoredPosition = new Vector2(value == DirectionCue.Right ? 165 : -165, 0);
            SetVerticesDirty();
        }

        protected override void OnPopulateMesh(VertexHelper mesh)
        {
            mesh.Clear();
            void Triangle(Vector2 a, Vector2 b, Vector2 c)
            {
                int index = mesh.currentVertCount;
                mesh.AddVert(a, color, Vector2.zero); mesh.AddVert(b, color, Vector2.zero); mesh.AddVert(c, color, Vector2.zero);
                mesh.AddTriangle(index, index + 1, index + 2);
            }
            void Line(Vector2 a, Vector2 b)
            {
                var n = new Vector2(-(b - a).y, (b - a).x).normalized * 1.5f;
                Triangle(a - n, a + n, b + n); Triangle(a - n, b + n, b - n);
            }
            if (cue == DirectionCue.None) return;
            if (cue == DirectionCue.Behind)
            {
                Vector2 At(float angle) => new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * 10;
                for (int i = 0; i < 24; i++) Line(At((-40 - i * 11) * Mathf.Deg2Rad), At((-40 - (i + 1) * 11) * Mathf.Deg2Rad));
                Triangle(new Vector2(12, 4), new Vector2(0, 6), new Vector2(8, 15));
            }
            else
            {
                float sign = cue == DirectionCue.Right ? 1 : -1;
                Line(new Vector2(-12 * sign, 0), new Vector2(5 * sign, 0));
                Triangle(new Vector2(13 * sign, 0), new Vector2(3 * sign, 8), new Vector2(3 * sign, -8));
            }
        }
    }
}
