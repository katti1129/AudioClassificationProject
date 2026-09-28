using System;
using System.Collections;
using System.Net;
using System.Net.Sockets;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Server;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace AmbulanceAR.Tests
{
    public class MqttLoopbackTests
    {
        static IEnumerator WaitFor(Func<bool> predicate, string reason)
        {
            double deadline = ReceiveClock.Now + 15;
            while (!predicate() && ReceiveClock.Now < deadline) yield return null;
            Assert.True(predicate(), reason);
        }

        [UnityTest]
        public IEnumerator SubscriberConnectsReceivesAndResubscribesAfterBrokerRestart()
        {
            var reservation = new TcpListener(IPAddress.Loopback, 0); reservation.Start();
            int port = ((IPEndPoint)reservation.LocalEndpoint).Port; reservation.Stop();
            var factory = new MqttFactory();
            using (var server = factory.CreateMqttServer(new MqttServerOptionsBuilder().WithDefaultEndpoint()
                .WithDefaultEndpointBoundIPAddress(IPAddress.Loopback).WithDefaultEndpointPort(port).Build()))
            using (var publisher = factory.CreateMqttClient())
            {
                var go = new GameObject("MQTT loopback test");
                try
                {
                    var start = server.StartAsync(); yield return WaitFor(() => start.IsCompleted, "Broker start"); start.GetAwaiter().GetResult();
                    var subscriber = go.AddComponent<AmbulanceMqttSubscriber>(); subscriber.brokerHost = "127.0.0.1";
                    subscriber.brokerPort = port; subscriber.reconnectSeconds = .2f; subscriber.Begin();
                    yield return WaitFor(() => subscriber.Connected, "Subscribe");
                    var options = new MqttClientOptionsBuilder().WithTcpServer("127.0.0.1", port).WithClientId("test-publisher").Build();
                    var connect = publisher.ConnectAsync(options); yield return WaitFor(() => connect.IsCompleted, "Publisher connect"); connect.GetAwaiter().GetResult();
                    string payload = "{\"version\":1,\"detected\":true,\"class_name\":\"siren\",\"confidence_pct\":98.1,\"doa_deg\":270,\"rms\":0.04,\"inference_ms\":20,\"timestamp_ms\":100}";
                    var send = publisher.PublishAsync(new MqttApplicationMessageBuilder().WithTopic(subscriber.topic).WithPayload(payload).Build());
                    yield return WaitFor(() => send.IsCompleted, "Publish"); send.GetAwaiter().GetResult();
                    AmbulanceMqttSubscriber.Packet packet = default;
                    bool received = false;
                    yield return WaitFor(() => received || (received = subscriber.TryDequeue(out packet)), "Receive through actual MQTT TCP");
                    Assert.True(AmbulanceState.TryParse(packet.Json, out var state)); Assert.AreEqual(270, state.doa_deg);
                    var freshness = new StateFreshness();
                    Assert.True(freshness.Accept(packet.Json, packet.ReceivedAt));
                    send = publisher.PublishAsync(new MqttApplicationMessageBuilder().WithTopic(subscriber.topic).WithPayload("{ malformed JSON").Build());
                    yield return WaitFor(() => send.IsCompleted, "Malformed publish"); send.GetAwaiter().GetResult();
                    received = false;
                    yield return WaitFor(() => received || (received = subscriber.TryDequeue(out packet)), "Malformed received through MQTT");
                    Assert.False(freshness.Accept(packet.Json, packet.ReceivedAt));
                    Assert.AreEqual(100, freshness.Current.timestamp_ms);
                    Assert.True(subscriber.Connected, "Malformed payload must not terminate MQTT worker");
                    int epoch = subscriber.Epoch;
                    var stop = server.StopAsync(); yield return WaitFor(() => stop.IsCompleted, "Broker stop"); stop.GetAwaiter().GetResult();
                    yield return WaitFor(() => !subscriber.Connected, "Disconnect observed");
                    Assert.Greater(subscriber.Epoch, epoch);
                    if (publisher.IsConnected)
                    {
                        var disconnect = publisher.DisconnectAsync();
                        yield return WaitFor(() => disconnect.IsCompleted, "Test publisher disconnect");
                        disconnect.GetAwaiter().GetResult();
                    }
                    start = server.StartAsync(); yield return WaitFor(() => start.IsCompleted, "Broker restart"); start.GetAwaiter().GetResult();
                    yield return WaitFor(() => subscriber.Connected, "Automatic reconnect and resubscribe");
                    connect = publisher.ConnectAsync(options); yield return WaitFor(() => connect.IsCompleted, "Publisher reconnect"); connect.GetAwaiter().GetResult();
                    send = publisher.PublishAsync(new MqttApplicationMessageBuilder().WithTopic(subscriber.topic).WithPayload(payload.Replace(":100}", ":101}")).Build());
                    yield return WaitFor(() => send.IsCompleted, "Second publish"); send.GetAwaiter().GetResult();
                    received = false;
                    yield return WaitFor(() => received || (received = subscriber.TryDequeue(out packet)), "Receive after broker restart");
                    Assert.True(AmbulanceState.TryParse(packet.Json, out state)); Assert.AreEqual(101, state.timestamp_ms);
                }
                finally { UnityEngine.Object.DestroyImmediate(go); }
            }
        }
    }
}
