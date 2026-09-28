# 検証報告

検証日：2026-09-26。対象はJetson_FinalとBeamPro_Final。実機検証とPC上の自動検証を区別する。

## 再開時に引き継いだもの

Scene、Mesh、Material、Arrow/HUD Prefab、XREAL設定、C#、Jetson統合、ドキュメントは作業ツリーに存在した。再生成せず内容を確認した。

保存済み `BeamPro_Final/Artifacts/editmode.xml` は20件Passed / 0 failed（UTC 2026-09-25 18:23:03開始）。コードと照合すると、方向変換、円周平滑化、JSON、Mesh、表示状態、実TCP MQTTの再接続を含んでいた。Jetson側10テストも実行成功済み。これらは再開前の成果として扱う。

## 確認済み

| 検証 | 結果・範囲 |
| --- | --- |
| Jetson Python | 既存10テストを再開後も再実行し成功。decision、state relay、CSV、Paho呼出しを検証。Pahoクライアントはモック |
| Python構文 | app / config / mqtt / telemetryのcompileall成功 |
| 起動CLI | `--help` 成功。重いMLライブラリなしでも設定説明を表示 |
| Unity C# | Unity 6000.0.55f1、AndroidターゲットのEditorコンパイル成功 |
| EditMode | 再開後21件成功、失敗0。既存20件＋保存済みSceneのPlay Mode試験1件 |
| MQTT実通信 | localhostのMQTTnet Brokerと製品SubscriberがTCP接続・Subscribe・受信 |
| 再接続 | Broker停止時に切断、再起動後に自動再接続・再Subscribe・新規メッセージ受信 |
| JSON | 不正JSON、型／値／版／重複キー、旧簡易JSONを拒否。実TCPでも不正JSONを受信し、状態を更新せず接続を維持することを確認 |
| 状態表示 | 検知ON→矢印/HUD、OFF→両方非表示、Unknown→HUDのみ、1.5秒期限超→両方非表示 |
| DOA | raw270/180/90/0→正面/右/後/左、Yaw0/raw270とYaw90/raw0が同じ世界方向 |
| 円周データ | 359/1を最短回転で平滑化。180反転でもゼロ方向にならない |
| Editor Simulation | 既存ProcessFrame試験に加え、保存済みSceneを実際にPlay Modeへ移し、Awake/Start/LateUpdate経由で表示・Yaw90の世界方向保持・Unknown/OFF/staleを確認 |
| Mesh | 厚さ0.13mの実Mesh、半径2.5m、頭部基準高さ−0.55m、Pulse1〜1.1 |
| 信頼度 | 50/80%境界の色切替、通常HUDの数値非表示・研究用表示切替コード |
| 参照版保護 | 保存済み185ファイルのSHA256一致 |

Jetsonの推論／USB／GUIをこのWindows PCで実行した結果ではない。EditModeの表示制御試験は実際のAir 2 Ultraの光学像やトラッキングを検証するものではない。

## 再開後の仕上げ

- Git差分、実ファイル、Sceneのシリアライズ値、XREAL設定、保存済みテストXMLを照合。
- IL2CPPでJSONから復元する `AmbulanceState` の全メンバーを維持するlink.xmlを追加。
- Unityのオフスクリーン描画で実MeshとHUDを確認。文字と矢印が重なっていたため、既存SceneとHUD Prefabの位置だけを頭部基準 `(0, 0.24, 1.4)` mへ変更。再描画で解消を確認。`Artifacts/preview.png` はPC描画であり、グラスの実写ではない。
- `ScenePlayModeTests.cs` を追加し、実SceneのUnityライフサイクルを検証。既存テストを含め21件成功。保存先：`Artifacts/editmode-resumed.xml`、`tests-resumed.log`。
- AndroidビルドでアプリID末尾 `final` がJava予約語として拒否されたため、`jp.research.ambulancear.complete` へ修正。
- SDK提供の旧Unity用／Unity 6用Activity AARが共に有効で、Javaクラスが重複していた。片方だけ含めても、Multi Resume OFFに対して不要な別Launcherが混入することを生成Manifestで確認。両AARの直接ImportをOFFにし、SDK自身が必要時のみ適切な版をコピーする方式へ合わせた。完成版は既存どおりMulti Resume OFF。SDKソース／バイナリは変更せず、完成版内のImportメタデータと設定処理のみ修正。
- Androidビルド警告に従い、Active Input HandlingをBothからInput System Package (New)へ変更。XREAL頭部姿勢は既存どおり新Input SystemのTrackedPoseDriverで取得。
- Android APKビルド成功。Unity BuildReport：Succeeded / Errors 0 / Warnings 6。残る警告はSDK内の非推奨APIと16KBアラインメントに関するもの。入力Bothの警告は解消。

### APKと証拠ファイル

`unity/MQTT_BeamPro/BeamPro_Final/` 基準：

