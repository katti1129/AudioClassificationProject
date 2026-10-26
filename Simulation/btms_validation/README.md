# BTMS 単一端部・境界連続性の検証環境

## 目的と現在の範囲

既存シミュレーションを変更せず、直接音・鏡面反射音と、**符号・位相を含む回折応答**を合成したときの境界連続性を検証する独立環境です。

実装した対象は、静止した点音源・受音点、剛な凸ウェッジ（外部開口角 π < α ≤ 2π）、およびその有限長端部の一次回折寄与です。α = 2π は厚さゼロの半平面に対応します。音速一定、線形音響、反射係数 +1 の剛境界です。

**有限長の端部を計算することと、有限壁全体の音場を解くことは異なります。** 有限壁の全端部・角・端部間相互作用、複数障害物、移動音源の遅延時間／Doppler、吸音材境界は未実装です。有限端部を無限壁の直接音・反射音に単純加算して「有限壁完成版」と扱う呼び出しは、エラーにしています。

位置の走査は、それぞれ独立した静止音場の比較です。移動音源の音声を生成する処理ではありません。この検証の PASS を、Dataset_002 の音割れ・重なりが解消したという意味には使わないでください。

## 実行方法

MATLAB R2025b で確認しています。追加の音響用 Toolbox は使用しません。

```matlab
cd('C:\Users\cpsla\AudioClassificationProject\Simulation\btms_validation')
result = main_btms_validation();
```

設定を変更する場合：

```matlab
cfg = btms_config();
cfg.quadratureOrder = 128;
result = main_btms_validation(cfg);
```

テストは標準的な境界位置・有限区間を使用する回帰テストです。任意の設定に合わせて期待値を自動生成する万能な検証器ではありません。例えば非常に短い IR 時間窓では、到達音が窓の外になりテストが成立しません。

出力は毎回別の `output/BTMS_日時/` に保存され、既存の実行結果を上書きしません。

| 出力 | 内容 |
| --- | --- |
| `checks.csv` | 各検査の測定値、期待値、許容差、単位、PASS/FAIL/INFO/NOT_EVALUATED |
| `boundary_scan.csv` | 境界両側・境界上での直接音、反射音、回折音、合計の複素伝達値 |
| `convergence.csv` | 積分次数・内部サンプリング周波数による誤差の変化 |
| `export_checks.csv` | CSV・MAT・PNG の保存後の再読込検査 |
| `results.mat` | 設定、テスト結果、IR、複素応答などの数値データ |
| `geometry.png` | 無限ウェッジの横断面と二種類の境界 |
| `boundary_continuity.png` | GA 単独・回折・合計応答と、境界両側の複素差 |
| `impulse_response.png` | 別形式の BTM 参照応答との比較、有限端部の到達区間 |
| `convergence.png` | 積分精度と IR の時間離散化誤差 |

今回は音声 WAV は出力しません。まずインパルス応答と複素周波数応答によって、音源の内容に隠れない形で境界の挙動を検査します。

## ファイル構成と既存コードの利用

| ファイル | 役割 |
| --- | --- |
| `main_btms_validation.m` | 検証・保存・出力の再読込 |
| `btms_config.m` | 条件・積分次数・周波数・保存先 |
| `+btms/validate.m` | 対応範囲と入力値の検査 |
| `+btms/gaussRule.m` | Gauss–Legendre 積分点・重み |
| `+btms/edgeResponse.m` | 有限／無限端部の符号付き BTMS 線積分 |
| `+btms/geometricalResponse.m` | 無限ウェッジの直接音と鏡面反射音 |
| `+btms/totalResponse.m` | 上記三成分の加算。回折音を LOS で ON/OFF しない |
| `+btms/referenceInfiniteBTM.m` | 別の時間変数による無限ウェッジ BTM 参照計算 |
| `+btms/saveFigures.m` | 四種類の図の保存 |
| `tests/run_btms_tests.m` | 定量テストと境界走査 |

既存の `Simulation/tests/+researchtest/check.m` と `row.m` をそのまま再利用しています。既存の `+acoustics/knifeEdgeLoss.m` と旧 `Diffraction/single_obstacle_diffraction_sin.m` は損失量の近似であり、今回必要な符号付き BTMS 応答ではありません。そのため別の計算関数を用意し、本体の回折処理を置換していません。

## 座標・単位・正規化

- 端部は z 軸。座標は `[r, theta, z]`、距離 m、角度 rad、時間 s、周波数 Hz。
- θ = 0 と θ = α が二つの面。0 < θ < α が音の伝わる外部領域です。
- 自由音場の基準は `h(t) = δ(t-R/c)/R`。音源の入力振幅の単位は Pa·m と解釈できます。基準距離 r_ref の音圧 [Pa] を使う場合は、入力に r_ref [m] を掛けます。
- 保存する `h` は各時間ビン内で積分した値 [1/m]。離散畳み込みで **さらに fs で割りません**。
- 音源・受音者が端部上にある場合や、同一点の直接音の特異点を経験的に丸めることはせず、対応外とします。
- 反射係数を既存設定の 0.6 などへ置き換えるだけでは、剛境界の BTMS と整合しません。今回は係数調整を公開していません。

