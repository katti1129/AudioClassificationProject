using UnityEngine;
using TMPro;
using System;
using System.Net.WebSockets;
using System.Threading;
using System.Threading.Tasks;
using System.Text;

// JSONの "label" と "confidence" だけ取り出すためのクラス
[Serializable]
public class InferenceResult
{
    public string label;
    public float confidence;
}


public class AudioSender : MonoBehaviour
{
    public TextMeshProUGUI resultText;

    const int SAMPLE_RATE = 48000;
    const int WINDOW_SEC = 1;
    const int WIN_SAMPLES = SAMPLE_RATE * WINDOW_SEC;

    float[] ringBuffer = new float[WIN_SAMPLES];
    int bufferPos = 0;

    ClientWebSocket ws;

    async void Start()
    {
        ws = new ClientWebSocket();
        await ws.ConnectAsync(
            new Uri("ws://127.0.0.1:8000"),
            CancellationToken.None
        );

        _ = Task.Run(() => ReceiveLoop());
    }

    void OnAudioFilterRead(float[] data, int channels)
    {
        if (ws == null || ws.State != WebSocketState.Open) return;

        for (int i = 0; i < data.Length; i += channels)
        {
            ringBuffer[bufferPos++] = data[i]; // mono

            if (bufferPos >= WIN_SAMPLES)
            {
                // ★ 修正箇所: ここで配列をコピーする
                float[] bufferToSend = new float[WIN_SAMPLES];
                Array.Copy(ringBuffer, bufferToSend, WIN_SAMPLES);

                // コピーした方を送る
                SendAudio(bufferToSend); 
                
                bufferPos = 0;
            }
        }
    }

    async void SendAudio(float[] audio)
    {
        byte[] bytes = new byte[audio.Length * sizeof(float)];
        Buffer.BlockCopy(audio, 0, bytes, 0, bytes.Length);

        await ws.SendAsync(
            new ArraySegment<byte>(bytes),
            WebSocketMessageType.Binary,
            true,
            CancellationToken.None
        );
    }


    async Task ReceiveLoop()
    {
        var buf = new byte[2048];

        while (ws != null && ws.State == WebSocketState.Open)
        {
            var result = await ws.ReceiveAsync(
                new ArraySegment<byte>(buf),
                CancellationToken.None
            );

            if (result.MessageType == WebSocketMessageType.Text)
            {
                string jsonMsg = Encoding.UTF8.GetString(buf, 0, result.Count);
                
                // メインスレッドでUI更新
                UnityMainThreadDispatcher.Instance().Enqueue(() =>
                {
                    if (resultText != null)
                    {
                        // 1. JSONをパースしてC#のクラスに変換
                        InferenceResult data = JsonUtility.FromJson<InferenceResult>(jsonMsg);

                        // 2. ラベルに応じて表示を変える
                        UpdateUI(data); 
                    }
                });
            }
        }
    }

    // ★ 表示ロジックを分離（好みに合わせてここを編集してください）
    void UpdateUI(InferenceResult data)
    {
        // 確信度をパーセント表記に (例: 0.668... → 67%)
        float confStr = data.confidence;

        if (data.label == "siren")
        {
            // サイレンの場合：赤色で警告アイコン付きで表示
            // ※ TextMeshProのRich Text機能を使っています
            resultText.text = $"<color=red><size=120%>🚨 SIREN DETECTED 🚨</size></color>\n" +
                              $"確信度: {confStr}";
        }
        else
        {
            // otherの場合：落ち着いた色で表示、または空文字にして消すのもアリ
            resultText.text = $"<color=#FFFFFF>検知クラス : {data.label}</color>\n" +
                              $"信頼度 : {confStr}</size>";
        }
    }


    async void OnApplicationQuit()
    {
        if (ws != null && ws.State == WebSocketState.Open)
        {
            await ws.CloseAsync(
                WebSocketCloseStatus.NormalClosure,
                "quit",
                CancellationToken.None
            );
        }
    }
}
