using System;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;
using TMPro;
using MQTTnet;
using MQTTnet.Client;

public class MqttReceiver : MonoBehaviour
{
    [Header("MQTT Settings")]
    [SerializeField] private string brokerAddress = "133.49.27.137";
    [SerializeField] private int brokerPort = 1883;
    [SerializeField] private string topic = "research/ambulance/v1/state";

    [Header("UI")]
    [SerializeField] private TMP_Text connectionText;
    [SerializeField] private TMP_Text detectedText;
    [SerializeField] private TMP_Text directionText;
    [SerializeField] private TMP_Text confidenceText;

    private IMqttClient mqttClient;

    // MQTT受信スレッド → Unityメインスレッドへ渡すため
    private readonly object dataLock = new object();

    private bool hasNewData = false;

    private bool receivedDetected;
    private float receivedDirection;
    private float receivedConfidence;

    [Serializable]
    public class AmbulanceData
    {
        public bool detected;
        public float direction;
        public float confidence;
    }

    async void Start()
    {
        await ConnectMqtt();
    }

    private async Task ConnectMqtt()
    {
        try
        {
            MqttFactory factory = new MqttFactory();
            mqttClient = factory.CreateMqttClient();

            MqttClientOptions options = new MqttClientOptionsBuilder()
                .WithTcpServer(brokerAddress, brokerPort)
                .WithClientId("UnityBeamProClient")
                .WithCleanSession()
                .Build();

            mqttClient.ConnectedAsync += async e =>
            {
                Debug.Log("MQTT connected");

                lock (dataLock)
                {
                    // 接続状態だけUnity側で表示
                }

                MqttClientSubscribeOptions subscribeOptions =
                    factory.CreateSubscribeOptionsBuilder()
                        .WithTopicFilter(
                            f =>
                            {
                                f.WithTopic(topic);
                            })
                        .Build();

                await mqttClient.SubscribeAsync(subscribeOptions);

                Debug.Log("Subscribed: " + topic);
            };

            mqttClient.DisconnectedAsync += e =>
            {
                Debug.LogWarning("MQTT disconnected");
                return Task.CompletedTask;
            };

            mqttClient.ApplicationMessageReceivedAsync += e =>
            {
                string message =
                    Encoding.UTF8.GetString(
                        e.ApplicationMessage.PayloadSegment
                    );

                Debug.Log("MQTT received: " + message);

                try
                {
                    AmbulanceData data =
                        JsonUtility.FromJson<AmbulanceData>(message);

                    lock (dataLock)
                    {
                        receivedDetected = data.detected;
                        receivedDirection = data.direction;
                        receivedConfidence = data.confidence;
                        hasNewData = true;
                    }
                }
                catch (Exception ex)
                {
                    Debug.LogError(
                        "JSON parse error: " + ex.Message
                    );
                }

                return Task.CompletedTask;
            };

            if (connectionText != null)
            {
                connectionText.text = "MQTT: Connecting...";
            }

            await mqttClient.ConnectAsync(options);

            if (connectionText != null)
            {
                connectionText.text = "MQTT: Connected";
            }
        }
        catch (Exception e)
        {
            Debug.LogError("MQTT connection error: " + e.Message);

            if (connectionText != null)
            {
                connectionText.text = "MQTT: Error";
            }
        }
    }

    void Update()
    {
        bool detected;
        float direction;
        float confidence;

        lock (dataLock)
        {
            if (!hasNewData)
                return;

            detected = receivedDetected;
            direction = receivedDirection;
            confidence = receivedConfidence;

            hasNewData = false;
        }

        // UnityのUI更新はメインスレッドで行う
        if (detectedText != null)
        {
            detectedText.text =
                detected ? "Siren Detected!" : "No Siren";
        }

        if (directionText != null)
        {
            directionText.text =
                $"Direction: {direction:F0}°";
        }

        if (confidenceText != null)
        {
            confidenceText.text =
                $"Confidence: {confidence * 100f:F1}%";
        }
    }

    private async void OnDestroy()
    {
        if (mqttClient != null &&
            mqttClient.IsConnected)
        {
            await mqttClient.DisconnectAsync();
        }
    }
}