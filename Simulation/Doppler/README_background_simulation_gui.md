# 1条件のWAV生成GUI

距離×Source速度を変える「6. 一括生成」タブを追加しました。詳細は同じフォルダの `README_background_batch.md` を参照してください。既存の1条件生成操作はそのまま使用できます。

## 起動

MATLABのコマンドウィンドウで実行します。

```matlab
addpath('C:\Users\cpsla\AudioClassificationProject\Simulation\Doppler');
app = background_simulation_gui();
```

MATLAB R2025bを使用します。既存シミュレーションと同じく、リサンプリング・スペクトログラムにはSignal Processing Toolboxを使用します。
App Designerの`.mlapp`ではなく、`uifigure`を使用した関数形式のGUIです。

## 操作手順

1. **音源・保存**：救急車WAV、背景音WAV、出力先を指定します。原音／背景切出しを試聴できます。
2. **位置・速度**：Source/Receiverの初期x・y・高さ、速度・方向、静止の有無、地面反射を設定します。
3. **背景音の配置**：開始基準、配置オフセット、元WAVの切出し開始、長さ、フェード、固定RMS SPLまたはSNRを指定します。
4. **音圧・詳細**：fs、音速、音源RMS校正、基準距離、許容最小経路長、共通Pa/FS、PNG出力を設定します。
5. **入力チェック・配置確認**：実際の音響計算・合成を保存なしで実行し、入力範囲やクリッピングを検査します。受音区間と背景音の挿入位置を表示します。
6. **WAV生成**：現在の設定で再計算し、WAV・CSV・MAT・PNGを保存します。事前チェックを省略しても計算関数の入力検証は動きます。
7. **生成結果**：合成音・サイレン・背景音・直接音・反射音を個別再生し、波形・スペクトログラムを確認できます。「図を拡大」で選択中の図を画像ビューアに開けます。

設定は**設定を保存／設定を読込**でMATファイルとして保存・再利用できます。読込対象は自分で作成した信頼できる設定MATにしてください。
保存設定は実効速度を記録するため、「静止」で保存した音源の速度は0として復元されます。
図のチェックを外した場合、結果タブの画像は空欄です。WAV・CSV・MATは引き続き保存します。

## 初期条件

| 項目 | 値 |
|---|---|
| 救急車WAV | `C:\Users\cpsla\AudioClassificationProject\Simulation\data\input\ambulance.wav` |
| Source初期位置 | [-60, 0, 1.5] m |
| Source速度 | 60 km/h、+x方向 |
| Receiver初期位置 | [0, 10, 1.2] m |
| Receiver速度 | 1.4 m/s、+x方向 |
| 加速度 | なし |
| 地面音圧反射係数 | 0.8 |
| fs / 音速 | 16000 Hz / 343 m/s |
| Source基準RMS SPL | 136 dB、1 m |
| 背景音 | UrbanSound8K engine_idling / fold10 / 102857-5-0-0.wav |
| 背景音レベル | 80 dB RMS SPL |
| 配置 | 幾何学的CPAの2秒前から4秒間 |
| 背景元音源切出し開始 | 0 s |
| 各端フェード | 20 ms |

速度方向は水平面で0°=+x、90°=+yです。Sourceはkm/h、Receiverはm/sで入力します。
シミュレーション長は入力WAV全体＋到達遅延の末尾で決まります。この版では任意長への繰返し／切詰めは行いません。

## 数理モデルと振幅の扱い

GUIは次の既存関数を呼び出します。新しい音響モデルを追加していません。

- `simulate_moving_receiver_rms`：実WAVのRMS校正、両者の等速運動、遅延時間解法、1/r減衰、鏡像法による地面反射。
- `mix_background_audio`：受音点の背景音を切出し、必要に応じてリサンプリング・フェード・RMS校正して加算。
- `run_background_simulation`：既存の固定スケール出力、WAV読戻し検査、CSV・MAT・PNG保存。

136 dB・1 mはこの設定の仮定校正値です。入力WAVの収録時音圧を実測したものではありません。
背景80 dBも実験用の指定値です。固定SPLと区間SNRは異なる実験条件です。
区間SNRでは背景挿入区間全体のサイレンRMSに対して背景ゲインを決定します。刻々のSNRを一定にする処理ではありません。
背景音は「Receiverで録音された音」として加え、救急車の速度・距離を背景音に適用しません。

合成後の最大値正規化やリミッターは使用しません。全成分・比較条件で共通のPa/FSを使い、クリッピングする設定は保存前に停止します。
生成結果の試聴にも同じPa/FSを使用します。原音試聴は未校正PCMなので、生成結果とは音量が異なります。PCの再生音圧は校正していません。

