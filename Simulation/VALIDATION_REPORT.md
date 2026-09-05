# 検証報告

検証日: 2026-09-05  
実行環境: MATLAB R2025b, Windows, Signal Processing Toolbox

## 結論

統合版28本はMATLAB Code Analyzerで指摘なし。解析テスト17件、短時間フルパイプライン9シナリオ、実WAV出力再読込20項目はすべて通過した。既定6 sの実サイレンシミュレーションも完走し、WAV、XLSX、MAT、PNGを生成・再読込できた。

## 解析・機能テスト（17/17）

| 検証 | 理論上の期待 | 結果 |
|---|---|---|
| 静止直接経路 | 距離10 m、遅延 `10/343 s`、Doppler 1 | pass |
| 球面拡散 | 距離2倍で音圧レベル差6.0206 dB | pass |
| Source接近 | `1/(1-v_s/c)` | pass |
| Receiver接近 | `1+v_r/c` | pass |
| 両者同速度 | 距離一定、Doppler 1 | pass |
| 地面鏡像 | 鏡像距離＝2脚和、反射点一致 | pass |
| 障害物面反射 | 有効有限面から非ゼロ反射 | pass |
| 反射脚遮蔽 | AABBを貫通する反射を0 | pass |
| 3D LOS | 交差／非交差を区別 | pass |
| seed再現性 | 同seedでAABB完全一致 | pass |
| Fresnel候補 | 軸近傍のみ採用 | pass |
| knife-edge基準値 | `v=0` 約6.03285 dB、`v=-1` 0 dB | pass |
| 有限厚回折 | 2端部経路、正の経路差 | pass |
| broadband回折 | 遮蔽時に実周波数処理が非ゼロ | pass |
| 非遮蔽回折 | 回折成分0 | pass |
| WOLA visibility | clear区間への漏れ0 | pass |
| 直列AABB | taut-path fallback、非ゼロ、明示フラグ | pass |

## フルパイプライン・シナリオ（9/9）

- 障害物なし・両者静止
- 障害物なし・Source接近
- 障害物なし・Receiver接近
- Source/Receiver両者移動
- 地面反射あり
- LOS遮蔽＋回折あり
- LOS非遮蔽障害物あり
- Fresnel領域内外に複数障害物
- 同一seedのランダム障害物再現

全9シナリオが `acoustics.runSimulation` を通してpassした。

## 保存後再読込（20/20）

`data/output/validation/VALIDATION_OUTPUT_SMOKE/` に実 `ambulance.wav` の0.5 sケースを保存し、次を確認した。

- 4 WAVが存在し、全て16 kHz、8,000 samples
- WAVから `PaPerFullScale` を用いてPaを復元可能
- digital peakがheadroom以下
- 固定Pa/full-scaleが設定値と一致し、自動適応なし
- `final = direct + reflected + diffracted`
- ExcelにConditions、Obstacles、Paths、Reflectionsの4シート
- 障害物シートに要求されたID、seed、位置、寸法、反射、LOS、Fresnel、回折点、距離、損失列
- MATにPa正本の `results`
- PNG 4枚が存在し非空

## 既定6 s実行結果

保存先: `data/output/integrated/SIM_E6D80516/`

| 項目 | 実測値 |
|---|---:|
| 出力sample rate | 16,000 Hz |
| 内部sample rate | 32,000 Hz |
| samples | 96,000 |
| 障害物 | 24 |
| Fresnel候補 | 21 |
| LOS遮蔽geometry frames | 326 |
| 回折active frames | 326 |
| 直列AABB taut-path近似frames | 56 |
| 未対応複数回折frames | 0 |
| 回折放射時刻非収束frames | 0 |
| 障害物反射面候補 | 120 |
| 有効な障害物反射面 | 6 |
| final peak | 36.1553135924 Pa |
| final RMS | 6.2688851248 Pa |
| 成分和最大誤差 | `3.5527136788e-15 Pa` |
| WAV scale | 1002.37446725 Pa/full-scale |
| adaptive scale | false |
| final WAV再読込最大誤差 | `1.81272518773e-06 Pa` |

WAVは全4本とも16 kHz、96,000 samples、Excel 4シート、MAT、PNG 4枚を再確認した。スペクトログラムは各パネル最大を0 dBとする共通 `[-80,0] dB` 表示で、周波数軌跡の時間変化を確認できる。

## 解釈上の制限

- WAVの絶対SPLは録音だけから決まらない。既定136 dB RMS @ 1 mは校正仮定である。
- 反射は一次鏡面、実数・周波数非依存の圧力係数である。
- 単一AABB回折は有限厚の最短迂回経路にITU-R型のpath-equivalent magnitude lossを適用する近似である。
- 直列AABBの鉛直taut-pathもUTD/Deygout/Bullingtonそのものではない。使用フレームは必ずメタデータ化され、設定によりエラー停止できる。
- 回折係数の追加複素位相、周波数依存境界インピーダンス、大気吸収、風・温度屈折、乱流、指向性、拡散反射、高次反射は検証対象外である。

したがって、本環境は定義した幾何音響＋path-equivalent knife-edgeモデルについて再現・検証済みであるが、波動方程式や厳密UTDの代替と解釈してはならない。
