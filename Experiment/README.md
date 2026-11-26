# 2台のPCによる4方向音声提示実験

親PCで実験者用GUI・録音・回答記録を動かし、子PCで音源を再生するPythonソフトです。
ARアプリへの表示追加や操作は行いません。支援あり／なしは実験者がAR側で切り替え、GUIには条件を記録します。

## 現在の実験ルール

- サイレンだと判断したときだけWASDで方向を回答。マウスでのクラス回答はありません。
- W=北、D=東、S=南、A=西。最初の有効な押下だけを採用します。
- 親PCの左=西、右=南。子PCの左=北、右=東（`common.py`の`ROUTES`で変更）。
- 回答、またはマイクで検出した発音からの回答期限（初期値10秒）で試行終了。
- 音源を停止し、停止応答と録音保存を確認した後、少なくとも5秒待って次へ進みます。準備処理分だけ間隔は延びます。厳密に5秒周期ではありません。
- 短い音源が先に終わっても回答期限までは待ちます。音源の長さと回答期限は別です。
- otherの無回答はcorrect_rejection、sirenの無回答はmiss。無回答のRTは空欄です。
- 音の検出失敗、早押し、録音欠落、通信異常はinvalidとしてセッションを中断。参加者の誤答には数えません。
- 練習モードは各試行後に停止。「再開 / 次の練習」で進みます。本番は自動進行です。
- 中断セッションへの自動復帰や不成立試行の自動再出題は行いません。再開は新しいセッションとして保存します。

## 重要：計測精度の範囲

NSW-088はWindows 10/11対応・USB有線・単一指向性・ケーブル約4mです。
メーカーはUSBハブや延長ケーブルを介さず接続するよう指定しています。

- 公式仕様：https://hori.jp/products/nsw/karaoke_mic
- 説明書：https://hori.jp/image/2023/03/jpnsw-088_manual_230303.pdf

この実装の回答時間は**実機で校正するまでは暫定値**です。音が入った録音サンプルのADC時刻を、コールバック実行時の時計と`time.perf_counter()`との差で概算変換しています。USB/OSの未知の遅延、コールバック到着の揺らぎ、GUI入力処理や無線キーボードの遅延は自動的には取り除けません。

検出は1msの移動RMSがしきい値を指定時間（初期値3ms）超えた区間の先頭です。物理的な音の最初の瞬間ではなく、検出ルールに基づく時刻です。静かな立ち上がり、暗騒音、方向ごとの感度でずれます。検出器は音源を照合しないため、椅子の音や発話にも反応します。音源先頭の無音も確認してください。

NSW-088を固定したまま4方向すべて、全音源、予定する提示音量で録音を検証してください。方向ごとにマイクを向け直す運用は避けます。四方向を同じ精度で検出できない場合、マイク変更などを検討します。ゲインや提示音量を、検出しやすくする目的だけで本番中に変更しないでください。

波形で開始を確認する検査は検出の検証です。絶対的な計測遅延を確認するには、時刻の分かる基準信号・外部の記録系等との比較が別途必要です。`timing_calibrated=true`は実験者の記録用フラグであり、精度を保証する機能ではありません。`input_time_correction_ms`は校正で求めた値を**発音時刻に加算**します。未校正なら0とfalseのままにします。

## インストール（両方のPC）

Python 3.11以降のWindowsで、PowerShellをこの`Experiment`フォルダで開きます。

```powershell
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements.txt
Copy-Item config.json config.local.json
.venv/Scripts/python.exe check_audio.py --list-devices
```

`config.local.json`を編集します。2台の音声デバイス番号は別々なので、各PCで一覧を確認します。

