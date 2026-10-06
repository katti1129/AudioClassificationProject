# 音響状態と視野外案内

MQTT v1やJetsonの送信形式は変更しない。頭部装着版から引き継いだ表示処理の仕様。机上版の方向基準と校正手順は [README.md](README.md) を参照。

## 状態

| 有効な受信状態 | HUD | 矢印 |
| --- | --- | --- |
| silence | SURROUNDINGS QUIET、小さい緑灰色文字 | 非表示 |
| other | SOUND DETECTED、小さい淡黄色文字 | 非表示 |
| siren + detected true | AMBULANCE / SIREN DETECTED、赤橙色＋救急車アイコン | DOA・追跡が有効で視野内なら表示 |
| siren + 負のDOA | 上記＋DIRECTION UNKNOWN | 非表示 |
| 未接続／stale／未受信 | AUDIO STATUS UNAVAILABLE、グレー | 非表示 |

class_nameとdetectedを両方確認する。silence/otherはdetectedがtrueでもサイレンとして扱わない。sirenでdetected=falseはSound扱い、未知のclass_nameはUnavailable扱い。

silence/otherは同じ候補が0.75秒継続すると表示を切り替える。安定待ち中は直前の通常状態を維持する。サイレンは即時、通信無効も即時。サイレン解除後は古い警告を即座に消し、通常状態の安定待ち中はUnavailableを表示する。staleの判定自体は従来どおり最終有効受信から1.5秒。MQTT再接続時は表示フィルターもリセットする。

## 視野外案内

AmbulanceDirectionController.WorldDirectionとカメラのforward/rightを水平面へ投影し、符号付き水平角を求める。カメラ正面から±25°以内ならワールド矢印、範囲外ならカメラ追従HUDで「← TURN LEFT」「TURN RIGHT →」、後方半球なら「↻ BEHIND YOU」。旋回して範囲内に入ると案内を消す。頭部追跡無効・Unknown・非サイレン時は案内も矢印も消す。

これは設定した水平視野角による判定で、グラスの光学視野・縦方向のクリッピングを自動取得する機能ではない。実機に合わせVisible Half Angleを調整する。HUD案内はワールド矢印と別オブジェクト。記号はHudDirectionIconがUIメッシュとして描くのでフォント欠落に依存しない。

## Inspector

| オブジェクト／Component | 設定 | 初期値 |
| --- | --- | --- |
| Ambulance Arrow / AmbulanceArrowView | Radius（水平距離） | 1.8m |
| 同上 | Height Offset | −0.25m |
| 同上 | Tilt Degrees（先端を起こす角度） | 35° |
| 同上 | Base Scale | 1 |
| 同上 | Pulse Scale（最大倍率） | 1.2 |
| 同上 | Pulse Seconds（拡大縮小の周期） | 1秒 |
| 同上 | Emission Intensity | 1.5 |
| 同上 | Low / Medium / High Confidence Color | 青灰／黄／赤、境界50/80%を保持 |
| Ambulance System / AmbulanceSystemController | Visible Half Angle（水平半角） | 25° |
| Main Camera / Ambulance HUD / AmbulanceAlertView | Status Stable Seconds | 0.75秒 |
| 同上 | Quiet / Sound / Siren / Unavailable Color | 緑灰／淡黄／赤橙／灰 |

矢印は消灯点滅ではなく滑らかなPulseを継続。Mesh自体は以前の厚み付き形状を保持し、Transformで起こすため世界方位は変わらない。Emissionで暗い背景でも見えるようにするが、Bloomは必須にしない。Confidence数値は従来のShow Debug Detailsで切り替える。

## Scene更新

`Ambulance AR > Upgrade acoustic HUD` は既存SceneへAcoustic Status、Source Guidance、Desk Calibration、FixedMicrophoneReferenceを追加し、HUD Prefab／Arrow Prefabも更新する。Scene全体を再作成しない。矢印の既存値が旧初期値と一致する項目だけ新初期値へ変更するため、独自の調整値は保持する。Broker Host、DOA Offset、XR設定には触れない。

## 検証

AcousticPresentationTests：安定時間と短い交互入力、サイレン即時割込み、class_nameとdetectedの整合、左／右／後方、視野内復帰、359/1°、Unknown、追跡なし、通信無効、色・発光・倍率・傾き。

既存のDisplayIntegrationTests／ScenePlayModeTestsは新仕様へ更新し、実SceneのPlay Modeでsilence/other/サイレン/旋回/Unknown/staleを確認する。既存のDOA変換、JSON、MQTT実TCP・Broker再接続の試験も継続する。

コピー元の38件に机上版用の試験を追加した。机上版の結果・APK生成状況は [README.md](README.md) に記録する。コピー元のテスト成功を、このプロジェクトのテスト結果として扱わない。

PC描画は `Capture acoustic states`、校正・後方・振り向きの描画は `Capture desk calibration and turn` メニューで `Artifacts/` に出力する。これはグラスの実写ではない。Beam Proでの光学像、見つけやすさ、角度と文字サイズは実機確認が必要。