| ファイル | 内容 |
| --- | --- |
| `Builds/AmbulanceAR.apk` | ARM64 / IL2CPP / Development、215,798,025 bytes |
| `Artifacts/build-result.txt` | Unity BuildReport要約。Bytesはビルド全体の報告値で、APKサイズとは異なる |
| `android-build-final.log` | 最終APKのUnity/IL2CPP/Gradleログ |
| `Artifacts/editmode.xml` | 再開前の20件成功の記録 |
| `Artifacts/editmode-resumed.xml` | 再開後21件の最終結果 |
| `tests-resumed.log` | 再開後のテスト実行ログ |
| `Artifacts/preview.png` | HUD修正後のPC描画 |

APK SHA256：`73440DC05775A7F95AA17B9AC4CEF4F626EEB170833F2B851CAFD19AEBBC4F5C`。

`aapt dump badging` でpackage `jp.research.ambulancear.complete`、min API29、target API36、ABI `arm64-v8a`、単一の起動Activityを確認。生成Manifestにも `nreal_sdk`、REALITY対応情報、INTERNET / CAMERA権限が存在し、不要なMulti Resume起動口がない。Broker Hostは例の `192.168.1.50` のままなので、異なるLANではSceneの接続先を変更し再ビルドする。

既存正常版185ファイルのSHA256一致。提供SDKとの比較でも差分は上記2つのAARの.metaのみ。各README／技術資料のローカルリンク先はすべて存在する。

### 再開後に変更・追加したファイル

Unity側はすべて `unity/MQTT_BeamPro/BeamPro_Final/` 内：

- `Assets/AmbulanceAR/Editor/AmbulanceProjectSetup.cs`：AndroidアプリID、SDK AARのImport設定、HUD初期位置。
- `Assets/AmbulanceAR/Editor/PreviewCapture.cs`：既存Scene／PrefabのHUD位置を保存する限定的な調整処理。
- `Assets/AmbulanceAR/Scenes/AmbulanceARScene.unity`、`Assets/AmbulanceAR/Prefabs/AmbulanceHUD.prefab`：HUD位置。
- `Assets/AmbulanceAR/link.xml`（およびUnity生成.meta）：状態型のIL2CPP保持。
- `Assets/AmbulanceAR/Tests/EditMode/ScenePlayModeTests.cs`（およびUnity生成.meta）：保存済みSceneの実Play Mode試験を追加。
- `Assets/AmbulanceAR/Tests/EditMode/MqttLoopbackTests.cs`：不正JSONの実TCP受信試験を追加。
- `ProjectSettings/ProjectSettings.asset`：アプリIDと新Input System設定。
- `Packages/com.xreal.xr/Runtime/Plugins/Android/nractivitylife-release.aar.meta`、`nractivitylife_6-release.aar.meta`：任意機能AARの直接ImportをOFF。
- `README.md`：現在の設定・APK・テスト・残る制約。

資料：`mqtt_xreal_system/README_MQTT_XREAL.md`、`Jetson_Final/README.md`、`docs/system_architecture.md`、`docs/mqtt_protocol.md`、`docs/calibration.md`、`docs/verification.md`（本ファイルを追加）。ログ、XML、PNG、APKは生成物としてGit対象外。Jetsonの実装コード、Mesh、Arrow Prefab、方向変換コードは再開後に変更していない。

## 実機で残る確認

ADB一覧に接続端末なし。Beam ProへのAPK導入、MyGlasses起動、Air 2 Ultraでの6DoF、ReSpeaker実音声・CRNN、Jetson Mosquitto＋Wi-Fi経由の総合確認は未実施。

特に、マイクの向き・左右符号、DOAと頭部姿勢の時間差、追跡喪失と回復、光学視野内の大きさ・高さ、信頼度色と文字の視認性を確認する。SDKはローカル提供3.0.0-pre.4であり、公開版3.1.0の実機互換性検証を行ったとは扱わない。

提供SDKの `libXREALXRPlugin.so` と `libmedia_codec.so` に16KBアラインメント警告がある。SDKバイナリを改造して回避していない。端末OSとページサイズ（`adb shell getconf PAGE_SIZE`）を記録し、16KBページの端末では対応SDKへの更新と再検証が必要。公式サイトにも[Android 16互換性調査中の告知](https://docs.xreal.com/Getting%20Started%20with%20XREAL%20SDK)がある。今回のAPKはmin API29 / target API36だが、これはAndroid 16実機の動作確認を意味しない。

## 再現方法

Jetson側（リポジトリルート、paho-mqtt導入済み環境）：

```bash
python -m unittest discover -s mqtt_xreal_system/Jetson_Final/tests -p 'test_*.py' -v
python mqtt_xreal_system/docs/verify_reference_files.py
```

Unity EditMode（Windows PowerShell）：

```powershell
& 'C:/Program Files/Unity/Hub/Editor/6000.0.55f1/Editor/Unity.exe' -batchmode -nographics -projectPath '<repo>/unity/MQTT_BeamPro/BeamPro_Final' -buildTarget Android -runTests -testPlatform EditMode -testResults '<repo>/unity/MQTT_BeamPro/BeamPro_Final/Artifacts/editmode.xml' -logFile '<repo>/unity/MQTT_BeamPro/BeamPro_Final/tests.log'
```

APKは同じUnityで `-batchmode -quit -buildTarget Android -executeMethod AmbulanceAR.Editor.AmbulanceProjectSetup.BuildApk`。ProjectPathを完成版に限定する。ログ・APK・LibraryはGit追跡しない。
