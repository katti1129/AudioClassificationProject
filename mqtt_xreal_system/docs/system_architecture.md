# 完成版の構成と実装上の境界

## 参照版と完成版

| 場所 | 役割 |
| --- | --- |
| `System/` | 既存のReSpeaker / CRNN / GUI。変更しない |
| `unity/MQTT_BeamPro/BeamPro/` | 動作確認済みMQTTアプリ。変更しない |
| `mqtt_xreal_system/Jetson/`, `Unity/` | 既存MQTTプロトタイプ。変更しない |
| `mqtt_xreal_system/Web_AR_Mockup/` | 水平矢印・色・Pulseの設計仕様。変更しない |
| `mqtt_xreal_system/Jetson_Final/` | 完成版Jetsonエントリーポイントと専用コピー |
| `unity/MQTT_BeamPro/BeamPro_Final/` | 既存UnityプロジェクトのAssets / Packages / ProjectSettingsを複製した実機用プロジェクト |

後半の依頼32章を優先し、原本へ統合コードを書き込まず分離した。`baseline_hashes.json` は作業開始時の参照版のSHA256。原本のLibrary等の生成物は対象外。

## データ経路

```text
ReSpeaker audio 16 kHz / mono ─→ 1.0 s rolling buffer
  → RMS gate (0.012)
  → Log-Mel (128 bins, FFT 1024, hop 512, 128 x 32)
  → existing CRNN / ReduceSumLayer
  → 5-prediction mean → siren threshold 0.97 / 3 ON / 3 OFF
  → final_class / confidence / RMS / elapsed inference pipeline time
  → latest-state relay (fresh AI result AND fresh audio required)

ReSpeaker USB DOA (~20 Hz) ─→ fresh direction / Unknown
  → publisher worker (~10 Hz) → Paho network thread → Mosquitto
  → Wi-Fi → MQTTnet worker → bounded queue → Unity LateUpdate
  → validated v1 state → calibrated local direction + head yaw history
  → world direction target → circular smoothing
  → 3D mesh + wearer HUD
```

## Jetson再利用と変更

`app/legacy_gui.py` は既存GUIの専用コピー。音声デバイス選択、前処理、モデルロード、PySide6 GUIを保持する。`tuning.py` も同梱。完成版は `System/` を実行時に書き換えず、独立して動作する。

変更点：

- 元コードはヒステリシス未成立時にargmaxへ戻るため、sirenが最大ならON待ちを迂回し得た。完成版は `SirenDecision` のactive状態だけからsirenを決定する。
- 無音時は履歴とヒステリシスをリセット。
- 音声キューは最大8チャンク。滞留時は古いチャンクを捨てる。
- USB読み出しタイムアウト200ms、DOA更新から300ms超ならUnknown。DOA初期化不能でも音声推論は継続。
- GUI更新フックは小さい状態コピーのみ。ネットワークとCSV I/Oは別スレッド。
- 新しい音声が500ms以上ない、または新しい推論結果が1秒以上ない場合、Publishを停止する。古いAI結果へ新しいtimestampを付け続けない。
- CSVは最大512行のキュー。満杯ならドロップ数をGUIに表示。ログ書込み障害をAIへ波及させない。

`inference_ms` は既存GUIと同じ、RMS/前処理/推論/判定を含む経過時間（秒→ms）で、GPU演算のみの時間ではない。モデルの学習時と同じ前処理・クラス順 `other, siren` を維持する。学習済み重みは同梱・捏造しない。

## Unityの役割

`Assets/AmbulanceAR/` に独自機能を集約。既存のMainSceneやMqttReceiverは複製先にも保持し、完成版Sceneでは起動しない。

