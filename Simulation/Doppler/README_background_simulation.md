# 背景音合成版（既存Dopplerモデルをそのまま使用）

## 実行方法

MATLABで `Simulation/Doppler` をCurrent Folderにして実行します。

```matlab
[result, outputDir] = run_background_simulation;
```

既定値: Source 60 km/h、Receiver 1.4 m/s、ともに+x方向、加速度なし。
初期位置・高さ・サイレン音圧・地面反射は `moving_receiver_rms_config` と同一。
背景音はコピー済みUrbanSound8Kのエンジン音 `102857-5-0-0.wav`。
最近接の2秒前から4秒、80 dB SPL相当の固定RMS、両端20 msの編集用フェード。
80 dBはデモ設定値であり、この録音の実測音圧や道路の代表値ではありません。
この録音の聴取確認、サイレン混入確認、AI学習データとの独立性確認は未実施。

## 数理モデルを引き継ぐ方法

`run_background_simulation` → **既存の `simulate_moving_receiver_rms` を直接呼び出す**
→ `mix_background_audio` → WAV・MAT・CSV・PNG保存。

元のDopplerファイルや `+acoustics` は変更しません。
Source/Receiverの軌跡、放射時刻方程式、線形補間、1/r音圧減衰、地面鏡像反射、
入力の全長RMS音圧校正は従来のままです。加速度は常に0です。

背景音は受音点で聞こえる既録音の音として加算します。
背景音を救急車の伝搬処理に通さず、救急車のドップラーや距離減衰をかけません。
周囲の全音源位置・移動を再現する空間音響モデルではありません。
元録音に含まれる反射や機器特性等も残ります。

## 設定例

```matlab
config = background_simulation_config();
config.background.file = 'C:/path/to/background.wav';
config.background.sourceStartSec = 0;      % 背景音WAVの読み出し開始 [s]
config.background.timeReference = 'cpa';  % 'start' または 'cpa'
config.background.startOffsetSec = -2;    % 基準からの挿入オフセット [s]
config.background.durationSec = 4;        % 使用時間 [s]
config.background.mode = 'fixed_rms';
config.background.splDb = 80;             % 無補正RMS音圧レベル [dB re 20uPa]
config.background.fadeSec = 0.02;          % 編集による急な切断を和らげる両端フェード
[result, outputDir] = run_background_simulation(config);
```

受音信号の先頭から2秒後に挿入する場合:

```matlab
config.background.timeReference = 'start';
config.background.startOffsetSec = 2;
```

SNRを指定する場合:

```matlab
config.background.mode = 'snr';
config.background.snrDb = 0;
```

無効化すると背景を読み込まず、元の受音信号をそのまま返します。

```matlab
config.background.enabled = false;
```

## 挿入時刻とCPAの定義

`cpa`は同じ時刻のSourceとReceiverの幾何学的距離が最小になる時刻です。
相対位置d0=S0-R0、相対速度v=Vs-Vrとして `t_cpa=-dot(d0,v)/dot(v,v)`。
地面反射や放射時刻はCPA定義には使いません。
したがって「直接音の遅延付き経路長が最小になる受音時刻」や「RMS最大時刻」とは別です。
計算されたCPA時刻を受音時間軸の基準として使用します。
相対速度0で一意のCPAがない場合やCPAが観測区間外の場合は、cpa指定をエラーにします。
両者静止等では `timeReference='start'` を使ってください。

指定秒数は最寄りサンプルへ丸め、実際の開始・終了・読み出し開始を保存します。
挿入区間は `[開始, 終了)`（終端を含まない）。元ファイル不足、出力範囲外はエラーです。
自動切り詰め・ループ・ランダム選択は実装していません。

## RMS・SNRの定義

背景をモノラル化、必要時リサンプリング、指定区間切り出し、編集用フェードの順で処理。
フェードは信号編集処理であって、伝搬や物理的音源の発音過程のモデルではありません。
フェード後の区間全体のRMSをb_rms、同じ受音区間のサイレンRMSをs_rmsとします。