## 実装式と数値積分

Calamia–Svensson (2007) の式 (2)–(5) に基づき、端部 z に沿って積分します。

```
nu = pi/alpha
phi = pi ± thetaS ± thetaR  （四つの組合せ）
m = sqrt(rS^2 + (z-zS)^2),  l = sqrt(rR^2 + (z-zR)^2)
cosh(eta) = (m*l + (z-zS)*(z-zR))/(rS*rR)
beta_i = sin(nu*phi_i)/(cosh(nu*eta)-cos(nu*phi_i))
h(t) = -nu/(4*pi) sum_i integral beta_i/(m*l) delta(t-(m+l)/c) dz
```

実装では次の恒等変換を導出して使い、境界付近の鋭い核を処理します。この変数変換はこの実装の数値積分手法であり、論文の高速近似アルゴリズムそのものを移植したものではありません。

```
u = asinh((z-zS)/rS) + asinh((z-zR)/rR)
eta = abs(u)
L0 = sqrt((rS+rR)^2 + (zS-zR)^2)
L(u)^2 = L0^2 + 4*rS*rR*sinh(u/2)^2
dz/(m*l) = du/L(u)
a = wrapToPi(nu*phi_i), kappa = abs(tan(a/2))
v = atan(tanh(nu*u/2)/kappa)
beta_i du = (2*sign(tan(a/2))/nu) dv
```

各時間ビンに対応する正負の u 区間を有限端部区間と交差させ、v 上の Gauss–Legendre 積分を行います。既定は 64 点です。32 点では境界近傍で設定許容誤差を満たさなかったため増やしました。許容誤差を緩和したわけではありません。

`a=0` の境界上では、その回折項の左右対称極限と、対応する GA 成分の 1/2 重みを組み合わせます。これは境界条件に対応する極限の扱いで、角度に幅を持たせたクロスフェードではありません。丸め誤差の判定にのみ機械精度程度の閾値を使います。

`H` は積分点の実際の遅延を使って `exp(-i*2*pi*f*L/c)` も積分した複素応答です。一方、離散 IR は時刻 n/fs を中心とするビンに面積を割り当てるため、時間離散化誤差があります。両者を同一視せず、サンプリング周波数を上げたときの誤差を記録します。

無限端部の応答には時間方向の尾部があります。既定 0.08 s で打ち切っており、「無限時間まで完全な周波数応答」とは主張しません。次の時間窓に残る応答量を INFO として記録します。有限端部の到達時間が時間窓内に収まる場合は、その端部の全一次寄与を含みます。

## 検査内容と判定

1. 無限端部：時間形式 BTM を独立した変数 `q=sqrt(t-t0)` で積分し、線積分と比較。相対 L1 誤差 ≤ 1e-8。
2. 音源・受音者の交換に対する相反性、最短経路から決まる到達時刻、到達前の無音。
3. 有限端部：区間分割の加法性、端点による応答終了時刻、最短点が区間外のときの到達時刻。
4. 積分次数の収束：既定次数と倍の次数の複素応答差を比較。差を `1/L0` で規格化した値 ≤ 1e-5。
5. 270° ウェッジ／360° 半平面、両面側、直接音の影境界／反射境界を検証。
6. 125, 500, 1000, 2000, 4000 Hz において、角度差 ±1e-2～±1e-6 rad の二側極限を比較。最終複素差 ≤ 1e-3（`1/L0` 基準）。境界上の値と二側平均、IR ビンの連続性も検査。
7. 回折を加えない GA 単独を負の対照とし、理論上の不連続が検出されることを確認。
8. CSV・MAT・PNG を保存後に再読込。FAIL があっても結果を保存し、警告を出す。

複素差を使うため、振幅の絶対値だけが偶然一致して位相が不連続な場合を見逃しにくくしています。PASS の項目数には出力ファイルの検査を混ぜず、別集計にしています。参照計算は同じ解析理論の別実装であり、実測／FEM／BEM による独立した物理検証ではありません。

## 次の段階

1. 有限壁の面・全端部・可視性を整合した幾何表現で定義し、端部寄与の組合せを検証する。
2. 他の数値法／公開参照値と比較し、有限壁で一次回折だけでは不足する条件を明らかにする。
3. 静止条件で人工信号・実際の `data/input/ambulance.wav` を畳み込み、帯域・振幅・遅延を検証する。
4. 時間変化する経路の遅延・Doppler を一貫して扱い、境界を通過する音声で検証する。
5. その後に既存 `+acoustics` との統合と Dataset_002 条件での比較を検討する。

## 出典

- Svensson, Fred & Vanderkooy (1999), *An analytic secondary source model of edge diffraction impulse responses*, JASA 106, 2331–2344. https://doi.org/10.1121/1.428071
- Calamia, Svensson & Funkhouser (2005), *Integration of edge-diffraction calculations and geometrical-acoustics modeling*. https://dael.euracoustics.org/confs/acoustics2008/data/fa2005-budapest/paper/468-0.pdf
- Calamia & Svensson (2007), *Fast Time-Domain Edge-Diffraction Calculations for Interactive Acoustic Simulations*. https://doi.org/10.1155/2007/63560