CPAは同時刻のSource/Receiver位置による幾何学的最近接時刻で、伝搬遅延を含む最短経路時刻とは別です。
両者静止／同一速度などCPAが一意でない条件、CPAが観測区間外の条件では、配置基準を「録音開始」にしてください。
背景音が短い場合、配置が受音区間外の場合などは自動補正せず、エラーを表示します。

## 出力

初期保存先：

```text
C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_background\BG_<一意ID>\
```

- `final.wav`：合成音
- `siren.wav`：直接音＋地面反射音
- `background.wav`：配置・校正後の背景音
- `direct.wav` / `reflected.wav`：サイレン伝搬成分
- `result.mat`：Pa単位信号、設定、経路、背景挿入マスクなど
- `background_settings.csv`：配置、校正ゲイン、実効RMS SPL/SNR
- `signal_summary.csv`：成分別RMS・ピーク
- `calibration.csv`：共通Pa/FS、音源校正・入力パス
- `window_metrics.csv`：1秒区間ごとのRMS/SNR、背景音被覆率
- `background_waveforms.png` / `background_spectrograms.png`：図を有効にした場合

背景挿入マスク／被覆率はAIの正解ラベルではありません。このGUIではRecallなどのAI評価値を計算しません。
設定を変更しても、結果タブの再生対象は直前に正常保存された音声です。次の生成が完了するまで旧結果であることを表示します。

## キャンセルとエラー

- 二重実行を禁止し、処理中は設定・選択ボタンを無効にします。
- キャンセルは計算開始前／伝搬計算後／保存開始前の区切りで反映します。計算中に押しても即座に割り込みません。
- 保存開始後はキャンセル・ウィンドウ終了を受け付けず、保存完了まで待ちます。
- 処理中に閉じようとした場合はキャンセルを要求し、処理終了後に再度閉じる操作が必要です。
- 計算・入力エラーは下部に表示し、操作可能な状態に戻します。
- ディスク不足など保存途中のI/Oエラーでは不完全な出力フォルダが残る可能性があります。その場合は成功として表示せず、直前の成功結果を維持します。

`run_background_simulation(config)`の既存呼出しは変更不要です。GUI用の第2引数として任意の進捗・キャンセル関数を追加しました。数値計算式は変更していません。

## 検証

```matlab
addpath('C:\Users\cpsla\AudioClassificationProject\Simulation\Doppler');
[checks,reportDir] = test_background_simulation_gui();
```

検査結果は次へ保存します。

```text
C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_background_gui_tests\GUI_<一意ID>\
```

`gui_checks.csv`は各項目を随時書き出します。中断されたテストのCSVには実施済み項目のみが含まれるため、最終のPASS件数／完了メッセージも確認してください。
`gui_*.png`はMATLABの実GUI画像、`output_directory.csv`は生成した実音源結果との対応です。

対象は設定変換、4移動組合せ、設定保存復元、不正入力、エラー後復帰、二重実行防止、キャンセル、実WAVでの既存計算との一致、WAV読戻し、CSV・画像保存です。
自動テストは音響モデルの実環境一致や聴感を保証しません。ネイティブのファイル選択ダイアログの手操作、スピーカーの再生品質は自動評価対象外です。

このGUIの対象外：障害物・ナイフエッジ・BTMS・加速度・複数背景音・AI推論。既存のデータセット生成GUIとは独立しています。一括生成は「6. 一括生成」タブに追加しています。

## 2026-10-31 実行結果

MATLAB R2025bで以下を完了しました。

- 最終版GUIテスト：74 PASS / 0 FAIL。
- 既存背景音テストの回帰確認：71 PASS / 0 FAIL。
- GUI・実行関数・GUIテストのCode Analyzer：各0件。
- GUIで保存した直接音・反射音・サイレン・背景音・合成音は、同じ設定の既存計算関数とサンプル単位で完全一致しました。
- 5成分の24-bit WAV読戻しは、共通Pa/FSに対する量子化誤差が1 LSB以内。クリッピングなし。

最終GUIテストCSV：

```text
C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_background_gui_tests\GUI_tp348a4f35_2216_4356_974e_2c2ee034ea01\gui_checks.csv
```

実音源の生成結果：

```text
C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_background_gui_tests\GUI_tp348a4f35_2216_4356_974e_2c2ee034ea01\audio\BG_tp6288d463_107c_4c24_8278_5175eb21a201\final.wav
```

既存背景音テストCSV：

```text
C:\Users\cpsla\AudioClassificationProject\Simulation\data\output\doppler_background\BG_tpd83ab3fa_016c_46a3_a3e4_28286251c62e\checks.csv
```

GUIテストの前2回も各74 PASSですが、上記の最終実行を参照してください。145項目は異なる2テスト群の合計であり、再実行回数は加算していません。
