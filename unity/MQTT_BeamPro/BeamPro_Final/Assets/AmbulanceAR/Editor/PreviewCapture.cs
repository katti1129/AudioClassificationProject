using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace AmbulanceAR.Editor
{
    public static class PreviewCapture
    {
        // Targeted migration: retain all scene objects, references and calibration values.
        [MenuItem("Ambulance AR/Move HUD above arrow and capture")]
        public static void AdjustHudAndCapture()
        {
            var scene = EditorSceneManager.OpenScene(AmbulanceProjectSetup.ScenePath);
            var alert = Object.FindFirstObjectByType<AmbulanceAlertView>();
            var rect = alert.GetComponent<RectTransform>();
            rect.anchoredPosition3D = new Vector3(0, .24f, 1.4f);
            EditorUtility.SetDirty(rect);
            Canvas.ForceUpdateCanvases();
            EditorSceneManager.MarkSceneDirty(scene);
            EditorSceneManager.SaveScene(scene);
            string path = AmbulanceProjectSetup.Root + "/Prefabs/AmbulanceHUD.prefab";
            var prefab = PrefabUtility.LoadPrefabContents(path);
            try
            {
                prefab.GetComponent<RectTransform>().anchoredPosition3D = new Vector3(0, .24f, 1.4f);
                PrefabUtility.SaveAsPrefabAsset(prefab, path);
            }
            finally { PrefabUtility.UnloadPrefabContents(prefab); }
            Capture();
        }

        // Renders the generated Unity scene offscreen. Never saves preview changes.
        [MenuItem("Ambulance AR/Capture reference preview")]
        public static void Capture()
        {
            EditorSceneManager.OpenScene(AmbulanceProjectSetup.ScenePath);
            var system = Object.FindFirstObjectByType<AmbulanceSystemController>();
            var camera = system.poses.head.GetComponent<Camera>();
            camera.transform.position = new Vector3(0, 1.6f, 0); camera.transform.rotation = Quaternion.identity;
            camera.backgroundColor = new Color(.025f, .045f, .065f);
            camera.fieldOfView = 55;
            var state = new AmbulanceState { detected = true, confidence_pct = 98, doa_deg = 250 };
            system.arrow.Present(true, camera.transform.position, Quaternion.Euler(0, 20, 0) * Vector3.forward, 98, 0);
            system.alert.Present(state, true, true, "UNITY PREVIEW / NOT DEVICE CAPTURE");
            Canvas.ForceUpdateCanvases();
            var target = new RenderTexture(1280, 720, 24);
            var image = new Texture2D(1280, 720, TextureFormat.RGB24, false);
            var previous = RenderTexture.active;
            try
            {
                camera.targetTexture = target; camera.Render(); RenderTexture.active = target;
                image.ReadPixels(new Rect(0, 0, 1280, 720), 0, 0); image.Apply();
                Directory.CreateDirectory("Artifacts"); File.WriteAllBytes("Artifacts/preview.png", image.EncodeToPNG());
            }
            finally { camera.targetTexture = null; RenderTexture.active = previous; Object.DestroyImmediate(target); Object.DestroyImmediate(image); }
            Debug.Log("AMBULANCE_PREVIEW_CAPTURED");
        }
    }
}