| 設定 | 内容 |
|---|---|
| host | 親PC側で、子PCのWi-Fi IPv4アドレスを設定 |
| port | 両PCで同じ値。初期値50327 |
| token | 両PCで同じ十分長いランダム文字列に変更。初期値では子PCは起動不可 |
| input_device | 親PCのNSW-088に対応する録音デバイス番号 |
| output_device | 各PCの3.5mm出力に対応する、2ch以上の再生デバイス番号 |
| sample_rate | 初期値48000。マイク・出力が対応するレートに設定し、WAVも統一 |
| gain | 音源に掛ける係数。初期値0.2。両PCで同じ値にする |
| threshold_dbfs | 発音検出のRMSしきい値。初期値-35は仮の値で、実録音で調整必須 |
| min_above_ms | しきい値超過が継続する長さ。初期値3ms |
| onset_timeout_s | 再生指示後に発音を待つ上限。初期値5秒 |
| response_timeout_s | 検出発音からの回答期限。初期値10秒 |
| silence_s | 試行終了後の待機。初期値5秒 |
| settle_s | マイク開始後、検出を有効にする前の待機。初期値1秒 |

token生成例：

```powershell
.venv/Scripts/python.exe -c "import secrets; print(secrets.token_urlsafe(32))"
```

TCP通信は暗号化していません。信頼できる同一LAN内で使用し、インターネットへポート公開しないでください。学内Wi-Fiの端末間通信制限やWindowsファイアウォールの許可は管理方針に従って確認してください。本プログラムは設定を自動変更しません。

## 音源と試行リスト

`sounds/`に**モノラルWAV**を配置します。両PCに同じファイルを置き、レートも設定と合わせます。子PCへの準備時にSHA-256を照合します。ステレオ音源の無断混合や自動音量正規化はしません。

動作確認専用の合成トーンと32試行リストを生成する場合：

```powershell
.venv/Scripts/python.exe make_trials.py --demo
```

DEMO_sirenは単なる800Hzトーン、DEMO_otherは400Hzトーンです。**実験用サイレン音源ではありません。本番に使用しないでください。** 生成後のsoundsとtrials.csvを子PC側にもコピーします。既存ファイルは上書きしません。

本番では`manifest.example.csv`を参考に、`file,class`列を持つmanifestを作成します。

```powershell
.venv/Scripts/python.exe make_trials.py --manifest manifest.csv --output trials_A.csv --repeats 4 --seed 123
```

各音源を各方向からrepeats回出題し、固定seedで並べ替えます。クラス間の回数をそろえるにはmanifestのsiren/other音源数を同数にしてください。音源数×4方向×repeatsが総試行数です。同じ参加者の支援条件間で順番を丸暗記できる設計にならないよう、リストと条件順を事前に決めます。

任意に作成する`trials.csv`の例（ファイルは実在が必要）：

```csv
trial_id,file,class,direction
1,siren_01.wav,siren,north
2,other_01.wav,other,west
```

## 機器チェック

親PCで入力デバイスを設定した後：

```powershell
.venv/Scripts/python.exe check_audio.py --record --seconds 20
```

録音開始の待機後に検出を有効化し、入力ピークと検出時刻を表示します。RMSしきい値とピーク表示は別の量です。ファイルは`results/mic_check_*.wav`に保存されます。チェック中に各スピーカーから提示音を再生し、波形を確認します。Windowsの音声補正・AGC・ノイズ抑制が使われていないかも確認します。

各PCの左右出力を個別に確認：

```powershell
.venv/Scripts/python.exe check_audio.py --play DEMO_siren.wav --channel 0
.venv/Scripts/python.exe check_audio.py --play DEMO_siren.wav --channel 1
```

0=左、1=右。片方からだけ出ることを確認し、Windowsのモノラル音声設定や空間音響等の影響がないか確認してください。音量は低い状態から確認し、実験の提示音圧は参加者位置で測って調整します。マイク録音のスピーカーへのモニター再生は行いません。

## 起動と操作

子PCで実際のLANアドレスを指定（以下のIPは例）：

```powershell
.venv/Scripts/python.exe child_app.py --bind 192.168.1.20
```

親PCのhostを同じIPに設定し：

