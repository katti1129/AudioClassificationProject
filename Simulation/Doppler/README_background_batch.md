# 距離 × Source速度の一括生成

## GUIでの実行

```matlab
addpath('C:\Users\cpsla\AudioClassificationProject\Simulation\Doppler');
app = background_simulation_gui();
```

**「6. 一括生成」タブ**を使用します。入口は1条件版と共通です。

1. 他タブで救急車／背景WAV、Receiverの位置・速度、Sourceの方向・高さ、地面反射、音圧校正、出力先を設定。
2. 水平最近接距離の一覧、Source速度の一覧、共通の幾何学的最近接時刻を入力。
3. **条件一覧を作成**：幾何配置とWAVヘッダーから一覧を作成。音声の計算・保存はしません。
4. **全条件をチェック**：各条件の伝搬・合成・クリッピングを実際に計算。検査CSVを保存しますが、WAV・信号MAT・図は保存しません。
5. **一括生成**：現在の設定から一覧を作り直し、順番に生成。失敗条件をCSVに記録し、残りの条件を続行します。
6. **一括結果フォルダ**：一覧CSVのある場所を開きます。表の行を選択して**選択条件の出力**を押すと、その条件のWAV保存先を開きます。

設定を変更した場合、表示中の表には旧条件である旨を表示します。一括生成・チェックは古い計画を使わず、毎回現在の設定のスナップショットを作ります。
下部の「WAV生成」は従来どおり1条件版です。一括生成はタブ内の「一括生成」ボタンを使ってください。

## 初期条件と距離の定義

- 水平最近接距離：5、10、20、40 m。
- Source速度：20、40、60 km/h。
- 組合せ：4 × 3 = **12条件**。
- 共通の幾何学的CPA時刻：4 s。
- Receiver：既存タブの初期設定では1.4 m/s、+x方向。
- 音源・背景音：既存タブの設定を共通利用。初期背景はengine_idling、固定RMS SPL 80 dB、CPAの2秒前から4秒間。

入力距離は**水平面の最近接距離**です。CSVに高さを含む3次元距離も併記します。
Source高さ1.5 m、Receiver高さ1.2 mなら、水平距離dに対し3次元距離は `sqrt(d^2 + 0.3^2)` mです。

一括生成ではSourceの初期x/y、速度、静止指定を一覧条件で上書きします。Source方向・高さ、Receiverの全設定は共通です。
これらの上書きは条件ごとの設定コピーに対して行い、1条件版の画面設定そのものは変更しません。

## 最近接時刻をそろえる計算

水平相対速度を `v = Vs - Vr`、vに垂直な単位ベクトルをn、指定距離をd、CPA時刻をTとします。

```text
Source初期水平位置 = Receiver初期水平位置 + d*n - v*T
```

この設定なら、時刻Tの相対水平位置は `d*n` となり、相対速度との内積が0になるため、その時刻に最近接します。
nの向きは元のSourceがReceiverに対して存在した側を採用します。元配置が相対速度の直線上にある場合は、左法線 `[-vy,vx]/norm(v)` を使用します。
Receiverが横切る方向に動く場合にも、相対速度を使って同じ計算を行います。

全条件でSourceを同じ初期位置に固定する方式ではありません。比較条件で最接近の時刻を統一するため、速度ごとに初期位置が変わります。
SourceとReceiverの水平速度が同じ条件ではCPA時刻が一意に定まらず、INVALID／FAILとして記録します。背景なしでもこの条件は一括CPA比較の対象外です。
Source速度0はReceiverが動いていれば使用可能です。両者静止は1条件版を使用してください。

**CPAは同時刻の幾何配置です。**伝搬遅延を考慮した最短経路時刻や受音波形のピーク時刻ではありません。
距離が違えば到達遅延も違います。一括処理によって受音波形を人為的に時間移動して重ねることはしません。
共通CPA時刻は入力サイレンWAVの時間範囲内で指定します。音源の長さや音響モデルは変更しません。

## 背景音・音圧の比較条件

- 同一背景ファイル、同一切出し、同一フェード、同一レベル指定を全条件で使用。
- 距離による検出性能を比較する場合は**固定RMS SPL**を基本とします。
- SNRモードを選択した場合は、各条件の挿入区間サイレンRMSに合わせて背景音圧が変わります。CSVに指定モードと実際のSPL/SNRを記録します。
- 共通CPA基準で背景を置けば、全条件で同じ受音時間区間に配置されます。
- 全条件・全成分で同じ `wavFullScalePa` を使用し、条件別ピーク正規化はしません。
- クリッピングする条件はFAILとし、Pa/FSを自動変更しません。変更する場合は比較条件全体を同じ値で再生成してください。

