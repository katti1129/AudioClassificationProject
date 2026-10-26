# 回折経路切替の時間伸縮修正

更新日：2026-10-22（日本時間）

## 変更範囲

既存の経路探索（単一AABB迂回・複数障害物の垂直taut-path近似）、距離減衰、ITU型ナイフエッジの周波数依存損失を維持し、選択した経路を音声へ接続する処理を変更した。UTDへの移行ではない。直接音・反射音・Dataset_001の保存済みファイルは変更しない。

|ファイル|役割・変更|
|---|---|
|`+acoustics/synthesizeDiffraction.m`|選択経路の識別子を記録。一本の放射時刻配列を無条件に補間する処理を、経路別レンダリングへ置換。既存の周波数損失フィルタはそのまま再使用。|
|`+acoustics/diffractionPathKey.m`|障害物・面・端部・経路モデル・順序付き接触制約による経路識別。|
|`+acoustics/solveFixedDiffractionPath.m`|固定された回折点を通る伝搬の放射時刻を解き直し、真の残差と全AABBへの貫通を検査。|
|`+acoustics/renderDiffractionBranches.m`|同一経路だけを補間。経路切替は独立した遅延・周波数損失で生成して音圧を混合。実際の読み出し時刻・重み・診断値を保存。|
|`tests/measure_signal_and_path_quality.m`|旧データは従来通り診断。新データは選択経路の飛びと実際の経路別読み出し倍率を分離して判定。|
|`tests/test_diffraction_branch_rendering.m`|独立した二遅延の波形参照、誤ったIDの負例、古い放射時刻の補正、無効経路、加速する両端点等を検証。|
|`tests/run_diffraction_branch_validation.m`|旧テスト・人工信号・SEED再生成・既知の実音源切替ケースの比較を実行し、CSV/MAT/WAVを新規フォルダに保存。|

## 修正した問題

### 1. 別経路の遅延を補間していた

旧処理は幾何フレームごとに選び直した経路の放射時刻を一本の配列に並べ、音声サンプル時刻へ線形補間した。このため異なる経路の長さの差が、音源の急激な読み出し速度の変化になっていた。

修正後は同一の経路構成を持つ連続区間だけを一つのトラックにする。経路が消滅して再出現した区間も連結しない。同一障害物でも別の迂回面・端部・近似経路に変われば別トラックとする。

### 2. 最後の反復で経路が変わると、放射時刻と経路点が不整合になる場合があった

旧選択処理の最後の経路長は一つ前の放射時刻で評価されている場合があり、そのまま更新後の放射時刻で残差を作ると見かけ上0になる。選択処理の生の記録を残したまま、レンダラー側で最終的な経路点に対する伝搬式を独立に解く。

固定された経路点列を q1,...,qm とすると、

`t = tau + (|S(tau)-q1| + sum(|qj+1-qj|) + |R(t)-qm|)/c`

を解き、同じ最終tauで再評価した残差を検査する。補正値を`anchorTimeCorrectionSec`に保存する。

補正後の時刻では元の選択経路が別の箱を貫通する場合、隣接する幾何フレームの経路点だけを候補とし、現在時刻で改めて因果性・収束・幾何学的有効性を確認する。有効な候補に限って追跡を継続し、採用元を`recoveredAnchorFromFrame`に残す。回復不能な場合は黙って通過させず、欠落サンプルとして検証FAILになる。

## 切替区間の数値近似

- 同一経路内は従来の線形遅延補間を維持。
- 経路切替の前後の回折点を、それぞれ1幾何更新区間に局所的に固定して継続する。各経路は固有の伝搬時間を持つ。
- 旧経路・新経路それぞれに、既存の広帯域損失フィルタを独立に適用。
- 幾何更新区間内の位置を`alpha=(t-t0)/(t1-t0)`として、音圧重み`1-alpha`と`alpha`で混合。遅延は混合しない。
- 無効な継続経路の重みは0。有効な重みだけを和1に正規化する。これは経路間の混合重みであり、音声のピーク正規化ではない。
- フィルタの窓が切替を跨いでも別経路の読み出し時刻は共有しない。フィルタ用の余白区間も固定経路の伝搬式で評価。

