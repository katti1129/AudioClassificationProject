# 等速Source・Receiver / RMS基準の実WAVシミュレーション

## 再開時点と追加内容

2026-10-30: 中断時点では既存8スクリプトの確認までで、新規ファイルは未作成でした。
既存ファイルを変更せず、以下を追加しています。

- `moving_receiver_rms_config.m`: 全設定。SI単位、加速度設定なし。
- `simulate_moving_receiver_rms.m`: RMS校正、伝搬・合成。ファイル保存なし。
- `moving_receiver_rms.m`: 実行入口。WAV、Pa単位MAT、CSV、PNG保存。
- `test_moving_receiver_rms.m`: 解析解との比較、入力検証、実サイレンによる保存テスト。

## 実行

MATLABでこのDopplerフォルダをCurrent Folderにし、以下を実行します。

```matlab
[result, outputDir] = moving_receiver_rms;
```

または設定を明示します。

```matlab
config = moving_receiver_rms_config();
config.source.velocityMps = [60/3.6, 0, 0];
config.receiver.velocityMps = [1.4, 0, 0];
[result, outputDir] = moving_receiver_rms(config);
```

静止させる場合は該当速度を `[0,0,0]` にしてください。逆方向は符号を反転します。
両者静止・Sourceのみ移動・Receiverのみ移動・両者移動に対応します。
位置は時刻0の `[x,y,z]` [m]、速度は `[vx,vy,vz]` [m/s]。
現在は正の一定高さと水平移動（vz=0）、音速未満に限定しています。

既定値: Source `[-60,0,1.5]`、Receiver `[0,10,1.2]`、ともに+x方向。
救急車60 km/h、歩行者1.4 m/s (5.04 km/h)。加速度はありません。
入力 `Simulation/data/input/ambulance.wav` を全長使用し、ループしません。
モノラル化・必要時16 kHzリサンプリング後に全入力のRMSを校正します。
入力終了後の伝搬分まで出力するため、出力は入力より長くなります。

## 引き継ぐ数理モデルと変更理由

1. 既存 `norm_realaudio_direct_Greflction.m` のRMS校正方式:
   `p_ref = 20e-6 * 10^(L_ref/20)`、`s_pa = x/rms(x)*p_ref`。
   既定値は自由音場の1 mで136 dB SPL。これは実測された音源校正ではなく仮定です。
   波形のピークをこの値に固定しません。入力全長（無音部分も含む）のRMSです。
2. 既存の球面拡散による音圧 `d_ref/r` を維持。指定最小距離0.1 m未満は
   近接場モデルがないためエラーにし、経験的な振幅補正は追加しません。
3. 地面z=0の無限平面について既存の鏡像法を維持。圧力反射係数0.8。
   直接経路と反射経路を別々に遅延・減衰処理して加算します。
4. 加速版にあった放射時刻を解く考え方を引き継ぎ、既存
   `+acoustics/solveDirectPath.m` と `computeTrajectory.m` を再利用します。
   `t = tau + norm(R(t)-S(tau))/c` を解き、Receiverは受音時刻、Sourceは放射時刻の位置。
   既存APIに必要な加速度欄は内部で常に0に固定します。
   周波数倍率は `(1-n・vR/c)/(1-n・vS/c)`。波形は `s(tau)` を線形補間し、
   別途ピッチシフトを重ねません。単に `t-r(t)/c` とする旧等速版の近似は使いません。
5. 出力ごとのピーク正規化はしません。固定 `wavFullScalePa`（既定約1002.37 Pa）で
   全成分を24-bit PCM WAVに変換。±1以上になる場合は保存前にエラーにします。
   設定を変える場合も、比較する実験全体で同じ換算値を使用してください。
6. 表示する音圧レベルは125 msの矩形移動RMSです。
   ピーク包絡ではなく、騒音計の指数時間重み付きFast特性とも区別します。

## 出力

`Simulation/data/output/doppler_moving_receiver_rms/RMS_<一意ID>/`

- `direct.wav`, `reflected.wav`, `final.wav`: 同一Pa/FSスケール。個別音量調整なし。
- `result.mat`: 未量子化Pa信号、時間、経路、周波数倍率、反射点、設定。
- `calibration.csv`, `signal_summary.csv`: 音圧換算と各成分のRMS/ピーク。
  summaryのRMSは到達前無音・末尾を含む出力全体の値です。
- `geometry_doppler.png`, `waveforms_rms.png`, `spectrograms.png`。
- テスト入口から実行した場合は `checks.csv` も保存。

## 検証

```matlab
[checks, outputDir] = test_moving_receiver_rms;
```

静止/Source接近/Receiver接近/両者同方向/離反で、直線配置の独立解析式
`tau=((c-vR)*t-D)/(c-vS)` と比較。400 Hz正弦波の受音波形も解析波形と比較します。
校正・1/r距離比・鏡像距離/反射波形・成分加算・RMS入力ゲイン不変性・
リサンプリング・不正入力・クリッピング拒否・実WAV全長・WAV/MAT/PNG読み戻しを確認。
線形補間の正弦波NRMSE許容0.4%、遅延残差許容1e-10秒などをCSVに記録します。

## 範囲と限界

- MATLABおよびSignal Processing Toolbox（resample/spectrogram）を使用。
- `Simulation/+acoustics` の2関数に依存します。このフォルダだけのコピーでは動きません。
- 点音源、静止空気、一定音速、水平等速移動、1回の地面鏡面反射。
- 障害物・遮蔽・回折・BTMS・空気吸収・周波数依存地面インピーダンスは対象外。
- 既存の「時間遅延波形×1/r」という運動学的モデルを維持しています。
  厳密な移動モノポール放射の速度依存振幅補正は導入していません。
- 16 kHzでの線形補間を維持。高周波の補間誤差や接近時の帯域超過について、
  全帯域の高精度・アンチエイリアス保証はありません。
- 数値テスト合格は実環境との一致や聴感上の無欠陥を保証しません。
- RMSへの変更だけで、以前の遮蔽・反射境界のON/OFF問題が解決するわけではありません。
  今回の地面は無限平面なので、その有限障害物の境界切替自体を扱いません。

## 実行確認（2026-10-30）

MATLAB R2025bで最終コードを実行し、69項目PASS・0項目FAIL。
新規4つのmファイルのCode Analyzer警告は0件でした。
既存Dopplerの8ファイルと再利用した+acousticsの2ファイルはSHA-256で変更なしを確認。

最終確認の出力:
`Simulation/data/output/doppler_moving_receiver_rms/RMS_tp400e8e87_fdb6_4b8e_86dd_fb47570762b6/`

同フォルダの `checks.csv`、`RESULTS_JA.md`、`final.wav` を参照してください。
先行確認の `RMS_tp53bb065a_610d_4d9c_aee0_9fd637cd30da` はグラフ表示修正前の出力として保持しています。