## 出力と状態

指定した保存先の下に、一意な短いバッチIDのフォルダを作ります。

```text
<保存先>\batches\B_<12文字ID>\
    batch_config.mat
    conditions.csv
    batch_summary.csv
    heatmap_wavs\
        ambulance_CPA5m_V020.wav
        ambulance_CPA5m_V040.wav
        ...
        evaluation_manifest.csv
    C0001_D5m_V20kmh\
        BG_<Simulation ID>\
            final.wav / siren.wav / background.wav / direct.wav / reflected.wav
            result.mat / 各種CSV / PNG（図を有効にした場合）
    ...
```

- `batch_config.mat`：基準設定、距離・速度・CPA設定、各条件の設定コピー、実行モード。
- `conditions.csv`：条件ID、指定／算出CPA、3次元距離、両者の初期位置と速度、共通Pa/FS、入力WAV、背景設定・実効レベル、ピーク、出力パス、状態・失敗理由。
- `batch_summary.csv`：状態別件数。実行が最後まで戻った場合に保存。
- 各条件の既存出力：1条件版と同じ形式で保存。数理モデルは同じ関数を呼び出します。

### AIヒートマップ用の音声まとめ

一括生成が終了すると（キャンセルで途中終了した場合も）、SUCCESSの条件の
`final.wav` だけをバッチ直下の `heatmap_wavs` に自動コピーします。
例: `ambulance_CPA10m_V020.wav`。CPAは水平最近接距離[m]、VはSource速度[km/h]です。
小数条件も `ambulance_CPA10.5m_V20.5.wav` のように保持します。
コピー前後のバイト一致を検査し、再正規化・再エンコード・元ファイルの移動はしません。
他の4成分WAVはこのフォルダに入れません。チェックのみでは作成しません。

`EvaluateSimulationHeatmaps.py` のWAVフォルダ選択画面で、この **heatmap_wavsフォルダそのもの** を選択してください。
バッチ全体を指定すると、元のfinal.wav等は条件タグがなくErrors.csvに記録されます。
背景条件はファイル名に含めないため、異なるバッチの音声は混ぜずに評価してください。
`evaluation_manifest.csv` には背景音・SPL・SNR・CPA時刻など元の条件表と、
コピー元／コピー先、ExportStatus（COPIED/FAIL/SKIPPED）、失敗理由を残します。
Python評価側はこのCSVを自動で設定に反映しません。CPA時刻・評価区間は従来どおり指定してください。
一括結果フォルダボタンからheatmap_wavsを開けます。1条件版の保存方法は変更しません。

過去のバッチも、音声を再生成せず次のコマンドでまとめられます。

```matlab
addpath('C:\Users\cpsla\AudioClassificationProject\Simulation\Doppler');
batchDir = '実際のバッチフォルダの絶対パス'; % conditions.csvのあるフォルダ
[manifest, datasetDir] = export_background_heatmap_dataset(batchDir);
```

既にheatmap_wavsがあれば別のID付きフォルダを作り、上書きしません。
コピー失敗はevaluation_manifest.csvのFAILに記録されます。出力処理全体が失敗した場合は
バッチ直下のheatmap_export_error.csvも確認してください。元のシミュレーション成功件数とは別です。

CSVは条件の開始・完了・失敗・キャンセルごとに更新します。

| 状態 | 意味 |
|---|---|
| READY / INVALID | 一覧作成時の幾何条件判定。音声処理は未検査 |
| PENDING / RUNNING | 待機中／実行中 |
| PASS | 保存なしの音声チェック成功 |
| SUCCESS | WAV等の保存成功 |
| FAIL | 幾何・音声・保存の失敗。ErrorIDとMessageを参照 |
| CANCELLED | 現在の条件を保存開始前にキャンセル |
| NOT_RUN | キャンセルにより実行しなかった条件 |

