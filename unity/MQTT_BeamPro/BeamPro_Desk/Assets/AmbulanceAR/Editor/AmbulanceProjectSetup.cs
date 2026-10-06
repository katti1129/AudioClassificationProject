using System;
using System.IO;
using System.Linq;
using TMPro;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEditor.XR.Management;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.XR;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.UI;
using UnityEngine.XR.Management;
using Unity.XR.CoreUtils;
using Unity.XR.XREAL;

namespace AmbulanceAR.Editor
{
    public static class AmbulanceProjectSetup
    {
        public const string Root = "Assets/AmbulanceAR";
        public const string ScenePath = Root + "/Scenes/AmbulanceARScene.unity";

        [MenuItem("Ambulance AR/1. Configure Android and XREAL")]
        public static void Configure()
        {
            foreach (string folder in new[] { "Scenes", "Prefabs", "Materials", "Settings" }) Directory.CreateDirectory(Root + "/" + folder);
            AssetDatabase.Refresh();
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "jp.research.ambulancear.desk");
            PlayerSettings.productName = "Ambulance AR Desk";
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel29;
            PlayerSettings.Android.targetSdkVersion = AndroidSdkVersions.AndroidApiLevelAuto;
            PlayerSettings.Android.forceInternetPermission = true;
            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[] { GraphicsDeviceType.OpenGLES3 });
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.Portrait;
            PlayerSettings.SetMobileMTRendering(NamedBuildTarget.Android, false);
            PlayerSettings.runInBackground = true;
            QualitySettings.vSyncCount = 0;

            // These are optional Multi Resume AARs. The SDK's build processor copies
            // the matching Unity variant into Assets only when that feature is on.
            // Disable direct package imports to avoid duplicate classes/launchers.
            foreach (string name in new[] { "nractivitylife-release", "nractivitylife_6-release" })
            {
                string path = "Packages/com.xreal.xr/Runtime/Plugins/Android/" + name + ".aar";
                var plugin = AssetImporter.GetAtPath(path) as PluginImporter;
                if (!plugin) throw new BuildFailedException("Missing XREAL activity plugin: " + path);
                bool enabled = false;
                if (plugin.GetCompatibleWithAnyPlatform() || plugin.GetCompatibleWithEditor()
                    || plugin.GetCompatibleWithPlatform(BuildTarget.Android) != enabled)
                {
                    plugin.SetCompatibleWithAnyPlatform(false);
                    plugin.SetCompatibleWithEditor(false);
                    plugin.SetCompatibleWithPlatform(BuildTarget.Android, enabled);
                    plugin.SaveAndReimport();
                }
            }

