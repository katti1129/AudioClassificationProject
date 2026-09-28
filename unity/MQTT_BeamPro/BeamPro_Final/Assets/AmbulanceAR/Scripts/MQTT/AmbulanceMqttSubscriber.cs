using System;
using System.Collections.Generic;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Protocol;
using UnityEngine;

namespace AmbulanceAR
{
    public sealed class AmbulanceMqttSubscriber : MonoBehaviour
    {
        public string brokerHost = "192.168.1.50";
        [Range(1, 65535)] public int brokerPort = 1883;
        public string topic = "research/ambulance/v1/state";
        [Min(.2f)] public float reconnectSeconds = 2;
        public bool connectOnStart = true;
        public bool Connected => connected;
        public string Status => status;
        public int Epoch => Volatile.Read(ref epoch);
        public readonly struct Packet
        {
            public readonly string Json;
            public readonly double ReceivedAt;
            public readonly int Epoch;
            public Packet(string json, double receivedAt, int epoch) { Json = json; ReceivedAt = receivedAt; Epoch = epoch; }
        }
        readonly object gate = new object();
        readonly Queue<Packet> pending = new Queue<Packet>();
        volatile bool connected;
        volatile string status = "MQTT: idle";
        int epoch;
        CancellationTokenSource cancellation;
        Task loop;

        void Start() { if (connectOnStart) Begin(); }
        public void Begin()
        {
            if (loop != null) return;
            // Snapshot all Inspector data on the Unity thread. Worker uses no Unity APIs.
            string host = brokerHost, channel = topic;
            int port = brokerPort;
            double retry = Math.Max(.2, reconnectSeconds);
            cancellation = new CancellationTokenSource();
            loop = Task.Run(() => ConnectionLoop(host, port, channel, retry, cancellation.Token));
        }
        public bool TryDequeue(out Packet packet)
        {
            lock (gate)
            {
                if (pending.Count > 0) { packet = pending.Dequeue(); return true; }
            }
            packet = default;
            return false;
        }
        void ResetSession()
        {
            lock (gate) { connected = false; pending.Clear(); Interlocked.Increment(ref epoch); }
        }
        async Task ConnectionLoop(string host, int port, string channel, double retry, CancellationToken token)
        {
            var factory = new MqttFactory();
            using (var client = factory.CreateMqttClient())
            {
                client.DisconnectedAsync += args => { ResetSession(); status = "MQTT: disconnected / retrying"; return Task.CompletedTask; };
                client.ApplicationMessageReceivedAsync += args =>
                {
                    var message = args.ApplicationMessage;
                    if (message.Topic == channel && !message.Retain && message.PayloadSegment.Count <= 4096)
                    {
                        string json = Encoding.UTF8.GetString(message.PayloadSegment);
                        lock (gate)
                        {
                            while (pending.Count >= 16) pending.Dequeue();
                            pending.Enqueue(new Packet(json, ReceiveClock.Now, epoch));
                        }
                    }
                    return Task.CompletedTask;
                };
                var options = new MqttClientOptionsBuilder().WithTcpServer(host, port)
                    .WithClientId("ambulance-" + Guid.NewGuid().ToString("N"))
                    .WithCleanSession().WithKeepAlivePeriod(TimeSpan.FromSeconds(5))
                    .WithTimeout(TimeSpan.FromSeconds(5)).Build();
                try
                {
                    while (!token.IsCancellationRequested)
                    {
                        if (!client.IsConnected)
                        {
                            ResetSession();
                            status = "MQTT: connecting";
                            try
                            {
                                await client.ConnectAsync(options, token).ConfigureAwait(false);
                                await client.SubscribeAsync(factory.CreateSubscribeOptionsBuilder().WithTopicFilter(filter =>
                                    filter.WithTopic(channel).WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtMostOnce)).Build(), token).ConfigureAwait(false);
                                connected = true;
                                status = "MQTT: subscribed";
                            }
                            catch (OperationCanceledException) { break; }
                            catch (Exception exception)
                            {
                                ResetSession();
                                status = "MQTT: " + exception.GetType().Name + " / retrying";
                                if (client.IsConnected)
                                    await client.DisconnectAsync().ConfigureAwait(false);
                            }
                        }
                        await Task.Delay(TimeSpan.FromSeconds(retry), token).ConfigureAwait(false);
                    }
                }
                catch (OperationCanceledException) { }
                catch (Exception exception) { status = "MQTT: stopped / " + exception.GetType().Name; }
                finally { ResetSession(); }
            }
        }
        void OnDestroy()
        {
            cancellation?.Cancel();
            if (loop != null) _ = loop.ContinueWith(_ => cancellation.Dispose(), TaskScheduler.Default);
        }
    }
}