キャンセルは下部の共通ボタンです。保存中は現在の条件の保存を完了してから停止し、完成済み出力は残します。
再実行は新しいバッチフォルダになります。途中バッチの自動再開・自動上書きは実装していません。
ディスク不足等で保存途中に失敗すると、不完全なファイルが条件フォルダ内に残る可能性があります。SUCCESS以外を完成データとして使用しないでください。
WindowsのMAT v7.3保存パス制限を避けるためIDを短くし、長すぎる出力パスは保存前に拒否します。必要なら保存先を短いパスに変更してください。
最大1000条件まで。リストの重複や式（`1:10`など）は受け付けず、数値列だけを解釈します。

## 設定保存・コマンド実行

GUI下部の設定保存MATには一括設定も含みます。旧1条件版の設定MATも読み込めます。旧ファイルに一括設定がない場合は現在の一括設定を維持します。
「初期設定へ戻す」は1条件・一括設定の両方をリセットします。生成済みファイルは変更しません。

```matlab
config = background_simulation_config();
batch = background_batch_config();
batch.distancesM = [5,10,20,40];
batch.sourceSpeedsKmh = [20,40,60];
batch.cpaTimeSec = 4;
batch.sourceHeadingDeg = 0;
[plan,configs] = background_batch_plan(config,batch); % 保存なしの幾何一覧
[checks,checkDir] = run_background_batch(config,batch,'check');
[results,batchDir] = run_background_batch(config,batch,'generate');
```

## ファイルの役割と検証

| ファイル | 役割 |
|---|---|
| `background_batch_config.m` | 一括条件の初期値 |
| `parse_background_batch_values.m` | evalを使わない数値列解析 |
| `background_batch_plan.m` | 相対運動に基づくCPA配置・条件一覧 |
| `run_background_batch.m` | 順次実行、CSV、失敗継続、キャンセル |
| `export_background_heatmap_dataset.m` | 最終合成音の条件名付きコピーと対応表。過去バッチにも使用可能 |
| `add_background_batch_tab.m` | 一括タブの表示・操作 |
| `background_simulation_gui.m` | 既存GUIへのタブ接続、共通ロック・保存設定 |
| `test_background_batch.m` | 幾何、保存、キャンセル、実WAV12条件の検査 |

音響本体の `simulate_moving_receiver_rms`、`mix_background_audio`、`run_background_simulation` は一括生成のために変更していません。

```matlab
[checks,reportDir] = test_background_batch();
```

出力：`C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_batch_tests\T_<ID>\batch_checks.csv`

テストでは実WAVで12条件を生成し、共通背景波形・CPA・量子化誤差・クリッピング・既存レンダラーとの一致を確認します。実音源12条件のテストは保存時間を抑えるため条件別PNGをOFFにしています。通常GUIのPNG設定は他タブのチェックに従います。
テストは数値・UI・入出力の検証です。聴感の良否、実環境との音圧一致、AIのRecallを保証するものではありません。

## 2026-10-31 検証結果

- 一括生成テスト：**220 PASS / 0 FAIL**。
- 既存の1条件GUI回帰テスト：**74 PASS / 0 FAIL**。
- 新規／変更MATLABコード7ファイル：Code Analyzer指摘0件。
- 実際のambulance.wav＋engine_idlingで12条件を保存。全条件SUCCESS。
- 全条件でCPA 4 s、背景音[2,6) s、背景80 dB RMS SPL、共通Pa/FS。
- 背景の挿入サンプル列は全条件で完全一致。最初／最後の条件は既存レンダラーとの合成音一致も検査。
- 24-bit WAV量子化誤差は1 LSB以内。全成分を通じた最大値は最大約0.099674 FS、クリッピングなし。

一括検証CSV：

```text
C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_batch_tests\T_c9e52f252b76\batch_checks.csv
```

実音源12条件の一覧・出力WAV対応：

```text
C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_batch_tests\T_c9e52f252b76\real_wav\batches\B_9d64f449e0cd\conditions.csv
```

1条件GUI回帰CSV：

```text
C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_background_gui_tests\GUI_tp3b7fb5c2_b15e_4014_8e66_c1aa0ab7af25\gui_checks.csv
```

初回検証でWindowsの長いパスによるMAT保存失敗を検出し、短いバッチIDとパス長チェックで修正後に再実行しました。
初回失敗フォルダは監査用に残しています。完成データには上記のSUCCESSバッチを使用してください。
合計294項目は一括220＋既存GUI74の集計で、失敗修正前の実行や繰り返し回数は加算していません。