これは**局所的な固定接触点・音圧クロスフェードによるレンダリング近似**であり、厳密な境界回折音場や複素UTD係数ではない。重なった経路の位相差による干渉は残り得る。直接音・反射音の急なON/OFFを直すものでもない。

## 診断データの意味

- `diffraction.emissionTimeSec` / `pathPointsM`：元の選択処理の生データ。修正前との比較用に保持。
- `diffraction.pathKey`：選択した経路の構成ID。
- `diffraction.rendering.branches`：実際に使用した経路別の`timeSec`、`emissionTimeSec`、`weight`、`valid`。
- `diffraction.emissionTimeAudioSec`：有効経路が1つだけの音声サンプルの放射時刻。無音または複数経路の混合時はNaN。混合信号に一つの放射時刻を割り当てない。
- `rendering.anchor*` / `recoveredAnchorFromFrame`：補正した時刻・経路点・無効アンカー/回復履歴。
- `rendering.uncoveredActiveSamples`：幾何上は回折有効だが音声に寄与できる経路がないサンプル数。

既存研究診断での`diffraction_selected_path_jumps`は生の選択時刻の飛び（WARNとして保持）。新データの`diffraction_time_warp`は実際の独立トラックの読み出し倍率を評価する。旧MATにはrenderingがないため、旧診断結果を変更しない。

速度境界は従来と同じ式と余裕0.002を使用する。この余裕は診断の数値許容差であり、読み出し速度のクリップや補正には使わない。

## 実行方法

通常のシミュレーション入口は変更しない。`main_simulation`、GUI、データセット生成は`acoustics.synthesizeDiffraction`経由で新処理を使用する。保存済み音声は自動では変更されないので、比較時は新しいDataset名/出力先を指定する。

MATLABのCurrent FolderをSimulationにして、単体テスト：

```matlab
addpath('tests');
checks = test_diffraction_branch_rendering();
disp(checks);
```

SEED1〜10の再生成と比較（Dataset_001が必要）：

```matlab
addpath('tests');
% 以前の実サイレン diffraction_switch のMATがある場合に設定する。
setenv('ACOUSTICS_BRANCH_BASELINE', '既知の切替ケースのphysical_results.matの絶対パス');
report = run_diffraction_branch_validation();
disp(report.runDir);
```

既知の切替ケースのMATがない場合、その比較はNOT_EVALUATEDとして明記する。人工信号等を省略して合格とはしない。

通常の出力先：`data/output/diffraction_branch_validation/<一意な実行フォルダ>/`

主なファイル：

- `checks.csv`：条件名・検査名・測定値・期待値・許容差・単位・判定。
- `before_after.csv`：修正前の選択経路の異常フレーム数、修正後の実読出し異常サンプル区間数、欠落、RMS、最大隣接サンプル差、出力WAV。
- `branch_metrics.csv`：経路ごとの識別子・評価区間数・運動境界・残差。
- `legacy_unit.csv` / `legacy_scenarios.csv`：既存の基本17項目/統合9ケース。
- `report.mat`：集計と条件別結果。
- `regenerated/`：新しい成分別WAVと物理結果MAT。

フレーム数とサンプル区間数は異なる粒度なので「33サンプルが0になった」等とは解釈しない。

## 未検証・残る制限

今回の変更は時間読み出しの接続不具合に対する修正。実測比較、厳密な直方体回折、UTD、心理音響的な可聴性、AI検知性能は別途検証が必要。境界の最大サンプル差が全ケースで低下することは、この修正の保証ではない。

参考：Raghuvanshi et al., *Precomputed Wave Simulation for Real-Time Sound Propagation*, §5.4 Temporal Interpolation（同じ波面の対応付けと補間）。https://gamma.cs.unc.edu/PrecompWaveSim/docs/paper_docs/paper.pdf

参考：Smith et al., *Doppler Simulation and the Leslie*, DAFx-02（時変遅延によるドップラー）。https://www.dafx.de/paper-archive/2002/DAFX02_Smith_Serafin_Abel_Berners_doppler_leslie.pdf
