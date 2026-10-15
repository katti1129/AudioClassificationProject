# ソフトウェア内での遅延測定

通常の認識・DOA・MQTT v1・AR表示を維持し、研究用計測モードを追加した。
既定はJetson・UnityともOFF。OFF時は計測用接続、時計合わせ、計測CSV、フレーム終端コルーチンを作らない。
通常の受信時刻・stale判定と、従来の任意ログ `--log-dir` は独立して残す。

## 測定区間

**収集音声内で推定した音の開始から、警告を反映したUnityフレーム終端まで** を測る。
グラスの発光時刻・GPU完了・ディスプレイ走査までの実測ではない。
既存 `inference_ms` の意味は変更していない。

| 時刻 | 取得場所 |
| --- | --- |
| T0 | Jetson。静音継続後、ブロックRMSが閾値を超えたブロック内の最初の振幅閾値超過サンプル |
| T1 | その試行で最初にサイレンと判定した時刻。平滑化・連続判定を含み、再推論でも保持 |
| T2 | 表示に対応する通常MQTTメッセージの `publish()` 呼び出し直前。JSON化・送信キュー・Broker経由は以降の区間に含む |
| T3 | Unityの通常MQTT受信コールバック冒頭。OS/TCP受信時刻そのものではない |
| T4 | `Present()` 後の `WaitForEndOfFrame`。警告・矢印を別々に追跡 |

T0は **音量の立ち上がり推定** であり、静かな環境で単独のサイレンを提示する実験用。
会話・物音・連続騒音の中でサイレン開始時刻を保証しない。閾値以下の音の先頭は含められず、立ち上がり方でも変わる。

`inputBufferAdcTime` と `currentTime` の差をJetson単調時計へ写し、サンプル位置を加える。
`onset_method=adc_mapped` もドライバ時刻とコールバック取得の誤差を含む推定。
ADC時刻が無効ならコールバック時刻−ブロック長を使い、`callback_estimate` と明記する。
後者は入力ドライバ待ち時間を正確に含められない。両方式を混ぜて平均しない。
音声欠落・ADC時刻不連続・入力キュー欠落を検知した試行は無効扱いにする。

