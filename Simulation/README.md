# 統合救急車サイレン音響シミュレーション

## 目的

本環境は、救急車サイレン検知AIの評価用音声を、Source（救急車）とReceiver（ユーザ）の幾何配置および運動から生成するMATLAB実装である。波形を経験的に加工するのではなく、各伝搬成分の経路長と放射時刻を求め、物理音圧 `[Pa]` の尺度で合成する。

従来の `Direct/`、`Direct_GReflection/`、`Direct_GReflection_WReflection/`、`Doppler/`、`Diffraction/`、`fresnel/` の各スクリプトは削除していない。完成版は、それらに実装されていた `1/r`、遅延補間、鏡像法、放射時刻反復、Fresnel候補抽出、knife-edge損失を `+acoustics/` の関数へ整理・一般化したものである。詳細な対応は `EXISTING_CODE_AUDIT.md`、設計判断は `SYSTEM_DESIGN.md` を参照する。

## 必要環境

- MATLAB R2021a以降を推奨（開発対象はR2025b）
- Signal Processing Toolbox
  - `resample`
  - `spectrogram`
- 入力WAV。既定値は `data/input/ambulance.wav`

## 最短の実行方法

MATLABで本フォルダをカレントフォルダにし、次を実行する。

```matlab
main_simulation
```

コードから設定を変更する場合は次のようにする。

```matlab
config = default_config();
config.source.initialPositionM = [-50, 0, 1.5];
config.source.initialVelocityMps = [60/3.6, 0, 0];
config.receiver.initialPositionM = [0, 10, 1.2];
config.receiver.initialVelocityMps = [0, 0, 0];
config.obstacle.seed = 42;
config.reflection.planes(1).pressureReflectionCoefficient = 0.6;

results = acoustics.runSimulation(config);
```

位置 `[x y z]` はm、速度はm/s、加速度はm/s²、時間はs、周波数とサンプリング周波数はHzで指定する。

## SourceとReceiverの運動

両者は同じ一定加速度モデルを使用する。

```text
p(t) = p0 + v0 t + 0.5 a t^2
v(t) = v0 + a t
```

そのため、次の4条件を設定値だけで表せる。

| 条件 | Source velocity/acceleration | Receiver velocity/acceleration |
|---|---:|---:|
| 両者静止 | 0 | 0 |
| Sourceのみ移動 | 任意 | 0 |
| Receiverのみ移動 | 0 | 任意 |
| 両者移動 | 任意 | 任意 |

## 信号処理モデル

### 放射時刻とドップラー

受音時刻 `t` に届く音の放射時刻 `tau` を

```text
t = tau + norm(receiver(t) - source(tau))/c
```

から反復計算する。入力WAVを `tau` で補間する時間ワープそのものがドップラーを生むため、別のpitch係数は掛けない。Receiver位置は受音時刻、Source位置は放射時刻で評価する。診断用の瞬時周波数倍率は

```text
alpha = (1 - dot(n, v_receiver)/c) / (1 - dot(n, v_source)/c)
```

である。既定では内部32 kHzで処理し、全成分合成後にアンチエイリアスFIRを用いて16 kHzへ戻す。

### 距離減衰

入力WAVを `referenceDistanceM` におけるRMS音圧へ校正し、各経路に

```text
gain = referenceDistanceM / pathLengthM
```

を適用する。これは自由音場の点音源における球面拡散、すなわち音圧振幅 `1/r`、強度 `1/r^2` に対応する。点音源近似が成立しない極近距離で発散しないよう `minimumDistanceM` を使用する。

### 反射

既存コードの鏡像法を、移動するSource/Receiverと有限面へ一般化した一次鏡面反射である。設定平面（既定は地面）に加え、ランダムAABBの上面と4側面を一方向の有限反射面として扱う。各障害物の材質に設定された圧力反射係数が、実際の障害物面反射へ使用される。反射のSource→反射点と反射点→Receiverの両脚は全AABBとの交差を確認し、物体を貫通する反射は除外する。

圧力反射係数は符号を持つ振幅係数であり、エネルギー反射率ではない。既定値は測定値ではないため、対象路面・壁材の測定値または根拠ある文献値に置き換える必要がある。現版の係数は周波数非依存で、拡散反射は含まない。

### 障害物、Fresnel候補、遮蔽

障害物は地面上のaxis-aligned 3D boxとしてseed付きで生成する。Source/Receiver軌跡との重複を避け、ID、位置、3辺、材質名、圧力反射係数を保持する。

全障害物に詳細回折計算を行う前に、指定した最低解析周波数のFresnelゾーンと交差する可能性がある箱を保守的に抽出する。これは物体の削除ではなく、回折計算のbroad phaseである。LOS判定と反射脚の遮蔽判定は、安全のためFresnel除外後ではなく全障害物を対象とする。採用・除外結果はExcelへ残る。