```powershell
.venv/Scripts/python.exe parent_app.py
```

1. GUIで参加者ID、支援条件、練習／本番、再生リストを設定。
2. NSW-088の入力と親PCのスピーカー出力を明示選択。デバイス名が「USB Audio Device」等の場合もあるため、抜き差しで識別してください。
3. 実際のAR支援条件とGUIの記録条件が一致しているか確認。
4. 「開始」。実験中はこのGUIをフォーカスしたままにする。
5. 練習は「再開 / 次の練習」で次へ。本番は自動。

実験者はマウスでGUI操作、参加者はキーボードでWASD回答とします。この版はWindowsの物理キーボード別の識別を行いません。実験者のキーボードでWASDを押しても回答になります。実験中は実験者が文字入力しないでください。GUIの設定欄は実験中に無効化します。別アプリにフォーカスが移った場合は記録漏れを避けるためセッションを中断します。

「この試行後に一時停止」は現在の試行を完了してから止まります。「緊急停止」は進行中の試行を不成立として中断します。通信待ち中は停止要求への応答に最大約2秒かかり得ます。子PCは接続切断、または2秒間リクエストがない場合に再生を停止します。OSや機器の異常時までの停止保証ではありません。

## 保存内容

`results/日時_参加者ID/`以下に保存：

- `session.json`：条件、設定（通信token除外）、試行リスト、音源ハッシュ、配置対応。
- `events.jsonl`：再生指示、回答入力、停止応答、エラー等のイベント。時刻は親PC内のperf_counter。
- `trials.csv`：正解、回答、RT、検出サンプル位置、有効性、エラー。
- `trial_0001.wav`等：マイクの録音。試行番号はリスト中の順番と対応。

子PCの時計との差でRTを計算しません。Wi-Fiで送るのは制御指示のみです。
validは「ソフトが異常を検出しなかった」という意味であり、計測精度や発音検出の正しさの保証ではありません。`timing_calibrated`と録音の検査を合わせて判断します。録音には参加者の発話等が入る可能性があるため、研究の同意・保管方針に合わせて管理してください。

## 検証

### 接続エラーの切り分け（音声機器なし）

`Connected:`はTCPの接続を受け付けたという意味で、token認証や応答成功の意味ではありません。
新しい`child_app.py`は受信・認証・処理・送信の段階をログに表示します。tokenの値は表示しません。
旧版ではエラー応答をソケットを閉じた後に送ろうとしていたため、親PCに認証エラー等の理由が届かない問題も修正しました。

両PCで最新版のPythonファイルを使用してください。`config.local.json`は各PCの既存設定を維持します。
親GUIを停止し、Macの旧子プロセスをCtrl+Cで停止してから、MacのExperimentフォルダで：

```bash
.venv/bin/python child_app.py --bind 192.168.11.18 --connection-only
```

IPは実際のMacのIPに置き換えます。WindowsのExperimentフォルダで：

```powershell
.\.venv\Scripts\python.exe check_connection.py
```

5回の`PASS`と完了が出れば、TCP・認証・応答は成功です。これは音声の遅延校正ではありません。
失敗時はWindowsの`FAIL`とMacの`stage=...`を確認します。`receive_request`なら要求の受信前／受信中、
`authenticate`ならtoken照合、`send_reply_status`なら応答送信中です。段階情報だけでOSやWi-Fi側の原因が確定するわけではありません。

確認後、MacはCtrl+Cで停止し、`--connection-only`を付けずに起動し直して実験を開始します。
接続テスト中は親GUIから実験を開始しないでください。

```powershell
.venv/Scripts/python.exe -m unittest discover -s tests -v
```

自動検証は採点、無回答と機器不具合の区別、片側への出力配列、検出器のバッファ境界処理、模擬セッションの保存などです。NSW-088・400-SP027・2台の実PCでの実測は別途必要です。SUSの実施と統計解析はこのソフトには含めていません。