参考：[sounddeviceのコールバック時刻](https://python-sounddevice.readthedocs.io/en/latest/api/streams.html)、[Unity 6 WaitForEndOfFrame](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/WaitForEndOfFrame.html)。

## 起動

1. 通常推論が動作するJetson環境で、リポジトリルートから起動する。モデルパスは実在するものへ変更する。

```bash
python -m mqtt_xreal_system.Jetson_Final.app.realtime_xreal_system \
  --model /absolute/path/to/best.keras \
  --broker 127.0.0.1 \
  --measure-latency \
  --latency-onset-threshold 0.01 \
  --latency-quiet-seconds 1.0
```

2. Unityで `BeamPro_Final` の `AmbulanceARScene` を開く。
3. `Ambulance System` の `Latency Measurement Controller` で **Measure Latency** をON。
   `Subscriber` は既存Subscriber、`Observation Seconds` は既定10秒。シーン内の参照は設定済み。
4. 通常の `Ambulance Mqtt Subscriber / Broker Host` をJetsonのLAN IPに設定する。
5. シーンを保存し、`Ambulance AR > 3. Build Beam Pro APK` で再ビルド・インストールする。
   計測設定は起動時に読み込むため、変更後はPlayまたはアプリを再起動する。
6. 起動後、少なくとも5秒待って時計合わせ・モデルのウォームアップを行う。
   静かな状態が続き、古い警告が消えていることを確認して正面からサイレンを提示する。
   試行間にも静音時間を設ける（目安3秒以上）。指定静音時間未満では新試行にならない。

Editorで通信を測る場合は `Editor Simulation` をOFFにする。シミュレーションの表示は対象外。
Gameビューを表示してPlay実行する。Editor batchmodeでは `WaitForEndOfFrame` が動かないため、統合テストではフレーム境界を明示的に与えている。

通常利用ではJetsonの `--measure-latency` を外し、Unityの **Measure Latency** をOFFにしたAPKを使用する。
従来の `--log-dir` はJetson認識結果CSVであり、今回のUnity計測CSVとは独立している。

## 時計合わせと計算

両端末の単調時計を使用。通常JSONのUnix時刻 `timestamp_ms` は照合キーにだけ使い、遅延の引き算には使わない。
Unity送信u1、Jetson受信j2、Jetson返信j3、Unity受信u4の4時刻で推定する。

```text
offset = ((j2 - u1) + (j3 - u4)) / 2   # Jetson時計 − Unity時計
rtt    = (u4 - u1) - (j3 - j2)
Jetson時刻をUnityへ換算 = Jetson時刻 − offset

detection_s      = T1 − T0
send_wait_s      = T2 − T1
transport_s     = T3 − (T2 − offset)
unity_s         = T4_warning − T3
warning_total_s = T4_warning − (T0 − offset)
arrow_total_s   = T4_arrow − (T0 − offset)
```

2秒周期で同期要求を送信。直近10秒以内・RTT 250ms以下から最小RTTを採用する。
往復経路が対称という近似があり、完全な時計同期ではない。`sync_rtt_s`、`sync_age_s`、`clock_offset_s` を残す。
RTT/2はネットワーク非対称による誤差の目安であり、ADC・フレーム・時計ドリフト等を含む全誤差保証ではない。
同期がない場合や負の区間時間は無効として、ゼロに丸めない。
切断・Broker再接続・Jetson再起動時は途中の試行を無効にし、同期を取り直す。

## 通信と照合

通常状態トピック `<state-topic>` のJSONは変更しない。追加トピックも QoS 0 / retain false。

| Topic末尾（`<state-topic>/latency/` 以下） | 送信方向・内容 |
| --- | --- |
| `event` | Jetson→Unity：session、trial_id、t0、onset_method、invalid、audio_sequence、audio_end |
| `result` | Jetson→Unity：event情報＋inference_id、t1、final_class、timestamp_ms、t2、telemetry_dropped |
| `sync/request` | Unity→Jetson：要求id。u1はUnityで保持 |
| `sync/response` | Jetson→Unity：id、session、s2、s3 |

`session + trial_id` は音の試行、`inference_id` は推論結果、通常JSONの `timestamp_ms` は送信メッセージの照合キー。
通常表示は計測情報を待たない。逆順到着に対応し、表示フレームと後着メタデータを照合する。
再送は別試行にしない。初回表示のメタデータが欠落した場合、後続フレームを初回表示と誤認して成功扱いしない。
通常状態は単一Jetson Publisherを前提とする。同一timestampの衝突を見つけたら無効にする。

## CSVの回収

`Application.persistentDataPath/Latency/latency-*.csv` に保存する。
起動時のUnityログ `[Latency] CSV: ...` に実際のパスを出す。有界キューを経由し別スレッドでまとめて書き込む。
Androidの現設定（アプリID `jp.research.ambulancear.complete`）では通常、次で取得できる。

```powershell
& $adb pull /sdcard/Android/data/jp.research.ambulancear.complete/files/Latency ./latency-results
```

`$adb` は使用中のadb.exeのパス。最初の計測情報を受信してから `Observation Seconds` 後に試行を確定する。
最後の試行後も10秒以上待ってから終了・回収する。観測窓の起点はUnityの計測情報受信時点であり、音源再生時間と区別する。

CSVには各区間、警告・矢印の総時間、元時刻、同期情報、累積欠落数、試行状態、`observation_seconds` を残す。
未取得時刻は空欄であり0秒ではない。

CSV末尾には `warning_confidence_pct`（警告初回表示時）と `arrow_confidence_pct`（矢印初回表示時）も記録する。
それぞれ、その表示に使用した通常MQTT状態の `confidence_pct` を0〜100の値で保存する（小数点以下最大3桁）。
初回表示後の判定値で上書きしない。表示がなかった場合や値を取得できなかった場合は空欄であり、0%とは区別する。
警告と矢印が異なるタイミングで表示されれば、Confidenceも異なる場合がある。
この値は表示に使った分類結果のスコアであり、実際の正解率や、T1時点の最初の判定スコアそのものを保証する値ではない。
既存MQTT情報を使用するため、この列追加のためにJetsonを変更する必要はない。Unity APKは再ビルド・再インストールする。
新しいCSVファイルから列が追加され、既存のCSVは変更しない。

| status | 意味 |
| --- | --- |
| `ok` | 警告・矢印の両方を計測 |
| `no_arrow` | 警告を記録したが矢印は未表示（視野外・Unknown・追跡不良等も含む） |
| `no_warning` | 推論情報は届いたが警告表示の記録なし |
| `no_result_metadata` | 開始情報は届いたが対応する推論メタデータなし |
| `invalid` | 時刻不整合、音声欠落、切断、初回表示の照合欠落等。notes参照 |
| `incomplete` | 観測時間終了前に計測終了 |

計測通信もQoS 0のため、eventとresultが両方失われるとUnityは試行の存在を知れない。
CSV行数だけを実験回数とせず、提示回数とtrial_idの欠番も確認する。
`jetson_dropped` / `unity_dropped` は計測キュー等の累積欠落数であり、回線上の全損失を検知しない。
成功平均だけでなく、提示回数・各status件数・同期条件を併記する。

## 検証方法

実施結果は [2026-10-15の検証報告](latency_verification.md) を参照。

Python単体テストとUnity EditModeで時計補正、異常時刻、音声欠落、再送、到着順逆転、CSV、計測OFFを確認する。
`LatencyLoopbackTests` はWindowsの専用venv（`Jetson_Final/.venv-latency`、numpyとpaho-mqtt）を使い、Python→実MQTT Broker→Unity→CSVを試験する。
音声とフレーム境界は合成入力。ReSpeaker、TensorFlow推論、Android実フレーム終端、XREAL光学表示の実測とは区別する。
実機では計測ON/OFFのCPU負荷・フレーム時間も比較する。
