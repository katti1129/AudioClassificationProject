# データ生成パイプライン 検証報告

検証日: 2026-09-30
環境: Windows / MATLAB R2025b / Signal Processing Toolbox

## 結果

- 新規MATLABコード: 23本（GUI 1、+pipeline 17、専用tests 5）
- Code Analyzer: 23本、指摘0件
- 新規テスト: 13/13成功
- 従来の解析・関数テスト: 17/17成功
- 従来のフルパイプラインシナリオ: 9/9成功
- 従来のWAV/Excel/MAT/PNG再読込: 20/20成功

新規テストのコマンド:
~~~matlab
addpath('tests');
r = run_dataset_tests();
~~~

従来の回帰検証:
~~~matlab
legacy = run_all_tests();
~~~

## 新規テストの内容

| テスト | 確認したこと |
|---|---|
| example | CPA20、Source60 km/h、Receiver4 km/h、地面0.8を条件名とconfigへ反映。PVを創作しない |
| identityIncludesHiddenPhysicalSettings | 高さ変更でハッシュが変わり、出力先変更では変わらない。負のReceiver速度を区別 |
| mappingAndValidation | seed連番、同一seed手動指定、選択行適用、seed範囲、速度/加速度プロファイル整合 |
| noInventedGroundPlane | groundのないconfigに反射面を勝手に追加しない |
| separation | WAVと診断結果の保存先分離、パストラバーサル拒否 |
| collisionPolicies | WAV/結果フォルダを対で扱うSkip/Rename/Overwriteと旧結果の退避 |
| roundTrip | 条件表・全base config・オプションのMAT保存/読込一致 |
| continueAfterFailure | 実WAV成功→存在しないWAV失敗→実WAV成功、manifest記録、後続継続 |
| artifactsAndScale | 16 kHz、0.25 s、Pa復元、成分和、4図、4シート、保存先の整合 |
| unchangedAcousticResult | バッチ経由と既存runSimulation直接実行の成分信号・障害物・Pa尺度の一致 |
| skipRenameOverwrite | 実データ再実行時のSKIPPED、REP02、旧結果退避、manifestの一意性 |
| cancelledRowsAndLock | CANCELLED記録、未公開WAV、datasetの同時書込み拒否、lock解放 |
| editSaveLoadRun | 実uifigure上の行生成、一括/選択適用、seed、Save/Load、バッチ開始、進捗100%、操作の復帰 |

テストは短時間の動作検証であり、大規模データセットの生成速度や音響モデルの実測精度を保証するものではない。
音響近似の範囲は既存README/SYSTEM_DESIGNと同じ。

## 確認用の実成果物

最終テストのDataset:
~~~text
C:\Users\cpsla\AudioClassificationProject\Simulation\datasets\Validation_74cc271f
~~~

初回3条件は SUCCESS / FAILED / SUCCESS。
2行目のFAILEDは意図的に指定した DOES_NOT_EXIST.wav による正常なエラー処理検証。
その後、Skip / Rename / Overwrite の検証を行ったため、最終Manifestは3 SUCCESSと1 FAILED、audioには3 WAVがある。
初回条件の図/MATはOverwriteの際に _history へ退避されている。
Attemptsシートで元の実行からの履歴を確認できる。
Validation_* はテスト専用であり、GUIの既定Dataset_001とは別である。

出力比較は、WAVを再読込してPaPerFullScaleを掛け戻し、MAT内のfinalPaとの誤差が1e-5 Pa未満であることを確認した。
同じ物理条件での既存直接呼出しとバッチ結果の各成分は完全一致した。

## 修正した実装上の問題

- UITableのプルダウン候補をMATLABが要求する行ベクトルへ修正。
- 匿名関数が作成時の値を保持する点を考慮し、GUIの条件表取得とキャンセル参照をライブなネスト関数へ変更。
- MATLABの静的ワークスペース制約を避け、ログ取得をローカル関数へ分離。
- 実験名+REP02でExcelのWindowsパス長制約に当たることを実WAVテストで確認。結果フォルダ内は短い診断ファイル名を使用し、図は短い一時パスで生成して移動するよう修正。
- 成功・失敗・スキップ・キャンセル数をGUIの終了表示に反映。
- manifestではRequestedObstacleCountと有効ObstacleCountを分け、障害物OFF時は有効個数0と記録。

## 既存コードの保全

既存main_simulation.m、default_config.m、+acousticsの計算・出力関数、従来4テストファイルは変更していない。
開始時から存在したdefault_config.mのコメント追記は保持した。

開始・終了時のSHA-256:
- default_config.m: EAE64983AD44C721FE840B5CD46EADFEA1DE33B29C3208D8AF169DB1F155FBCD
- main_simulation.m: EACB121A907DFE4E97957CE0726DC27D3674F54CF7135DF208EFB03B78BE37D0

Git上で+acousticsとmain_simulation.mに差分がないことも確認。
既存ファイルへの今回の変更はREADMEへの案内追記のみ。