- `AmbulanceMqttSubscriber`：再接続、Subscribe、16件上限のキュー、受信時刻、接続世代。
- `AmbulanceState` / `StateFreshness`：型・範囲検証、未知版拒否、重複タイムスタンプ拒否、鮮度。
- `HeadPoseHistory`：実カメラTransformから水平Yawを抽出。XRの位置・回転追跡の両方が有効な時だけ記録。
- `AmbulanceDirectionController`：方向補正、世界方向、短い時定数の円周平滑化。
- `AmbulanceArrowView`：+Zを先端とする水平Mesh、半径2.5m、高さ−0.55m、4秒周期1〜1.1倍。
- `AmbulanceAlertView`：救急車アイコン／英文、接続状態、Unknown。数値は `Show Debug Details` のみ。HUDは頭部基準 `(0, 0.24, 1.4)` m、矢印より上に配置。
- `AmbulanceSystemController`：新しい状態でだけ方向目標を更新し、毎フレーム位置を頭部移動に合わせる。

世界方向は保持するが、矢印の位置は `headPosition + direction * radius + up * heightOffset`。永続Spatial Anchorではない。頭部の並進後も距離を維持する。上下傾斜を見ない水平の方位提示であり、音源の高さ・距離・接近速度は推定していない。

色はWebモックの仮設定を継承：50%未満青灰色、50%以上80%未満黄、80%以上赤。低・中はPOSSIBLE AMBULANCE。色を理由に検知フラグを再判定しない。日本語フォントの外部依存を増やさず、実機HUDは救急車アイコン＋英語、数値は研究用切替とした。

## XREAL SDK

確認日：2026-09-26。[公式セットアップ](https://docs.xreal.com/Getting%20Started%20with%20XREAL%20SDK) はUnity 6000.0.x LTSを対応範囲に挙げている。したがって既存6000.0.55f1を継続する。

作業PCの `C:/Users/cpsla/Desktop/package` に存在した正規形式の `com.xreal.xr` **3.0.0-pre.4** を完成版の `Packages/com.xreal.xr/` にそのまま埋め込んだ。これは[現在の公開ダウンロードページ](https://developer.xreal.com/download/)の3.1.0とは異なる。バージョンを偽装していない。外部マシンへの移動時もSDKの利用条件に従うこと。

SDKの `XREALSettings`、`XREALXRLoader`、`XREALProjectValidator`、`XREALManifestProvider`、Interaction BasicsのHelloMR構成を参照した。旧NRSDK APIを新規コードから呼ばない。SDK内部の互換名（nreal manifest等）は提供元の実装を保持。

XR Origin + Input System TrackedPoseDriver（`<XRHMD>/centerEyePosition`、`centerEyeRotation`、`trackingState`）を構成し、SDKのUnity XR Input SubsystemからカメラTransformへ反映する。管理対象はAndroidのXREAL Loaderのみ。6DoF、REALITY、OpenGLES3、ARM64、IL2CPP、INTERNET、最小API29。手・平面・画像・永続アンカーの機能は使わない。

完成版のAndroidアプリIDは `jp.research.ambulancear.complete`。`Assets/AmbulanceAR/link.xml` でJSON復元対象の状態型をIL2CPPのストリッピングから保護する。

Support Multi ResumeはOFF（他の2Dアプリへ切り替えたままのAR表示は今回の構成外）。提供SDKでは `nractivitylife-release.aar` と `nractivitylife_6-release.aar` の直接Importが両方ONだったため、完成版では両方OFFに補正する。これらはSDKのビルド処理がMulti Resume ON時だけ適切な版をAssetsへコピーする用途。SDKのコード／バイナリは保持し、Import用の.metaだけを変更している。

## 時刻と精度の限界

DOAはPublish時付近に取得した頭部相対方位。Unityは受信時刻をローカル単調時計で保存し、その時刻付近の姿勢履歴と組み合わせる。`Pose Lookback Seconds`（初期0）でDOAサンプリング＋LAN遅延の概算補正ができる。v1にはDOA専用の測定時刻がないため、厳密な測定時刻同期を実現したとは扱わない。速い頭部回転・遅いLANでは残差が出るので実測が必要。

1.0秒音声窓、モデル推論、ヒステリシスの遅延も別途存在する。世界方向の平滑化は初期時定数0.12秒。追跡喪失時は矢印を隠し、追跡回復後の新しい有効データを待つ。垂直を向いてYawが定義できない場合も同様。
