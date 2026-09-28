using System.Collections.Generic;
using UnityEngine;

namespace AmbulanceAR
{
    public sealed class AmbulanceArrowView : MonoBehaviour
    {
        [Min(.3f)] public float radius = 2.5f;
        public float heightOffset = -.55f;
        [Range(1, 1.2f)] public float pulseScale = 1.1f;
        [Min(.1f)] public float pulseSeconds = 4;
        public MeshRenderer arrowRenderer;
        MaterialPropertyBlock properties;
        public static Color ConfidenceColor(float percent) => percent >= 80 ? new Color32(255, 85, 79, 255) :
            percent >= 50 ? new Color32(255, 196, 79, 255) : new Color32(180, 193, 207, 255);

        public void Present(bool visible, Vector3 headPosition, Vector3 worldDirection, float confidence, float time)
        {
            arrowRenderer.enabled = visible;
            if (!visible) return;
            transform.position = headPosition + worldDirection * radius + Vector3.up * heightOffset;
            // Mesh tip is local +Z. World +Y is up; no pitch/roll or unexplained corrections.
            transform.rotation = Quaternion.LookRotation(worldDirection, Vector3.up);
            float pulse = 1 + (pulseScale - 1) * .5f * (1 - Mathf.Cos(time * 2 * Mathf.PI / Mathf.Max(.1f, pulseSeconds)));
            transform.localScale = Vector3.one * pulse;
            if (properties == null) properties = new MaterialPropertyBlock();
            Color color = ConfidenceColor(confidence);
            properties.SetColor("_BaseColor", color);
            properties.SetColor("_EmissionColor", color * .5f);
            arrowRenderer.SetPropertyBlock(properties);
        }

        public static Mesh CreateMesh()
        {
            // A flat extruded arrow in XZ, 0.13 m thick, +Z tip. Top-view outline
            // matches the web mock (0.74 m wide, 1.03 m long). Flat normals keep
            // the side thickness legible. No external mesh or texture asset.
            Vector2[] outline = { new Vector2(-.14f, -.48f), new Vector2(.14f, -.48f),
                new Vector2(.14f, .05f), new Vector2(.37f, .05f), new Vector2(0, .55f),
                new Vector2(-.37f, .05f), new Vector2(-.14f, .05f) };
            int[] face = { 0, 1, 2, 0, 2, 6, 6, 2, 4, 2, 3, 4, 6, 4, 5 };
            var vertices = new List<Vector3>();
            var triangles = new List<int>();
            void Triangle(Vector3 a, Vector3 b, Vector3 c)
            { int n = vertices.Count; vertices.Add(a); vertices.Add(b); vertices.Add(c); triangles.Add(n); triangles.Add(n + 1); triangles.Add(n + 2); }
            Vector3 Point(int index, float y) => new Vector3(outline[index].x, y, outline[index].y);
            for (int i = 0; i < face.Length; i += 3)
            {
                Triangle(Point(face[i], .065f), Point(face[i + 2], .065f), Point(face[i + 1], .065f));
                Triangle(Point(face[i], -.065f), Point(face[i + 1], -.065f), Point(face[i + 2], -.065f));
            }
            for (int i = 0; i < outline.Length; i++)
            {
                int j = (i + 1) % outline.Length;
                Triangle(Point(i, -.065f), Point(j, .065f), Point(j, -.065f));
                Triangle(Point(i, -.065f), Point(i, .065f), Point(j, .065f));
            }
            var mesh = new Mesh { name = "HorizontalAmbulanceArrow" };
            mesh.SetVertices(vertices); mesh.SetTriangles(triangles, 0); mesh.RecalculateNormals(); mesh.RecalculateBounds();
            return mesh;
        }
    }
}
