# Siren / Spatial Lab — Web AR Mockup

救急車サイレン検知・方向提示システムの表示体験を確認する、独立したWebモックです。
ReSpeaker → Jetson Orin Nano（CRNN / DOA）→ MQTT → Beam Pro → Unity + XREAL SDK → XREAL Air 2 Ultra、という将来構成のうち、方向提示を疑似再現します。

**実際のXREALアプリではありません。** マイク入力・推論・MQTT通信・XREAL SDK・実機トラッキングは使用しません。背景はThree.jsの道路・建物で、実際の光学シースルー表示や視野角は再現しません。
既存の `Jetson/`、`Mosquitto/`、`Unity/`、`README_MQTT_XREAL.md`、`System/`、Unityプロジェクトは変更していません。

## 起動

リポジトリのルートで実行します（Python 3が必要）。

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory mqtt_xreal_system/Web_AR_Mockup
```

ブラウザで http://127.0.0.1:8765/ を開きます。終了はターミナルで Ctrl+C。
ビルド・npm installは不要です。Three.js 0.160.1を `vendor/` に同梱しているため、外部ネットワークも不要です。WebGL対応ブラウザを使ってください。ES Modulesを使うため、`index.html` のダブルクリック（file://）ではなくHTTPサーバーから開いてください。

## 操作

| 操作 | 意味 |
| --- | --- |
| Siren Detected | ONで立体矢印と警告、OFFで両方を非表示 |
| DOA | 生の疑似受信方向。0〜359°、1°刻み。数値入力も可能 |
| Confidence | 0〜100%、初期値98%。矢印の色を変更。数値は調整パネルとJSONだけに表示。サイズ・表示可否は変えない |
| DOA Offset | 取り付け方向の固定補正。−180〜+180° |
| Invert DOA | 生のDOAの符号を反転してからオフセットを適用 |
| Head Yaw | カメラの向きだけを−180〜+180°回転。DOAと矢印の空間位置は保持 |
| Front / Right / Back / Left | 生のDOAを0 / 90 / 180 / 270°に変更。補正は引き続き適用 |
| Demo | 約30秒で1周。再クリック・DOA手動変更・プリセット選択で停止 |

モックの初期値はDOA 20°、Offset 0°、Invert OFF、Head Yaw 0°、検知ONです。前方から少し右の矢印を見せます。
Front等のラベルは**未補正時の代表方向**です。OffsetやInvertを変えると表示方向も変わります。
Pulseは4秒周期で1.0〜1.1倍。OSの「動きを減らす」設定時はPulseを停止します（明示的に起動するDemoは使用可能）。

## ユーザー向け表示

救急車アイコンと大きな日本語表示で対象を示します。ユーザー向け警告にはConfidenceやDOAの数値を出さず、調整パネルとJSONに残しています。

| Confidence | 矢印の色 | 警告表示 |
| --- | --- | --- |
| 0%以上50%未満 | 青灰色 | 救急車の可能性 / 音の種類を確認中 |
| 50%以上80%未満 | 黄 | 救急車の可能性 / サイレンらしい音を検知 |
| 80%以上100%以下 | 赤 | 救急車 / サイレンを検知 |

閾値・色はモックの仮設定です。校正済み確率や危険度ではありません。`app.js` の `CONFIDENCE_BANDS` で変更できます。発光色・警告のアクセントにも反映します。低信頼度でも検知ONなら矢印を表示し、OFFでは警告も非表示です。接近速度は推定していないので「接近」とは断定しません。

## DOA・座標・実機との違い

```text
signedDOA = invert ? -DOA : DOA
displayAngle = ((signedDOA + offset) % 360 + 360) % 360
theta = displayAngle * PI / 180
x = 2.5 * sin(theta)
y = 1.05  // 視点の高さは1.6m
z = -2.5 * cos(theta)  // Three.js: 初期カメラの正面は -Z
arrow.rotation.y = -theta
camera.rotation.y = -headYaw * PI / 180
```

初期正面0°、右90°、後方180°、左270°です。Unityの+Z前方へ移植するときは `z = +radius * cos(theta)` とし、回転規約も合わせます。表示半径2.5mは**音源までの推定距離ではなくUIの配置距離**です。矢印は厚みのあるExtrudeGeometryのMeshです。地面と平行に寝かせ、音源へ外向きに配置します。上面が見えるよう視線より0.55m低い高さ1.05mに置いています。DOAから音源の仰角を推定しているわけではありません。

今回のHead Yawは、要求された「DOA 180°を保ち、振り返ると矢印が見える」確認用です。DOAを基準姿勢の空間方向として配置し、視点だけを動かします。

**実機のヘルメット搭載ReSpeakerのDOAは、その時点の頭部に対する相対方向**です。モックの固定DOAをそのまま実機の世界座標と解釈してはいけません。実機では測定時の頭部姿勢で補正済み方向ベクトルを世界座標へ変換する必要があります。

```text
worldDirection = headRotationAtMeasurement * calibratedHeadRelativeDirection
```

頭部姿勢と音声測定時刻の同期、追跡原点、頭部移動後のアンカー更新方式を決める必要があります。このモックは頭部回転のみで、並進・距離推定・世界アンカーの再測定は対象外です。

既存Unityスクリプトの「DOAを反転→Offsetを加算→正規化」の順序を踏襲しています。ただし既存は2D画像をZ軸回転し、既定Offsetは90°です。本モックは右を正とする3D方位、既定Offsetは0°なので、既存の物理方向対応をそのまま保証しません。実機で回転符号とゼロ方向を再校正してください。

## MQTT Payload Preview

`../README_MQTT_XREAL.md`、`../Jetson/mqtt_bridge.py`、`../Unity/Assets/Scripts/SirenMqttSubscriber.cs` のトピック・フィールド構成を参照しています。

```text
research/ambulance/v1/state
```

```json
{
  "version": 1,
  "detected": true,
  "class_name": "siren",
  "confidence_pct": 98,
  "doa_deg": 20,
  "rms": 0.041,
  "inference_ms": 23.8,
  "timestamp_ms": 1787832000000
}
```

DOA・検知・Confidenceの変更時に更新します。`doa_deg` は補正前の生値です。Offset、Invert、Head Yawは表示側設定なのでペイロードには追加していません。`timestamp_ms` はプレビューを更新した時刻のUnixミリ秒。RMS・推論時間は固定テスト値です。OFF時の `class_name` はモック上の便宜的な `background` で、実機モデルのクラス名を規定しません。

既存仕様の `doa_deg = -1`（不明方向）、通信断、1.5秒の鮮度タイムアウト、QoS / retain は本モックではシミュレーションしません。実機受信処理では引き続き考慮してください。

## 検証

2026-09-26実施：

- `node --check app.js` 成功。
- ローカルHTTPサーバーで `/`、`app.js`、`style.css`、`vendor/three.module.js` がすべてHTTP 200。JavaScriptのContent-Typeも確認。
- `node verify.cjs`：9グループ成功。実際のThree.jsのGeometry、カメラ射影、Quaternionを使い、水平配置、4方向の位置・向き、補正順序、検知表示、後方視認条件、ペイロード、Confidenceの色境界とサイズ維持、数値入力、Pulse、Demoを検証。
- `verify.cjs` はDOMとWebGLRendererを置換するローカル統合検証です。**ブラウザ実行・GPU描画・画面レイアウトの確認を代替しません。**
- Codexのブラウザ一覧は空で、内蔵ブラウザとChromeの起動APIは「Browser is not available」を返しました。**ブラウザ表示・JavaScriptコンソールエラー・見た目の実確認は未完了です。** 接続後に以下を実施してください。

### ブラウザ確認手順

1. 起動URLを開き、道路・建物・立体矢印を確認。コンソールにJavaScript/WebGLエラーがないことを確認。
2. Siren DetectedをOFF→ONにし、矢印と警告が両方切り替わることを確認。
3. DOAスライダー・数値入力・4方向プリセットで位置と表示角度が変わることを確認。
4. DOA 45°、Offset 30°で75°。Invert ONで345°になることを確認。JSONのDOAは45のまま。
5. Offset 0°、Invert OFF、Back、Head Yaw 0°で矢印が視野外。Yaw +180°または−180°で後方の矢印が見え、DOAは180°のまま。
6. Confidenceを0 / 49.9 / 50 / 79.9 / 80 / 100%にして上表の色と文言を確認。矢印の大きさは変わらず、ユーザー向け警告に数値がないことを確認。
7. DemoでDOAとJSONが進み、359°→0°と周回することを確認。Stop Demo、プリセット、手動DOAで停止することを確認。
8. ウィンドウを狭め、縦積みレイアウト・キャンバスの追従・操作可能性を確認。

## 今後のUnity / XREAL SDK移植

再利用できるのは、受信状態の構造、DOA補正・正規化、円周配置、音源方向への回転、検知による表示切替、時間ベースのPulseです。Three.jsコード自体をUnityにコピーするのではなく、Vector3・Quaternion・Mesh・Material等へ置き換えます。

実機で人間側が決める項目：ReSpeakerの取り付けゼロ方向・回転符号、姿勢と測定時刻の同期、世界座標への変換とアンカー更新、視認しやすい半径・高さ・矢印サイズ、警告の表示量、閾値・表示保持時間、不明DOA・通信断時の動作。

## ファイル

- `index.html`：画面構造・起動時エラー表示
- `style.css`：ダークUI・HUD・レスポンシブレイアウト
- `app.js`：3D背景・Mesh・補正・操作・疑似JSON
- `verify.cjs`：Nodeで実行するローカル統合検証
- `vendor/three.module.js`：Three.js 0.160.1
- `vendor/THREE-LICENSE.txt`：Three.js MITライセンス
- `README.md`：本書

Three.jsの参照先：[公式ドキュメント](https://threejs.org/docs/)。同梱ファイル取得元：`https://cdn.jsdelivr.net/npm/three@0.160.1/build/three.module.js`。
