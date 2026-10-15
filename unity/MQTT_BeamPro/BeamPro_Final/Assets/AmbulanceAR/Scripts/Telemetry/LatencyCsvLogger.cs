using System;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace AmbulanceAR
{
    public sealed class LatencyCsvLogger : IDisposable
    {
        readonly BlockingCollection<string> pending = new BlockingCollection<string>(512);
        readonly Task worker;
        public string Path { get; }
        public volatile string Error;
        public int Dropped { get; private set; }
        public const string Header = "session,trial_id,status,onset_method,warning_inference_id,warning_timestamp_ms,t0_jetson,t1_jetson,t2_jetson,t3_unity,t4_warning_unity,t4_arrow_unity,detection_s,send_wait_s,transport_s,unity_s,warning_total_s,arrow_total_s,clock_offset_s,sync_rtt_s,sync_age_s,jetson_dropped,unity_dropped,notes,observation_seconds,warning_confidence_pct,arrow_confidence_pct";
        public LatencyCsvLogger(string directory)
        {
            Path = System.IO.Path.Combine(directory, "latency-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff") + "-" + Guid.NewGuid().ToString("N").Substring(0, 6) + ".csv");
            worker = Task.Run(() => Write(directory));
        }
        public static string Cell(object value)
        {
            if (value == null) return "";
            if (value is double number && !LatencyClock.Finite(number)) return "";
            string text = Convert.ToString(value, CultureInfo.InvariantCulture);
            return "\"" + text.Replace("\"", "\"\"") + "\"";
        }
        public void Submit(params object[] values)
        {
            if (Error != null || pending.IsAddingCompleted || !pending.TryAdd(string.Join(",", values.Select(Cell)))) Dropped++;
        }
        void Write(string directory)
        {
            try
            {
                Directory.CreateDirectory(directory);
                using (var stream = new StreamWriter(Path, false, new UTF8Encoding(false)))
                {
                    stream.WriteLine(Header);
                    while (!pending.IsCompleted)
                    {
                        if (!pending.TryTake(out string row, 250)) continue;
                        stream.WriteLine(row);
                        while (pending.TryTake(out row)) stream.WriteLine(row);
                        stream.Flush();
                    }
                }
            }
            catch (Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; }
        }
        public void Dispose() { pending.CompleteAdding(); worker.Wait(2000); }
    }
}
