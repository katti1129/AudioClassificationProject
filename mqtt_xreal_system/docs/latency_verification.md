# 遅延計測モードの検証（2026-10-15）

## Confidence列追加の検証

遅延CSV末尾に `warning_confidence_pct` と `arrow_confidence_pct` を追加した。
通常のMQTT状態から、各初回表示に使ったConfidence（0〜100）を記録する。Jetson・MQTT形式はこの追加で変更していない。
値を後続の判定で上書きしないこと、警告と矢印で異なる値を保存できること、未表示時は空欄になることを確認した。

開いているUnityを停止せず、`Artifacts/ConfidenceValidation` のコピーで **50/50成功、失敗0、スキップ0**。
Python→実MQTT→Unity→CSVのテストでもConfidence=99が両列へ保存されることを確認。C#コンパイルエラー0。
変更した5つのC#ファイルが本体と検証コピーで一致することも確認した。
結果：`unity/MQTT_BeamPro/BeamPro_Final/Artifacts/ConfidenceValidation/Artifacts/confidence-editmode.xml`。

Confidence列追加後のAndroid APK再ビルド・実機試験は未実施。以下のAndroidビルド成功は、この列を追加する前の計測版に対する結果である。

## 確認済み

- Windows開発環境のPython 3.13で、Jetson_Finalの単体テスト **19/19成功**（既存10件＋追加9件）。numpy 2.5.4、paho-mqtt 2.1.0を専用venvへ導入。
- Unity **6000.0.55f1** のEditModeテスト **50/50成功**、失敗0、スキップ0。既存の表示・方向・MQTT再接続・Scene Play Modeテストを含む。
- Unity C#コンパイルエラー0。通常のMQTT v1 JSON、QoS 0、retain falseを維持。
- 実localhost TCP Brokerで、Pythonの計測Publisher→Unityの状態受信・別トピック・時計合わせ→CSV保存を確認。
- metadata先着／frame先着、再送の重複排除、警告と矢印の別記録、Unknown等で矢印なし、時計未同期・負の時間、開始情報だけ届くケース、malformed JSON、初回警告の照合欠落、CSVの終了時排出、計測OFFを検証。
- Sceneに計測コンポーネント・参照を追加し、Measure Latencyの既定OFFと、OFF時に計測CSVが作られないことを保存済みSceneのPlay Modeテストで確認。
- Pythonの構文検査、CLI `--help`、差分の空白検査を実施。
- Android IL2CPPビルド **Succeeded / Errors 0 / Warnings 2**。既存APKを上書きせず `Builds/LatencyValidation.apk` を生成（計測OFF）。ビルド確認用の一時Editorスクリプトは実行後に削除した。

Unity結果：`unity/MQTT_BeamPro/BeamPro_Final/Artifacts/latency-editmode.xml`

Unityログ：`unity/MQTT_BeamPro/BeamPro_Final/Artifacts/latency-editmode-complete.log`

Android結果：`unity/MQTT_BeamPro/BeamPro_Final/Artifacts/latency-build-result.txt`

Androidログ：`unity/MQTT_BeamPro/BeamPro_Final/Artifacts/latency-android-build.log`

ビルド警告2件は既存XREAL SDK同梱の `libXREALXRPlugin.so` と `libmedia_codec.so` が16KB-alignedではないというもの。
ログではAndroid 15以降のARM64端末で問題となる可能性が示されている。今回SDKバイナリは変更していない。対象端末のOS・ページサイズでの適合は別途確認が必要。
ビルドログにはRendering Debugger用Shader Variantの削除通知と、Editor終了時の未初期化Subsystem停止通知もある。

統合テストの音声・フレーム境界は合成入力。Editor batchmodeで実際のWaitForEndOfFrameを待った測定ではない。
CSV内の合成試験結果をJetson・Beam Pro実機の遅延として引用しないこと。

## 実機で必要な確認

- ReSpeakerのADC時刻の有効性、入力欠落の有無、音の立ち上がり閾値。
- Jetson上のTensorFlow・音声・GUIを含む全経路。
- Beam Proのフレーム終端取得・CSV保存／回収、Wi-Fi環境での同期RTT。
- 実機での計測ON/OFFのCPU負荷・フレーム時間比較。
- サイレン提示回数とCSV試行数の照合、未検知・欠落を含む統計。
- 必要なら外部撮影／光センサーで実際の光学表示まで確認。

## 変更範囲

Jetson：`config/config.py`、`app/legacy_gui.py`、`app/state_relay.py`、`app/realtime_xreal_system.py`、`mqtt/mqtt_bridge.py`。
追加：`telemetry/latency_probe.py`、`tests/test_latency.py`、`tests/latency_loopback_sender.py`。

Unity：`AmbulanceSystemController.cs`、`AmbulanceMqttSubscriber.cs`、`AmbulanceProjectSetup.cs`、`AmbulanceARScene.unity`、Scene Play Modeテスト。
追加：`Scripts/Telemetry/` の4スクリプト（Clock、Client、Controller、CSV logger。DurationsはClock内）、2テストファイルと対応meta。

説明書：完成版README、MQTT仕様、測定手順、検証報告。
既存正常版の `System/`、`BeamPro/`、`Jetson/`、`Web_AR_Mockup/` は変更していない。
作業開始時からあった `ProjectSettings.asset` のpreloadedAssets参照2件削除は維持している。
