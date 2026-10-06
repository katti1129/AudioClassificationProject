# BeamPro_Desk — 机に固定したReSpeaker用

`BeamPro_Final`の作業ツリーをコピーした独立したUnityプロジェクト。元の頭部装着版は変更しない。Unity Hubの「Add project from disk」でこのフォルダを選び、Unity **6000.0.55f1**で開く。新規の空プロジェクトは不要。

Scene：`Assets/AmbulanceAR/Scenes/AmbulanceARScene.unity`

## 再利用したもの

MQTT v1、QoS 0受信・再接続、JSON検証、1.5秒stale、silence／other／siren表示、0.75秒の状態安定化、信頼度色、立体Mesh Arrow、視野外案内、XREAL 6DoF、埋込SDK `Packages/com.xreal.xr`（3.0.0-pre.4）、Android設定を引き継いだ。Jetson側の変更は不要。

## 頭部装着版との違い

| | BeamPro_Final | BeamPro_Desk |
| --- | --- | --- |
| マイク | 頭と一緒に回る | 机に固定する |
| DOAの基準方位 | 受信時の頭部Yaw | 起動後に校正したマイクの固定Yaw |
| 頭を回すと | マイクのRaw DOAも変わる | Raw DOAは同じで、視野内外だけが変わる |
| アプリ名 | Ambulance AR | Ambulance AR Desk |
| Android ID | jp.research.ambulancear.complete | jp.research.ambulancear.desk |

同じBeam Proに両方をインストールできる。起動するアプリを取り違えないようHUDにも `DESK MIC` と表示する。

```text
micLocalAngle = Normalize360(-rawDOA + 270)  // InspectorのInvert / Offsetで調整可能
worldDirection = calibratedMicYaw * (sin(micLocalAngle), 0, cos(micLocalAngle))
worldDirection と現在の camera.forward / right → 視野内の矢印、または左右／後方のHUD案内
```

Raw 270°=マイク正面、180°=右、90°=後方、0°=左。ここでの「正面」は利用者ではなくマイク基準。

## 実機での手順

1. ReSpeakerを机へ固定する。正面方向を決めて印を付け、以後マイクを回転させない。
2. `Ambulance System`のMQTT Broker HostをJetsonのIPに設定してSceneを保存する。コピー時の値は `133.49.27.137`。
3. `Ambulance AR > 3. Build Beam Pro Desk APK`で `Builds/AmbulanceAR_Desk.apk`を生成する。
4. `adb install -r Builds/AmbulanceAR_Desk.apk`でインストールし、Air 2 Ultraを接続してMyGlassesから **Ambulance AR Desk** を起動する。
5. 頭を**マイクの正面と同じ向き（平行）**へ向ける。「マイク本体を見る」という意味ではない。`FACE THE SAME DIRECTION AS MIC FRONT / HOLD STILL` が出ている間、5秒間頭を動かさない。校正文が消えれば完了。
6. マイクと音源を固定したまま、頭だけを回して確認する。後方の音源に向くと `BEHIND YOU` が消え、矢印が出る。JetsonのDOAは頭の回転では変化しない。
7. マイクを動かした場合はアプリを終了して起動し直し、再校正する。追跡喪失・XR原点変更・アプリの一時停止でも校正を解除するため、案内が出たら再びマイク正面と同じ向きへ合わせる。

校正中もサイレン警告と音響状態は表示するが、矢印と視野外案内は表示しない。校正はセッション内だけで保持し、前回起動時のXR方位を保存して再利用しない。頭部の水平の向きが校正候補から3°を超えて変わった場合は5秒のカウントをやり直す。

この版は**マイクから見た音の方位**を示す。利用者が机から離れて移動した場合の音源位置・距離や視差は推定しない。最初はマイクの近くの定位置で、単一の固定音源を使って確認する。

## InspectorとEditor Simulation

`Ambulance System / FixedMicrophoneReference`：Alignment Seconds（5秒）、Maximum Drift Degrees（3°）。`AmbulanceDirectionController`：Invert DOA / DOA Offset / Smoothing。

HUD、矢印、視野角の設定は [AUDIO_STATUS.md](AUDIO_STATUS.md) を参照。矢印は距離1.8m、高さ−0.25m、傾き35°。水平視野半角25°。

PlayではEditor SimulationがON。Editorのみ初回校正を即時に行う。実機の5秒校正は省略しない。画面のBackを選びHead Yawを180°へ動かすと、Raw DOA=90°のまま矢印が現れる。Fixed world sourceをOFFにしても、机上版では同じDOAを維持したまま頭を回せる。`Align desk mic forward to current view`でEditor内の校正をやり直せる。

`AmbulanceSystemController`のコンテキストメニュー `Recalibrate desk microphone`も校正を解除する。実機での再校正はアプリ再起動を使用する。

## 検証

Test Runner > EditMode > AmbulanceAR.Tests。既存の音響表示・MQTT再接続テストを再利用し、机上固定DOAでの旋回、校正待ち、校正中の動き、追跡喪失、任意の初期Yaw、359°/1°境界、アプリID分離の試験を追加した。

2026-10-05、Unity 6000.0.55f1・Androidターゲットで **EditMode 48件成功／失敗0、C#コンパイルエラー0**。コピー元の38件を机上版に合わせて更新し、10件を追加した。保存済みSceneのPlay ModeでRaw DOA=90°を維持して頭だけ180°回し、BEHIND YOUが消えて矢印が現れることを確認。実TCPでのMQTT再接続・再Subscribeと不正JSONの試験も成功。

結果：`Artifacts/desk-tests.xml`、`Artifacts/desk-tests.log`。PC描画も `Artifacts/desk-calibration.png`、`desk-behind.png`、`desk-turned.png` で確認済み。実機の光学像と校正操作はBeam Pro + Air 2 Ultraで別途確認が必要。

Android APK生成も成功（Errors 0 / Warnings 6）。`Builds/AmbulanceAR_Desk.apk`：191,702,350 bytes。APKからアプリID `jp.research.ambulancear.desk`、表示名 `Ambulance AR Desk`、ABI `arm64-v8a` を確認済み。ログは `Artifacts/desk-build.log`、サマリーは `Artifacts/build-result.txt`。端末へのインストールは行っていない。

警告にはXREAL SDKのネイティブライブラリ（libXREALXRPlugin.so / libmedia_codec.so）の16KB alignment未対応と、Rendering Debugger用Shaderの除去が含まれる。SDKの非推奨API警告も出ている。16KBページを使うAndroid端末での互換性は未確認で、今回SDK自体は変更していない。

コピー元のAssets／Packages／ProjectSettings 1,068ファイルは、作業前後のSHA256比較で変更0。今回の作業は `BeamPro_Desk` 内だけで完結している。

Library、Temp、Builds、Artifactsはコピー元から持ち込まず、このプロジェクトで生成する。プロジェクト間でLibraryを共有しない。作業前のコピー元Assets／Packages／ProjectSettingsのハッシュは `Artifacts/final-source-hashes.json` に保存。