LOS遮蔽は高さだけでなく、3D線分と箱のslab交差判定で求める。時変幾何は `geometryTimeStepSec` 間隔で更新するため、この時間離散化は数値近似である。

### 回折

有限厚AABBでは単一の点だけを経由すると一方の脚が箱内部へ入るため、上面または側面上に「入射側端部」と「出射側端部」を求め、Source→端部1→面上→端部2→Receiverの最短有効経路を使う。経路差 `delta` と波長 `lambda` から

```text
v ~= 2*sqrt(delta/lambda)
```

を計算し、既存コードにもあったITU-R P.526の単一knife-edge近似を「総迂回経路に等価な挿入損失」として周波数ビンごとに適用する。実WAVは短時間Fourier変換のweighted overlap-addで処理する。ITUの挿入損失は同じSource–Receiver間の自由音場を基準とするため、幾何拡散は直接距離の `1/D`、遅延は迂回経路長 `L/c` を使う。

複数AABBが直列に遮蔽し、どの単一箱迂回経路も別の箱に遮られる場合は、直接水平方位を含む鉛直面内で、各箱の上端制約を満たすtaut pathを再帰的に構成する。その総経路差にも同じpath-equivalent損失を適用し、使用フレームを `multiplePathApproximationUsed` に保存する。これはDeygout/Bullington/UTDそのものではなく、スカラー音響の明示的な工学近似である。既定では使用時に警告し、設定によりエラーまたは警告抑止を選べる。楔角、境界インピーダンス、有限端・頂点回折が定義できる場合は、Pierce/UTD等へ置換すべきである。

## コード構成

| ファイル／フォルダ | 役割 |
|---|---|
| `main_simulation.m` | 既定設定を読み、全処理を1回で実行する入口 |
| `default_config.m` | SI単位の実験条件、モデル選択、保存条件を一元管理 |
| `+acoustics/loadSourceAudio.m` | WAV読込、mono化、FIR resample、RMS音圧校正 |
| `+acoustics/computeTrajectory.m` | Source/Receiverの一定加速度軌跡 |
| `+acoustics/solveDirectPath.m` | 両者移動の放射時刻、遅延、距離、Doppler倍率 |
| `+acoustics/solveReflectionPath.m` | 鏡像Sourceによる移動端点の一次反射経路 |
| `+acoustics/synthesizeReflections.m` | 設定平面反射と反射脚遮蔽 |
| `+acoustics/synthesizeObstacleReflections.m` | AABB上面・側面の有限反射 |
| `+acoustics/generateObstacles.m` | seed付きランダムAABB生成 |
| `+acoustics/fresnelSelect.m` | Fresnel楕円体による回折候補の保守的選別 |
| `+acoustics/segmentAABB.m`, `computeObstruction.m` | 厳密slab法による3D LOS交差 |
| `+acoustics/computeBrokenPathVisibility.m` | 反射2脚と全障害物の交差 |
| `+acoustics/chooseDiffractionEdge.m` | 有限厚単一AABBの2端部迂回経路 |
| `+acoustics/chooseMultipleObstacleDiffractionPath.m` | 直列AABBの鉛直taut-path近似 |
| `+acoustics/knifeEdgeLoss.m`, `synthesizeDiffraction.m` | ITU-R型周波数依存損失とWOLA合成 |
| `+acoustics/runSimulation.m` | 全データフローと成分合成 |
| `+acoustics/writeOutputs.m`, `writeMetadataExcel.m`, `createFigures.m` | WAV/MAT、XLSX、PNG保存 |
| `tests/` | 解析テスト、フルシナリオ、保存後再読込検証 |
| `tests/run_all_tests.m` | 上記3検証スイートを一括実行 |

## 出力

既定の保存先は次のとおりである。

```text
data/output/integrated/<SimulationID>/
├─ audio/
│  ├─ <ID>_direct.wav
│  ├─ <ID>_reflected.wav
│  ├─ <ID>_diffracted.wav
│  └─ <ID>_final.wav
├─ figures/
│  ├─ <ID>_geometry.png
│  ├─ <ID>_waveforms.png
│  ├─ <ID>_spectrograms.png
│  └─ <ID>_diagnostics.png
├─ <ID>_metadata.xlsx
└─ <ID>_physical_results.mat
```

最終確認では既定の実サイレン6 s条件を `SIM_E6D80516` として実行し、`data/output/integrated/SIM_E6D80516/` の全成果物を再読込確認した。

