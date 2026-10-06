# Beam Pro / XREAL Air 2 Ultra 完成版

`../BeamPro/` のAssets・Packages・ProjectSettingsを複製した独立プロジェクトです。Unity **6000.0.55f1** で開いてください。元プロジェクトへ変更を戻す必要はありません。

## Sceneと設定

`Assets/AmbulanceAR/Scenes/AmbulanceARScene.unity` を開きます。

```text
XR Origin / Camera Offset / Main Camera
  └── Ambulance HUD
Ambulance Arrow               ← カメラの子にしない
Ambulance System              ← MQTT / Direction / HeadPose / System
Arrow Key Light
```

生成済みのScene・Mesh・Material・Prefabがあります。再生成が必要な時は `Ambulance AR > 1. Configure Android and XREAL`、`2. Create final scene` を使用します。Sceneが存在すれば開くだけで、Inspectorの調整値を消しません。既存のMQTTテストSceneは残し、APKでは完成版Sceneだけを有効にしています。

Ambulance Systemを選択し、Broker HostをJetsonのLAN IPへ変更して保存してください。Broker Port、Topic、Stale Timeout、DOA Offset、Invert DOA、Direction Smoothing、Pose Lookback Secondsを調整できます。音響表示の設定と検証は [音響状態表示](AUDIO_STATUS.md) を参照してください。

HUDは警告・通常の音響状態・視野外の旋回案内を別要素で表示します。silenceはSURROUNDINGS QUIET、otherはSOUND DETECTED。両者は初期0.75秒の継続後に切り替わり、サイレン検知と通信無効への遷移は即時です。旧Sceneへ手動適用する場合は `Ambulance AR > Upgrade acoustic HUD` を使います。既存のBroker HostやDOA校正値は保持します。

## Editor Simulation

Play ModeではEditor Simulationが初期ON。画面左上のパネルでDetected、Confidence、Head Yaw、方向プリセット、Unknown、パケット停止を操作できます。Fixed world source ONなら頭を回すとRaw DOAも変わり、矢印は世界方向を維持します。Back→Yaw180°を試してください。

Siren detectedをOFFにすると、QuietのON/OFFでsilence/otherを試せます。視野外の音源はTURN LEFT / TURN RIGHT / BEHIND YOUで案内し、音源の方へ向いたら案内が消えてワールド矢印が現れます。判定はカメラの水平視野半角（初期25°）です。

Editor専用コードは `#if UNITY_EDITOR` に限定し、APKへ偽のDOAや頭部姿勢を持ち込みません。HUDの数値は `Show Debug Details` で表示できます。通常表示は救急車アイコン、英文警告、信頼度色です。

## XREAL / Android

埋込SDK：`Packages/com.xreal.xr`、ローカル提供の **3.0.0-pre.4**。現在の公開SDK3.1.0とは異なります。今回のPCでSDK導入を再度行う必要はありません。

- Android XR Loader：`Unity.XR.XREAL.XREALXRLoader`
- Initial Tracking Type：MODE_6DOF
- Support Devices：XREAL_DEVICE_CATEGORY_REALITY
- Input Source：None、手・平面・画像・永続アンカーは使用しない
- Support Multi Resume：OFF。設定メニューがSDKのActivity AAR直接ImportをOFFに補正し、重複クラス・不要なLauncherの混入を防ぐ
- Stereo：Single Pass Instanced
- OpenGL ES3、IL2CPP、ARM64、min API29、Internet permission
- Active Input Handling：Input System Package (New)
- Package ID：`jp.research.ambulancear.complete`（基準版を上書きしない）

XR OriginのカメラはInput System TrackedPoseDriverでXRHMDの位置・回転を取得します。DOA変換はその水平Yawを使用します。SDK自身の6DoFトラッキングと接続は実機で確認が必要です。

別環境で埋込SDKを外す場合や正式版へ更新する場合のみ：公式から取得したSDKをPackage ManagerでImportし、重複した同名パッケージを作らず置換します。`XR Plug-in Management > Android > XREAL` とProject Validation、6DoF/REALITYを確認し、再コンパイル・再テストしてください。既存SDKと最新SDKの同時配置はしません。

## APK

`Ambulance AR > 3. Build Beam Pro APK` で `Builds/AmbulanceAR.apk` を作成します。Android SDK / NDK / OpenJDKはUnity Hubから同バージョン用を使用してください。Development Buildです。署名鍵の新規作成や公開ストアへの配信は行いません。

2026-09-26にAPK生成成功（エラー0）。生成済みAPKのBroker Hostは `192.168.1.50` なので、JetsonのIPが異なる場合はSceneを変更・保存して再ビルドしてください。SDK由来の非推奨API／16KBページ対応警告と実機未確認事項は検証報告に記録しています。

```powershell
adb devices
adb install -r Builds/AmbulanceAR.apk
```

Beam ProでUSBデバッグを許可し、Jetsonと同じLANへ接続。Air 2 Ultraを接続し、MyGlasses内でAmbulance ARを起動します。OSが求める表示・カメラ関連権限を確認してください。実機ではMQTTが新鮮でも位置・回転追跡が無効なら矢印を隠します。

## テスト／資料

Test Runner > EditMode > AmbulanceAR.Tests。4方向、Yaw補償、円周平滑化、JSON、不明方向、stale、Mesh、表示制御、localhost MQTT再接続を検証します。従来の21件に音響状態と視野外案内の17件を追加し、2026-10-05に本体プロジェクトで38件成功、失敗0。保存済みSceneをPlay Modeへ移して実行する試験も含みます。今回のXMLは `Artifacts/audio-status-main-tests.xml`、ログは `Artifacts/audio-status-main-tests.log`。反映内容と実機未確認項目は [音響状態の表示仕様](AUDIO_STATUS.md) を参照してください。以前の21件の結果は `Artifacts/editmode-resumed.xml` に残しています。APK・Library・ビルドログはGitへ追加しません。

PC描画確認は `Ambulance AR > Capture reference preview`、状態別画像は `Capture acoustic states`。既存Sceneを保存せず `Artifacts/` にPNGを出力します。HUDは頭部より0.24m上、前方1.4m。矢印の初期値は水平距離1.8m、高さ−0.25m、傾き35°、1秒周期で1〜1.2倍です。実際のグラスでの大きさ・高さは校正時に調整してください。

全体：[入口README](../../../mqtt_xreal_system/README_MQTT_XREAL.md) / [キャリブレーション](../../../mqtt_xreal_system/docs/calibration.md) / [検証報告](../../../mqtt_xreal_system/docs/verification.md)
