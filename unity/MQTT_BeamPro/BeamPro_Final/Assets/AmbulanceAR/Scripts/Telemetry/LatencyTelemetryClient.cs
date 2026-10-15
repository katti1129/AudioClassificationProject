using System;
using System.Collections.Generic;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Protocol;

namespace AmbulanceAR
{
    public sealed class LatencyTelemetryClient : IDisposable
    {
        public readonly struct Message
        {
            public readonly string Kind, Json;
            public readonly double ReceivedAt;
            public Message(string kind, string json, double at) { Kind = kind; Json = json; ReceivedAt = at; }
        }
        readonly object gate = new object();
        readonly Queue<Message> incoming = new Queue<Message>();
        readonly Dictionary<string, double> requests = new Dictionary<string, double>();
        readonly CancellationTokenSource stop = new CancellationTokenSource();
        readonly Task worker;
        int dropped;
        public int Dropped => Volatile.Read(ref dropped);
        public volatile string Status = "connecting";
        public LatencyTelemetryClient(string host, int port, string topic)
        { worker = Task.Run(() => Run(host, port, topic + "/latency", stop.Token)); }
        void Enqueue(Message message)
        {
            lock (gate)
            {
                if (incoming.Count >= 512) { incoming.Dequeue(); Interlocked.Increment(ref dropped); }
                incoming.Enqueue(message);
            }
        }
        public bool TryDequeue(out Message message)
        {
            lock (gate) { if (incoming.Count > 0) { message = incoming.Dequeue(); return true; } }
            message = default; return false;
        }
        public bool TakeRequest(string id, out double sent)
        {
            lock (gate)
            {
                if (id != null && requests.TryGetValue(id, out sent)) { requests.Remove(id); return true; }
                sent = 0; return false;
            }
        }
        async Task Run(string host, int port, string root, CancellationToken token)
        {
            var factory = new MqttFactory();
            using (var client = factory.CreateMqttClient())
            {
                client.DisconnectedAsync += args =>
                { Status = "disconnected"; Enqueue(new Message("reset", "", ReceiveClock.Now)); return Task.CompletedTask; };
                client.ApplicationMessageReceivedAsync += args =>
                {
                    double at = ReceiveClock.Now;
                    var m = args.ApplicationMessage;
                    if (!m.Retain && m.PayloadSegment.Count <= 4096 && m.Topic.StartsWith(root + "/", StringComparison.Ordinal))
                        Enqueue(new Message(m.Topic.Substring(root.Length + 1), Encoding.UTF8.GetString(m.PayloadSegment), at));
                    return Task.CompletedTask;
                };
                var options = new MqttClientOptionsBuilder().WithTcpServer(host, port)
                    .WithClientId("latency-beam-" + Guid.NewGuid().ToString("N")).WithCleanSession()
                    .WithTimeout(TimeSpan.FromSeconds(5)).Build();
                while (!token.IsCancellationRequested)
                {
                    try
                    {
                        if (!client.IsConnected)
                        {
                            lock (gate) requests.Clear();
                            Enqueue(new Message("reset", "", ReceiveClock.Now));
                            await client.ConnectAsync(options, token).ConfigureAwait(false);
                            var subscriptions = factory.CreateSubscribeOptionsBuilder();
                            foreach (string suffix in new[] { "event", "result", "sync/response" })
                                subscriptions.WithTopicFilter(f => f.WithTopic(root + "/" + suffix)
                                    .WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtMostOnce));
                            await client.SubscribeAsync(subscriptions.Build(), token).ConfigureAwait(false);
                            Status = "connected";
                        }
                        string id = Guid.NewGuid().ToString("N");
                        lock (gate)
                        {
                            if (requests.Count >= 16) requests.Clear();
                            requests[id] = ReceiveClock.Now;
                        }
                        await client.PublishAsync(new MqttApplicationMessageBuilder().WithTopic(root + "/sync/request")
                            .WithPayload("{\"id\":\"" + id + "\"}").WithRetainFlag(false)
                            .WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtMostOnce).Build(), token).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException) { break; }
                    catch (Exception ex)
                    {
                        Status = ex.GetType().Name;
                        if (client.IsConnected)
                            try { await client.DisconnectAsync().ConfigureAwait(false); } catch (Exception) { }
                    }
                    try { await Task.Delay(2000, token).ConfigureAwait(false); }
                    catch (OperationCanceledException) { break; }
                }
            }
        }
        public void Dispose() { stop.Cancel(); _ = worker.ContinueWith(_ => stop.Dispose()); }
    }
}