- fixed_rms: `gain = (20e-6*10^(splDb/20))/b_rms`
- snr: `gain = s_rms/(b_rms*10^(snrDb/20))`
- `background_pa = gain*background_segment`
- `final_pa = siren_pa + background_pa`

固定音圧方式ではサイレン振幅から独立に背景を調整します。
SNR方式では同区間のサイレン（直接音＋地面反射）のRMSが基準です。
背景区間内の無音やフェードも含み、活動区間だけを推定する処理はありません。
全区間のSNRと時間ごとのSNRは異なります。
RMSはA/C周波数補正なし。法定サイレン音量の測定手順との一致は保証しません。

## 出力

`Simulation/data/output/doppler_background/BG_<ID>/`

- `direct.wav`, `reflected.wav`: 救急車の直接音・地面反射音。
- `siren.wav`: 背景音を加える前の救急車受音信号。
- `background.wav`: 指定時刻に配置した背景音。区間外は0。
- `final.wav`: 合成音。
- `result.mat`: 上記Pa波形・設定・伝搬経路・背景区間マスク。
- `background_settings.csv`: 背景ファイル・使用区間・CPA・ゲイン・設定/実測SNR。
- `calibration.csv`: Simulation ID、入力サイレン、共通Pa/FS換算値。
- `signal_summary.csv`: 全長RMS・ピーク。
- `window_metrics.csv`: 受音先頭基準の1秒窓ごとのRMS・SNR・背景区間の占有率。
  最後の窓は1秒未満の場合があります。背景なし窓のSNRはNaN。
- `background_waveforms.png`, `background_spectrograms.png`。

背景区間マスクは「配置区間」であり、サイレンの正解ラベルではありません。
AIのRecallは本コードでは計算しません。評価時にはAI入力窓全体が対象区間に入るかを確認します。

全WAVは同じ固定 `wavFullScalePa` で24-bit PCM化し、ピーク正規化しません。
いずれかが±1以上ならファイル保存前にエラーにします。
変更する場合は比較条件全体で同じ換算値を使ってください。

## 検証

```matlab
[checks, outputDir] = test_background_simulation;
```

合成区間・CPA・読み出し開始・サンプル丸め・固定RMS・SNR・フェード・再現性・
無効化・ステレオ/リサンプリング・異常入力・実エンジン/雨音での合成・保存を検査。
元モデルとの救急車信号のサンプル単位一致も検査します。
結果は固定RMSエンジン例の `checks.csv` と `example_outputs.csv` に保存します。
既存の物理モデルの限界は元の `README_moving_receiver_rms.md` を参照してください。

## 検証済みの出力（2026-10-31）

MATLAB R2025b: 今回の合成・入出力テストは71 PASS / 0 FAIL。
新規4つのmファイルのCode Analyzer指摘は0件。
既存Dopplerの12個のmファイルはSHA-256照合で変更なし。
実WAVで旧モデルとのsiren/direct/reflectedの差は全サンプルで0。

`Simulation/data/output/doppler_background/` 以下:

- 固定80 dBエンジン: `BG_tpe57da0b5_9d23_45cb_a1dc_e02b25619ffe`
- SNR 0 dBエンジン: `BG_tp74da6801_5a10_47d6_84c0_3d4c9e1e7aed`
- 固定80 dB雨: `BG_tp4f02d77c_e9bf_40c7_b631_7344103a65e4`

最初のフォルダに `checks.csv`、`example_outputs.csv`、`RESULTS_JA.md` を保存。
全例とも実挿入区間は[1.930125, 5.930125)秒。
固定80 dBの区間SNRは約34.05 dB。SNR 0 dB例の背景音は約114.05 dB相当であり、
現実の道路の代表音量ではなく人工的な耐雑音試験条件です。
