using TMPro;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace AmbulanceAR.Editor
{
    public static class AudioStatusSceneUpgrade
    {
        // Targeted, repeatable upgrade. Never recreate the scene or reset MQTT/calibration.
        [MenuItem("Ambulance AR/Upgrade acoustic HUD")]
        public static void Upgrade()
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            var scene = EditorSceneManager.OpenScene(AmbulanceProjectSetup.ScenePath);
            var system = Object.FindFirstObjectByType<AmbulanceSystemController>();
            ConfigureHud(system.alert);
            UpgradeArrow(system.arrow);
            EditorSceneManager.MarkSceneDirty(scene);
            EditorSceneManager.SaveScene(scene);
            foreach (string name in new[] { "AmbulanceHUD", "AmbulanceArrow" })
            {
                string path = AmbulanceProjectSetup.Root + "/Prefabs/" + name + ".prefab";
                var prefab = PrefabUtility.LoadPrefabContents(path);
                try
                {
                    if (name == "AmbulanceHUD") ConfigureHud(prefab.GetComponent<AmbulanceAlertView>());
                    else UpgradeArrow(prefab.GetComponent<AmbulanceArrowView>());
                    PrefabUtility.SaveAsPrefabAsset(prefab, path);
                }
                finally { PrefabUtility.UnloadPrefabContents(prefab); }
            }
            AssetDatabase.SaveAssets();
            Debug.Log("ACOUSTIC_HUD_UPGRADE_COMPLETE");
        }

        public static void ConfigureHud(AmbulanceAlertView alert)
        {
            TMP_Text Text(string name, Vector2 position, float size)
            {
                var child = alert.transform.Find(name);
                var text = child ? child.GetComponent<TMP_Text>() : null;
                if (text) return text;
                text = new GameObject(name, typeof(RectTransform)).AddComponent<TextMeshProUGUI>();
                text.transform.SetParent(alert.transform, false);
                text.font = alert.warningText.font;
                text.fontSize = size; text.alignment = TextAlignmentOptions.Center; text.raycastTarget = false;
                text.rectTransform.sizeDelta = new Vector2(850, 44);
                text.rectTransform.anchoredPosition = position;
                return text;
            }
            if (!alert.statusText) alert.statusText = Text("Acoustic Status", Vector2.zero, 26);
            if (!alert.guidanceText) alert.guidanceText = Text("Source Guidance", new Vector2(0, -82), 30);
            if (!alert.guidanceIcon)
            {
                alert.guidanceIcon = alert.guidanceText.GetComponentInChildren<HudDirectionIcon>(true);
                if (!alert.guidanceIcon)
                {
                    alert.guidanceIcon = new GameObject("Direction Icon", typeof(RectTransform)).AddComponent<HudDirectionIcon>();
                    alert.guidanceIcon.transform.SetParent(alert.guidanceText.transform, false);
                    alert.guidanceIcon.rectTransform.sizeDelta = new Vector2(32, 32);
                    alert.guidanceIcon.raycastTarget = false;
                }
            }
            if (!alert.guidanceIcon.GetComponent<CanvasRenderer>()) alert.guidanceIcon.gameObject.AddComponent<CanvasRenderer>();
            var connectionRect = alert.connectionText.rectTransform;
            if (Mathf.Approximately(connectionRect.anchoredPosition.y, -96) || Mathf.Approximately(connectionRect.anchoredPosition.y, -140))
                connectionRect.anchoredPosition = new Vector2(connectionRect.anchoredPosition.x, 95);
            alert.statusText.text = "AUDIO STATUS UNAVAILABLE";
            alert.statusText.color = alert.unavailableColor;
            alert.guidanceText.gameObject.SetActive(false);
            EditorUtility.SetDirty(alert);
        }

        static void UpgradeArrow(AmbulanceArrowView arrow)
        {
            // Replace only the old defaults, respecting independently adjusted fields.
            if (Mathf.Approximately(arrow.radius, 2.5f)) arrow.radius = 1.8f;
            if (Mathf.Approximately(arrow.heightOffset, -.55f)) arrow.heightOffset = -.25f;
            if (Mathf.Approximately(arrow.pulseScale, 1.1f)) arrow.pulseScale = 1.2f;
            if (Mathf.Approximately(arrow.pulseSeconds, 4)) arrow.pulseSeconds = 1;
            EditorUtility.SetDirty(arrow);
        }
    }
}
