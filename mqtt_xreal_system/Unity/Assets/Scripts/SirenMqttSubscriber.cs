using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Protocol;
using TMPro;
using UnityEngine;

/// <summary>
/// Beam Pro / XREAL-side MQTT subscriber.
/// Receives the Jetson ambulance state and updates a head-locked HUD.
/// Tested API shape: MQTTnet 4.3.7.1207.
/// </summary>
public class SirenMqttSubscriber : MonoBehaviour
{
    [Serializable]
    public class AmbulanceState
    {
        public int version;
        public bool detected;
        public string class_name;
        public float confidence_pct;
        public float doa_deg;
        public float rms;
        public float inference_ms;
        public long timestamp_ms;
    }

    [Header("MQTT")]
    [Tooltip("JetsonのWi-Fi/LAN側IP。例: 192.168.1.50")]
    public string brokerHost = "192.168.1.50";
    public int brokerPort = 1883;
    public string topic = "research/ambulance/v1/state";
    public float reconnectIntervalSeconds = 2f;

    [Header("HUD References")]
    [Tooltip("サイレン検知中だけ表示したいHUD全体")]
    public GameObject alertRoot;
    [Tooltip("上向き矢印画像のRectTransform")]
    public RectTransform arrow;
    public TMP_Text statusText;
    public TMP_Text confidenceText;
    public TMP_Text directionText;
    public TMP_Text connectionText;

    [Header("DOA -> UI calibration")]
    [Tooltip("現在のReSpeaker GUI対応なら90。設置方向を変えたら実測で調整。")]
    public float doaToUiOffsetDeg = 90f;
    [Tooltip("DOAの回転向きが逆の場合のみON")]
    public bool invertDoa = false;

    [Header("Safety / stale data")]
    [Tooltip("この秒数以上新しいMQTT状態が来なければ警告を消す")]
    public float staleTimeoutSeconds = 1.5f;

    private readonly ConcurrentQueue<string> _receivedJson = new ConcurrentQueue<string>();
    private readonly ConcurrentQueue<string> _connectionMessages = new ConcurrentQueue<string>();

    private IMqttClient _client;
    private MqttFactory _factory;
    private CancellationTokenSource _cts;
    private float _lastReceiveRealtime = -999f;

    private async void Start()
    {
        if (alertRoot != null)
            alertRoot.SetActive(false);

        SetConnectionText("MQTT: starting");

        _cts = new CancellationTokenSource();
        _factory = new MqttFactory();
        _client = _factory.CreateMqttClient();

        _client.ApplicationMessageReceivedAsync += e =>
        {
            if (e.ApplicationMessage.Topic == topic)
            {
                // MQTT callback is not the Unity main thread.
                // Queue the JSON and touch Unity objects only in Update().
                _receivedJson.Enqueue(e.ApplicationMessage.ConvertPayloadToString());
            }
            return Task.CompletedTask;
        };

        _client.ConnectedAsync += e =>
        {
            _connectionMessages.Enqueue("MQTT: connected");
            return Task.CompletedTask;
        };

        _client.DisconnectedAsync += e =>
        {
            _connectionMessages.Enqueue("MQTT: disconnected");
            return Task.CompletedTask;
        };

        await ConnectionLoopAsync(_cts.Token);
    }

    private async Task ConnectionLoopAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                if (_client != null && !_client.IsConnected)
                {
                    var options = new MqttClientOptionsBuilder()
                        .WithTcpServer(brokerHost, brokerPort)
                        .WithClientId("beampro-xreal-" + Guid.NewGuid().ToString("N").Substring(0, 8))
                        .WithCleanSession()
                        .WithKeepAlivePeriod(TimeSpan.FromSeconds(15))
                        .Build();

                    await _client.ConnectAsync(options, token);

                    var subscribeOptions = _factory.CreateSubscribeOptionsBuilder()
                        .WithTopicFilter(f =>
                        {
                            f.WithTopic(topic);
                            f.WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtMostOnce);
                        })
                        .Build();

                    await _client.SubscribeAsync(subscribeOptions, token);
                    _connectionMessages.Enqueue("MQTT: subscribed");
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _connectionMessages.Enqueue("MQTT error: " + ex.Message);
            }

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(reconnectIntervalSeconds), token);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private void Update()
    {
        // Apply the newest connection status on the Unity main thread.
        while (_connectionMessages.TryDequeue(out string connectionMessage))
            SetConnectionText(connectionMessage);

        // If multiple MQTT messages arrived in one frame, keep the newest one.
        string newestJson = null;
        while (_receivedJson.TryDequeue(out string json))
            newestJson = json;

        if (!string.IsNullOrEmpty(newestJson))
        {
            try
            {
                AmbulanceState state = JsonUtility.FromJson<AmbulanceState>(newestJson);
                _lastReceiveRealtime = Time.realtimeSinceStartup;
                ApplyState(state);
            }
            catch (Exception ex)
            {
                Debug.LogWarning("MQTT JSON parse failed: " + ex.Message + "\n" + newestJson);
            }
        }

        // Never leave an old warning on screen after communication stops.
        if (Time.realtimeSinceStartup - _lastReceiveRealtime > staleTimeoutSeconds)
        {
            if (alertRoot != null && alertRoot.activeSelf)
                alertRoot.SetActive(false);
        }
    }

    private void ApplyState(AmbulanceState state)
    {
        if (state == null)
            return;

        if (alertRoot != null)
            alertRoot.SetActive(state.detected);

        if (!state.detected)
            return;

        if (statusText != null)
            statusText.text = "AMBULANCE / SIREN";

        if (confidenceText != null)
            confidenceText.text = state.confidence_pct.ToString("F1") + " %";

        if (state.doa_deg < 0f)
        {
            if (directionText != null)
                directionText.text = "DOA: Unknown";
            if (arrow != null)
                arrow.gameObject.SetActive(false);
            return;
        }

        float doa = Normalize360(state.doa_deg);
        if (directionText != null)
            directionText.text = "DOA: " + doa.ToString("F0") + "°";

        if (arrow != null)
        {
            arrow.gameObject.SetActive(true);
            float signedDoa = invertDoa ? -doa : doa;
            float z = Normalize360(signedDoa + doaToUiOffsetDeg);
            arrow.localRotation = Quaternion.Euler(0f, 0f, z);
        }
    }

    private static float Normalize360(float angle)
    {
        angle %= 360f;
        if (angle < 0f)
            angle += 360f;
        return angle;
    }

    private void SetConnectionText(string message)
    {
        if (connectionText != null)
            connectionText.text = message;
        Debug.Log(message);
    }

    private async void OnDestroy()
    {
        if (_cts != null)
        {
            _cts.Cancel();
            _cts.Dispose();
            _cts = null;
        }

        if (_client != null && _client.IsConnected)
        {
            try
            {
                await _client.DisconnectAsync();
            }
            catch (Exception)
            {
                // Scene/app shutdown: no recovery is needed here.
            }
        }
    }
}
