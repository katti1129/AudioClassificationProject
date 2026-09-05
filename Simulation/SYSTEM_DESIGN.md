# 統合音響シミュレーション設計（Phase 3）

## 設計方針

完成版は `main_simulation.m` を入口とし、設定構造体を `default_config.m` で一元管理する。実装は `+acoustics` MATLAB packageへ機能分割し、旧スクリプトは検証可能な履歴として保持する。

信号処理は原則として物理音圧 `[Pa]` のまま行う。入力波形は指定した基準距離でのRMS音圧レベルに校正し、各伝搬経路について放射時刻、経路長、幾何拡散、反射損失または回折損失を計算してから時間領域で加算する。

## データフロー

```text
default_config
  ↓ validateConfig / Simulation ID
loadSourceAudio（mono, resample, RMS→Pa）
  ↓
computeTrajectory（Source / Receiver）
  ↓
generateObstacles（seed付き3D AABB）
  ↓
fresnelSelect（全障害物→詳細計算候補）
  ↓
computeObstruction（3D LOS交差、時変マスク）
  ├─ solveDirectPath → synthesizeDirect
  ├─ solveReflectionPath → synthesizeReflections / synthesizeObstacleReflections
  └─ chooseDiffractionEdge / chooseMultipleObstacleDiffractionPath
                              → synthesizeDiffraction
  ↓
direct + reflected + diffracted
  ↓
MAT（Pa正本） / WAV（記録されたPa/full-scale）
  ↓
Excel（Conditions / Obstacles / Paths）
  ↓
PNG（Geometry / Waveforms / Spectrograms / Diagnostics）
```

## 採用する物理モデル

### 軌跡

SourceとReceiverを独立に、初期位置 `p0 [m]`、初速度 `v0 [m/s]`、一定加速度 `a [m/s^2]` で表す。

```text
p(t) = p0 + v0 t + 0.5 a t^2
v(t) = v0 + a t
```

すべて0を設定すれば静止となり、要求された4通りの静止・移動組合せを同じ関数で処理できる。

### 直接音と両者移動ドップラー

受音時刻 `t` に届く音の放射時刻 `tau` を次式の固定点反復で求める。

```text
t - tau = |p_r(t) - p_s(tau)| / c
```

入力信号を `tau` で補間することで、単一正弦波に限定せず実WAV全体を時間ワープする。Receiver運動は受音位置 `p_r(t)` に含まれる。伝搬方向の単位ベクトルを `n` とすると、診断用ドップラー倍率は

```text
d tau / d t = (1 - n dot v_receiver/c) / (1 - n dot v_source/c)
```

で求める。単純な相対速度の大きさではなく、静止媒質に対する両者の伝搬方向速度を使用する。時間ワープによる補間誤差を抑えるため、設定可能な倍率で内部オーバーサンプリングし、全成分の合成後にアンチエイリアスFIRを伴って16 kHzへ戻す。

### 距離減衰

自由音場の点音源を仮定し、基準距離 `r_ref` の音圧から

```text
p(r) = p(r_ref) r_ref / r
```

とする。これは音響強度が概ね `1/r^2`、音圧振幅が `1/r` で減少する球面拡散である。`r_min` 未満は `r_min` に固定し、近距離発散と点音源モデルの適用外を明示する。

### 反射

既存コードと同じ鏡像法を一般の静止平面へ拡張する。鏡像SourceとReceiverを結ぶ線と平面の交点を反射点とし、鏡像経路長を用いて放射時刻を反復する。反射係数は設定可能な圧力振幅係数（符号を許容）とする。

設定平面に加え、各ランダムAABBの上面と4側面を有限・一方向の反射面へ変換し、障害物が保持する材質別圧力係数を使用する。反射2脚は全AABBとのslab交差を評価し、物体を貫通する鏡像経路を除外する。現版は一次鏡面反射、実数・周波数非依存係数、静止面の近似であり、拡散反射と高次反射は含まない。

### 障害物とFresnel候補選別

障害物は地面上のaxis-aligned 3D box（AABB）とし、位置、幅、奥行き、高さ、材質、反射係数を保持する。乱数生成器を局所的にseed設定し、軌跡との安全距離を確保する。

第 `n` フレネル半径

```text
rn(x) = sqrt(n lambda x (D-x) / D)
```

と点楕円体条件 `d1+d2 <= D+n*lambda/2` を用いる。AABB中心の経路和から外接球半径の2倍を引くLipschitz下界で判定するため、箱とフレネル体の完全な解析交差ではなく、影響物を誤って捨てにくい保守的broad-phase判定である。採否と最小クリアランスを全障害物について記録する。

### 遮蔽

LOSはFresnel候補だけでなく全障害物について、Source–Receiver線分とAABBの交差を3軸slab法で判定する。音声サンプルごとの全障害物判定を避け、設定した幾何更新間隔で判定し、音声時刻へ保持補間する。この離散時間化は明示的な数値近似である。