            var perTarget = AssetDatabase.LoadAssetAtPath<XRGeneralSettingsPerBuildTarget>(Root + "/Settings/XRGeneralSettings.asset");
            if (!perTarget)
            {
                perTarget = ScriptableObject.CreateInstance<XRGeneralSettingsPerBuildTarget>();
                AssetDatabase.CreateAsset(perTarget, Root + "/Settings/XRGeneralSettings.asset");
            }
            EditorBuildSettings.AddConfigObject(XRGeneralSettings.k_SettingsKey, perTarget, true);
            if (!perTarget.HasManagerSettingsForBuildTarget(BuildTargetGroup.Android))
                perTarget.CreateDefaultManagerSettingsForBuildTarget(BuildTargetGroup.Android);
            var general = perTarget.SettingsForBuildTarget(BuildTargetGroup.Android);
            general.InitManagerOnStart = true;
            var manager = perTarget.ManagerSettingsForBuildTarget(BuildTargetGroup.Android);
            manager.automaticLoading = manager.automaticRunning = true;
            var loader = AssetDatabase.LoadAssetAtPath<XREALXRLoader>(Root + "/Settings/XREALLoader.asset");
            if (!loader) { loader = ScriptableObject.CreateInstance<XREALXRLoader>(); AssetDatabase.CreateAsset(loader, Root + "/Settings/XREALLoader.asset"); }
            manager.TrySetLoaders(new System.Collections.Generic.List<XRLoader> { loader });
            var settings = AssetDatabase.LoadAssetAtPath<XREALSettings>(Root + "/Settings/XREALSettings.asset");
            if (!settings) { settings = ScriptableObject.CreateInstance<XREALSettings>(); AssetDatabase.CreateAsset(settings, Root + "/Settings/XREALSettings.asset"); }
            settings.InitialTrackingType = TrackingType.MODE_6DOF;
            settings.SupportDevices = new System.Collections.Generic.List<XREALDeviceCategory> { XREALDeviceCategory.XREAL_DEVICE_CATEGORY_REALITY };
            settings.StereoRendering = StereoRenderingMode.SinglePassInstanced;
#if UNITY_ANDROID
            settings.InitialInputSource = InputSource.None;
            settings.SupportMultiResume = false;
            settings.AddtionalPermissions = new System.Collections.Generic.List<string> { "INTERNET", "CAMERA" };
#endif
            EditorBuildSettings.AddConfigObject(XREALSettings.k_SettingsKey, settings, true);
            foreach (var asset in new UnityEngine.Object[] { perTarget, general, manager, settings }) EditorUtility.SetDirty(asset);
            AssetDatabase.SaveAssets();
        }

        [MenuItem("Ambulance AR/2. Create final scene (only if absent)")]
        public static void CreateScene()
        {
            Configure();
            if (File.Exists(ScenePath)) { EditorSceneManager.OpenScene(ScenePath); return; }
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var origin = new GameObject("XR Origin").AddComponent<XROrigin>();
            var floor = new GameObject("Camera Offset"); floor.transform.SetParent(origin.transform, false);
            var headObject = new GameObject("Main Camera"); headObject.tag = "MainCamera"; headObject.transform.SetParent(floor.transform, false);
            var camera = headObject.AddComponent<Camera>(); camera.nearClipPlane = .05f; camera.farClipPlane = 100;
            camera.clearFlags = CameraClearFlags.SolidColor; camera.backgroundColor = Color.black;
            camera.GetUniversalAdditionalCameraData().renderPostProcessing = false;
            headObject.AddComponent<AudioListener>();
            origin.Camera = camera; origin.Origin = origin.gameObject; origin.CameraFloorOffsetObject = floor;
            origin.RequestedTrackingOriginMode = XROrigin.TrackingOriginMode.Device; origin.CameraYOffset = 0;
            var driver = headObject.AddComponent<TrackedPoseDriver>();
            driver.positionInput = new InputActionProperty(new InputAction("Head Position", InputActionType.Value, "<XRHMD>/centerEyePosition", expectedControlType: "Vector3"));
            driver.rotationInput = new InputActionProperty(new InputAction("Head Rotation", InputActionType.Value, "<XRHMD>/centerEyeRotation", expectedControlType: "Quaternion"));
            driver.trackingStateInput = new InputActionProperty(new InputAction("Head Tracking", InputActionType.Value, "<XRHMD>/trackingState", expectedControlType: "Integer"));

            var light = new GameObject("Arrow Key Light").AddComponent<Light>(); light.type = LightType.Directional;
            light.intensity = 1; light.transform.rotation = Quaternion.Euler(45, -30, 0);
            var mesh = AmbulanceArrowView.CreateMesh(); AssetDatabase.CreateAsset(mesh, Root + "/Materials/ArrowMesh.asset");
            var material = new Material(Shader.Find("Universal Render Pipeline/Lit")) { name = "Arrow Emissive URP" };
            material.EnableKeyword("_EMISSION"); material.SetColor("_EmissionColor", Color.red * .5f);
            material.SetFloat("_Smoothness", .45f); AssetDatabase.CreateAsset(material, Root + "/Materials/Arrow.mat");
            var arrowObject = new GameObject("Ambulance Arrow");
            arrowObject.AddComponent<MeshFilter>().sharedMesh = mesh;
            var meshRenderer = arrowObject.AddComponent<MeshRenderer>(); meshRenderer.sharedMaterial = material; meshRenderer.enabled = false;
            var arrow = arrowObject.AddComponent<AmbulanceArrowView>(); arrow.arrowRenderer = meshRenderer;
            PrefabUtility.SaveAsPrefabAsset(arrowObject, Root + "/Prefabs/AmbulanceArrow.prefab");

            var hudObject = new GameObject("Ambulance HUD", typeof(RectTransform), typeof(Canvas));
            hudObject.transform.SetParent(camera.transform, false);
            var canvas = hudObject.GetComponent<Canvas>(); canvas.renderMode = RenderMode.WorldSpace; canvas.worldCamera = camera;
            var rect = hudObject.GetComponent<RectTransform>(); rect.sizeDelta = new Vector2(900, 230);
            rect.localPosition = new Vector3(0, .24f, 1.4f); rect.localScale = Vector3.one * .001f;
            var alert = hudObject.AddComponent<AmbulanceAlertView>();
            var warning = new GameObject("Warning", typeof(RectTransform)); warning.transform.SetParent(hudObject.transform, false);
            warning.GetComponent<RectTransform>().sizeDelta = new Vector2(900, 150);
            var text = MakeText("Ambulance", warning.transform, new Vector2(820, 135), Vector2.zero, 40);
            // Ambulance silhouette built from simple UI rectangles and wheels.
            AddIcon(warning.transform);
            text.rectTransform.anchoredPosition = new Vector2(50, 0);
            alert.warningRoot = warning; alert.warningText = text;
            alert.connectionText = MakeText("Connection", hudObject.transform, new Vector2(900, 45), new Vector2(0, -96), 20);
            alert.connectionText.color = new Color(.65f, .75f, .8f);
            warning.SetActive(false);
            AudioStatusSceneUpgrade.ConfigureHud(alert);
            PrefabUtility.SaveAsPrefabAsset(hudObject, Root + "/Prefabs/AmbulanceHUD.prefab");

            var systemObject = new GameObject("Ambulance System");
            var subscriber = systemObject.AddComponent<AmbulanceMqttSubscriber>();
            var direction = systemObject.AddComponent<AmbulanceDirectionController>();
            var poses = systemObject.AddComponent<HeadPoseHistory>(); poses.head = camera.transform;
            var system = systemObject.AddComponent<AmbulanceSystemController>();
            system.microphone = systemObject.AddComponent<FixedMicrophoneReference>();
            system.subscriber = subscriber; system.direction = direction; system.poses = poses; system.arrow = arrow; system.alert = alert;
            EditorSceneManager.SaveScene(scene, ScenePath);
            // Preserve old scenes but only enable the new application scene for APK.
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) }
                .Concat(EditorBuildSettings.scenes.Where(s => s.path != ScenePath).Select(s => new EditorBuildSettingsScene(s.path, false))).ToArray();
            AssetDatabase.SaveAssets();
            Debug.Log("AMBULANCE_SETUP_COMPLETE " + ScenePath);
        }
        static TextMeshProUGUI MakeText(string name, Transform parent, Vector2 size, Vector2 position, float fontSize)
        {
            var text = new GameObject(name, typeof(RectTransform)).AddComponent<TextMeshProUGUI>();
            text.transform.SetParent(parent, false); text.rectTransform.sizeDelta = size; text.rectTransform.anchoredPosition = position;
            text.font = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>("Assets/TextMesh Pro/Resources/Fonts & Materials/LiberationSans SDF.asset");
            text.fontSize = fontSize; text.alignment = TextAlignmentOptions.Center; text.raycastTarget = false;
            return text;
        }
        static void AddIcon(Transform parent)
        {
            void Part(string name, float x, float y, float w, float h, Color color)
            {
                var image = new GameObject(name, typeof(RectTransform)).AddComponent<Image>(); image.transform.SetParent(parent, false);
                image.rectTransform.anchoredPosition = new Vector2(x - 370, y); image.rectTransform.sizeDelta = new Vector2(w, h); image.color = color; image.raycastTarget = false;
            }
            Part("Body", 0, 0, 58, 34, Color.white); Part("Cab", 37, -4, 22, 26, Color.white);
            Part("Window", 36, 0, 14, 11, Color.black); Part("Light", 0, 21, 18, 7, Color.red);
            Part("Cross vertical", 0, 0, 5, 20, Color.red); Part("Cross horizontal", 0, 0, 20, 5, Color.red);
            Part("Wheel left", -18, -21, 13, 10, Color.gray); Part("Wheel right", 35, -21, 13, 10, Color.gray);
        }

        [MenuItem("Ambulance AR/3. Build Beam Pro Desk APK")]
        public static void BuildApk()
        {
            if (!File.Exists(ScenePath)) CreateScene();
            Configure();
            Directory.CreateDirectory("Builds");
            var result = BuildPipeline.BuildPlayer(new BuildPlayerOptions { scenes = new[] { ScenePath },
                locationPathName = "Builds/AmbulanceAR_Desk.apk", target = BuildTarget.Android, options = BuildOptions.Development });
            Directory.CreateDirectory("Artifacts");
            File.WriteAllText("Artifacts/build-result.txt", $"{result.summary.result}\nErrors: {result.summary.totalErrors}\nWarnings: {result.summary.totalWarnings}\nBytes: {result.summary.totalSize}\n");
            if (result.summary.result != BuildResult.Succeeded) throw new BuildFailedException("Android build failed; see build log.");
        }
    }
}