MATファイルの信号はPa単位の正本である。WAVは全成分・全試行で共通にできる固定 `PaPerFullScale` で無次元化し、各WAVを個別に最大値1へ正規化しない。既定の `wavClippingPolicy="error"` では設定full-scaleを超えた試行を保存前に停止するため、条件間の物理音圧差を維持できる。明示的に `"adaptive_shared"` を選んだ場合だけ、その試行の全成分に共通尺度を拡大し、値をExcelとMATへ記録する。MATLAB `audiowrite` は±1を超えるデータをclipするため、この尺度管理を省略してはならない。

Excelには少なくとも次を保存する。

- `Conditions`: 入出力、Source/Receiver条件、音速、校正SPL、seed、各設定反射面、サンプルレート、WAV尺度
- `Obstacles`: 全障害物の寸法・材質、反射利用、区間内判定、LOS遮蔽、Fresnel採否、回折利用、2回折点・距離・損失
- `Paths`: 直接・反射・回折経路の集約診断
- `Reflections`: 設定平面および障害物面ごとの係数、有効フレーム、遮蔽フレーム、経路長、遅延

## 検証

```matlab
addpath(genpath(pwd));
reports = run_all_tests();
```

個別に確認する場合は `run_validation_tests`、`run_scenario_tests`、`run_output_validation` を実行する。

検証項目は次を含む。

- 両者静止時の遅延 `distance/c` とドップラー倍率1
- 距離倍増時の音圧差約6.0206 dB
- Source接近、Receiver接近、両者移動の理論ドップラー倍率
- 鏡像距離と折れ線反射経路長の一致
- 3D AABBの遮蔽／非遮蔽
- seedによる障害物再現性
- Fresnel領域内外の候補分離
- `v=0` でknife-edge損失約6.03 dB
- 遮蔽時のみ回折成分が生成されること
- 有限厚AABBの2端部迂回経路と直列AABBの鉛直taut-path
- 障害物面反射、および障害物に遮られる反射脚の除外
- 9種類の短時間フルパイプラインシナリオ
- 4種WAVの16 kHz・長さ・Pa復元、Excel必須列、MAT、PNGの保存後再読込

`run_output_validation` は実際の `ambulance.wav` を使った0.5 sの成果物を `data/output/validation/VALIDATION_OUTPUT_SMOKE/` に残す。最終確認時点では解析テスト17件、統合シナリオ9件、出力検証20項目がすべて通過している。詳細は `VALIDATION_REPORT.md` を参照する。

## 設定上の重要な注意

- WAVだけから絶対SPLは分からない。`referenceSPLdB` と `referenceDistanceM` は、録音校正または研究上の仮定である。
- `pressureReflectionCoefficient` は対象材質の測定値または根拠ある文献値へ置き換える。
- `fresnel.frequencyHz` は候補抽出対象帯域の最低周波数にする。低いほどゾーンが広く、安全側だが計算候補が増える。
- `diffraction.unsupportedMultiplePathAction` は直列障害物用のpath-equivalent近似を使ったときの動作を `"warning"`、`"error"`、`"ignore"` から選ぶ。研究データの厳格な生成では `"error"` も選択できる。
- `output.wavClippingPolicy="error"` と、データセット全体で共通の `fullScaleSPLdB` を推奨する。
- Source/Receiver速度は音速未満を前提とする。
- 大気吸収、気象屈折、乱流、音源指向性、複素地面インピーダンス、拡散反射、高次反射は現版に含まれない。

## 主な理論資料

- NASA, *Aeroacoustics of Flight Vehicles*, moving Source/Observer retarded time: https://ntrs.nasa.gov/api/citations/19860019440/downloads/19860019440.pdf
- Ali & Christian (2024), source-time Doppler auralization: https://doi.org/10.1051/aacus/2024073
- Allen & Berkley (1979), image-source method: https://doi.org/10.1121/1.382599
- ITU-R P.526-16, Fresnel zone and single knife-edge approximation: https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.526-16-202511-I!!PDF-E.pdf
- Pierce (1974), acoustic diffraction around corners/wide barriers: https://doi.org/10.1121/1.1914668
- MATLAB `resample`: https://www.mathworks.com/help/signal/ref/resample.html
- MATLAB `audiowrite`: https://www.mathworks.com/help/matlab/ref/audiowrite.html

## 旧コードとの関係

旧スクリプトは教育用・回帰確認用として残している。統合版の正本は `main_simulation.m`、`default_config.m`、`+acoustics/`、`tests/` であり、条件別データ生成では旧Dopplerスクリプトの冒頭値を直接書き換えず、設定構造体を使用する。各Phaseの変更理由は `PHASE_CHANGELOG.md`、旧19本との対応は `EXISTING_CODE_AUDIT.md` に記録している。