### 回折

既存の単一ナイフエッジ式を3D AABBへ拡張する。有限厚の箱では、上面または側面上の入射端と出射端を同時に求め、Source→端1→同一面→端2→Receiverの最短経路を選ぶ。これにより、旧方式の1回折点経路が箱内部を通過する問題を避ける。

総迂回経路差 `delta = L - d0` と波長 `lambda` から等価パラメータ `v ~= 2 sqrt(delta/lambda)` を求め、ナイフエッジ挿入損失を周波数ごとに算出する。実WAVには短時間Fourier変換（重み付きoverlap-add）を用い、各周波数ビンへ異なる振幅損失を適用する。挿入損失の基準場は直接距離 `d0` の `1/d0`、到達時刻は迂回経路 `L/c` とする。

複数障害物が直列にLOSを遮り、単一箱の迂回経路が別箱に遮られる場合は、直接水平方位を含む鉛直面へ各AABBの有限幅上端を投影し、再帰的upper-majorant（taut path）で全上端制約をクリアする経路を作る。その総経路差に同じ等価損失を適用し、使用フレームを記録・警告する。これは多重エッジUTD、Deygout、Bullingtonの実装ではない。任意形状の厳密UTDには面隣接、くさび角、複素境界インピーダンス等が必要なため、現データだけから一意に仮定しない。

## 出力尺度

- 計算と `.mat` 正本: Pa
- WAV: 全成分共通の `PaPerFullScale` で無次元化
- 既定はデータセット共通の固定 `PaPerFullScale` とし、超過時は保存前にエラー
- 明示的な `adaptive_shared` 選択時のみ、1試行内の全成分へ同じ安全尺度を適用
- 使用した尺度、ピークPa、クリッピング余裕をExcel条件シートへ保存

これにより、各ファイルを個別に最大値正規化せず、同一シミュレーション内の成分差を保存できる。シミュレーション間の絶対比較ではExcelまたはMATに記録した尺度を使用する。

## ファイル構成

```text
main_simulation.m
default_config.m
+acoustics/
  validateConfig.m
  createSimulationId.m
  loadSourceAudio.m
  computeTrajectory.m
  generateObstacles.m
  fresnelSelect.m
  segmentAABB.m
  computeObstruction.m
  computeBrokenPathVisibility.m
  solveDirectPath.m
  synthesizeDirect.m
  solveReflectionPath.m
  synthesizeReflections.m
  synthesizeObstacleReflections.m
  chooseDiffractionEdge.m
  chooseMultipleObstacleDiffractionPath.m
  knifeEdgeLoss.m
  synthesizeDiffraction.m
  runSimulation.m
  writeOutputs.m
  writeMetadataExcel.m
  createFigures.m
tests/
  run_all_tests.m
  run_validation_tests.m
  run_scenario_tests.m
  run_output_validation.m
README.md
PHASE_CHANGELOG.md
VALIDATION_REPORT.md
```

## 再現性

- seedと乱数アルゴリズムを設定・記録する。
- Simulation IDは設定JSON（`Inf`の符号も明示化）から決定論的に生成する。検証では固定IDも指定できる。
- 入力ファイル、設定、障害物表、物理尺度、モデル名を保存する。
- 同じ入力WAV、設定、seed、MATLAB版では同じ数値結果となることをテストする。

## 既知のモデル境界

- 幾何音響と単一エッジ回折のハイブリッドであり、波動方程式の数値解ではない。
- 大気吸収、温度・風の屈折、乱流、地面インピーダンス、サイレン指向性、建物内部残響は初期完成版の対象外。
- 反射係数はユーザが測定値または文献値として与える。根拠のない経験的係数は内部で追加しない。
- 有限AABBのpath-equivalent損失と直列AABBの鉛直taut-pathは明示的近似であり、複素位相を含むUTDや境界要素解ではない。

## 理論資料

- Moving Source/Receiver の放射時刻とドップラー: NASA, *Aeroacoustics of Flight Vehicles*, Eq. 3.156, https://ntrs.nasa.gov/api/citations/19860019440/downloads/19860019440.pdf
- 移動音源WAVのsource-time処理と補間誤差: Ali & Christian (2024), https://doi.org/10.1051/aacus/2024073
- 鏡像法: Allen & Berkley (1979), https://doi.org/10.1121/1.382599
- Fresnel zone・knife-edge近似: ITU-R P.526-16, Sections 2.1 and 4.1, https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.526-16-202511-I!!PDF-E.pdf
- 音響くさび回折とUTDの背景: Pierce (1974), https://doi.org/10.1121/1.1914668
- MATLAB `resample`（アンチエイリアスFIR）: https://www.mathworks.com/help/signal/ref/resample.html
- MATLAB `audiowrite`（浮動小数WAVも有効範囲外はclip）: https://www.mathworks.com/help/matlab/ref/audiowrite.html
