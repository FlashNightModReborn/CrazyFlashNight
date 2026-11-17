using System;
using System.IO;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.AgentHarness
{
    /// <summary>
    /// Current-user ACL named-pipe JSON-RPC 2.0 / newline-delimited server for `--agent-harness`.
    /// </summary>
    internal sealed class AgentHarnessPipeServer : IDisposable
    {
        private readonly string _pipeName;
        private readonly byte[] _expectedEpochBytes;
        private readonly Func<string, JObject, CancellationToken, Task<(JObject Result, Action OnResponseWritten)>> _handler;
        private readonly CancellationTokenSource _cts = new();
        private Task _acceptLoop;
        private volatile bool _disposed;

        internal AgentHarnessPipeServer(
            string pipeName,
            string sessionEpoch,
            Func<string, JObject, CancellationToken, Task<(JObject Result, Action OnResponseWritten)>> handler)
        {
            if (string.IsNullOrWhiteSpace(pipeName))
                throw new ArgumentException("pipeName is required.", nameof(pipeName));
            if (string.IsNullOrWhiteSpace(sessionEpoch))
                throw new ArgumentException("sessionEpoch is required.", nameof(sessionEpoch));

            _pipeName = pipeName;
            _expectedEpochBytes = Encoding.UTF8.GetBytes(sessionEpoch);
            _handler = handler ?? throw new ArgumentNullException(nameof(handler));
        }

        internal void Start()
        {
            if (_disposed || _acceptLoop != null) return;
            _acceptLoop = Task.Run(() => AcceptLoopAsync(_cts.Token));
        }

        private NamedPipeServerStream CreateSecuredServerInstance()
        {
            return new NamedPipeServerStream(
                _pipeName,
                PipeDirection.InOut,
                NamedPipeServerStream.MaxAllowedServerInstances,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly,
                65536,
                65536);
        }

        private async Task AcceptLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested && !_disposed)
            {
                NamedPipeServerStream server = null;
                try
                {
                    server = CreateSecuredServerInstance();
                    await server.WaitForConnectionAsync(ct).ConfigureAwait(false);
                    NamedPipeServerStream client = server;
                    server = null;
                    _ = Task.Run(() => HandleClientAsync(client, ct), ct);
                }
                catch (OperationCanceledException)
                {
                    server?.Dispose();
                    break;
                }
                catch (Exception ex)
                {
                    server?.Dispose();
                    try { LogManager.Log("[AgentHarness] Pipe accept error: " + ex.Message); } catch { }
                    try { await Task.Delay(100, ct).ConfigureAwait(false); } catch { break; }
                }
            }
        }

        private bool IsEpochAuthorized(string candidate)
        {
            if (string.IsNullOrEmpty(candidate)) return false;
            byte[] candBytes = Encoding.UTF8.GetBytes(candidate);
            if (candBytes.Length != _expectedEpochBytes.Length) return false;
            return CryptographicOperations.FixedTimeEquals(candBytes, _expectedEpochBytes);
        }

        private async Task HandleClientAsync(NamedPipeServerStream stream, CancellationToken ct)
        {
            using (stream)
            using (var reader = new StreamReader(stream, new UTF8Encoding(false), false, 4096, leaveOpen: true))
            using (var writer = new StreamWriter(stream, new UTF8Encoding(false), 4096, leaveOpen: true) { NewLine = "\n", AutoFlush = false })
            {
                try
                {
                    while (!ct.IsCancellationRequested && stream.IsConnected)
                    {
                        string line = await reader.ReadLineAsync(ct).ConfigureAwait(false);
                        if (line == null) break;
                        if (string.IsNullOrWhiteSpace(line)) continue;

                        JToken idToken = JValue.CreateNull();
                        JObject response;
                        Action onWritten = null;

                        try
                        {
                            JObject req = JObject.Parse(line);
                            if (req["id"] != null) idToken = req["id"].DeepClone();
                            string epoch = req.Value<string>("sessionEpoch");
                            if (!IsEpochAuthorized(epoch))
                            {
                                response = BuildEnvelope(idToken, false, new JObject
                                {
                                    ["ok"] = false,
                                    ["error"] = "session_epoch_mismatch"
                                });
                            }
                            else
                            {
                                string method = req.Value<string>("method") ?? "";
                                JObject @params = req["params"] as JObject ?? new JObject();
                                var handled = await _handler(method, @params, ct).ConfigureAwait(false);
                                JObject result = handled.Result ?? new JObject { ["ok"] = true };
                                bool ok = result.Value<bool?>("ok") ?? result.Value<bool?>("success") ?? true;
                                response = BuildEnvelope(idToken, ok, result);
                                onWritten = handled.OnResponseWritten;
                            }
                        }
                        catch (OperationCanceledException)
                        {
                            break;
                        }
                        catch (Exception ex)
                        {
                            response = BuildEnvelope(idToken, false, new JObject
                            {
                                ["ok"] = false,
                                ["error"] = "rpc_exception",
                                ["message"] = ex.Message
                            });
                        }

                        await writer.WriteLineAsync(response.ToString(Formatting.None)).ConfigureAwait(false);
                        await writer.FlushAsync(ct).ConfigureAwait(false);
                        if (onWritten != null)
                        {
                            try { onWritten(); } catch { }
                        }
                    }
                }
                catch (OperationCanceledException) { }
                catch (IOException) { }
                catch (Exception ex)
                {
                    try { LogManager.Log("[AgentHarness] Pipe client error: " + ex.Message); } catch { }
                }
            }
        }

        private static JObject BuildEnvelope(JToken id, bool ok, JObject result)
        {
            var env = new JObject
            {
                ["id"] = id ?? JValue.CreateNull(),
                ["ok"] = ok,
                ["result"] = result ?? new JObject()
            };
            if (!ok && result != null && result["error"] != null)
                env["error"] = result["error"].DeepClone();
            return env;
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try { _cts.Cancel(); } catch { }
            try { _acceptLoop?.Wait(500); } catch { }
            _cts.Dispose();
        }
    }
}
