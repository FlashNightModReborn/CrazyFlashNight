using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.AgentRuntime.TrustedRunner;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.TrustedRunner
{
    public sealed class
        TrustedUnattendedStdioAdapterTests
    {
        private const string ValidRequestId =
            "status-request-0000001";

        [Fact]
        public async Task JsonlNumericIdReturnsStructuredErrorWithoutCallingHost()
        {
            await using var transport =
                new MemoryStream();
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    transport,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\","
                    + "\"id\":1,"
                    + "\"method\":\"session.status\","
                    + "\"params\":{}}\n");
            using var output =
                new MemoryStream();

            int exitCode =
                await TrustedUnattendedStdioAdapter
                    .RunAsync(
                        TrustedUnattendedAdapter.Jsonl,
                        client,
                        input,
                        output,
                        CancellationToken.None);

            Assert.Equal(2, exitCode);
            using JsonDocument response =
                SingleOutput(output);
            Assert.Equal(
                JsonValueKind.Null,
                response.RootElement
                    .GetProperty("id")
                    .ValueKind);
            JsonElement error =
                response.RootElement
                    .GetProperty("error");
            Assert.Equal(
                -32600,
                error.GetProperty("code")
                    .GetInt32());
            Assert.Equal(
                "malformed_json",
                error.GetProperty("data")
                    .GetProperty("reasonCode")
                    .GetString());
            Assert.DoesNotContain(
                "trusted_runner_",
                response.RootElement
                    .GetRawText(),
                StringComparison.Ordinal);
        }

        [Fact]
        public async Task JsonlValidRequestRoundTripsAndEofReturnsCleanly()
        {
            string pipeName =
                "cf7-trusted-jsonl-test-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait =
                server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;
            Task serve =
                ServeSingleStatusAsync(server);
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    pipe,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\","
                    + "\"id\":\""
                    + ValidRequestId
                    + "\",\"method\":\"session.status\","
                    + "\"params\":{}}\n");
            using var output =
                new MemoryStream();
            Task<int> run =
                TrustedUnattendedStdioAdapter
                    .RunAsync(
                        TrustedUnattendedAdapter.Jsonl,
                        client,
                        input,
                        output,
                        CancellationToken.None);
            Task completed =
                await Task.WhenAny(
                    run,
                    Task.Delay(
                        TimeSpan.FromSeconds(3)));
            Assert.True(
                ReferenceEquals(
                    completed,
                    run),
                "JSONL adapter timed out; serverCompleted="
                    + serve.IsCompleted
                    + " serverStatus="
                    + serve.Status);
            int exitCode = await run;
            Task serverCompleted =
                await Task.WhenAny(
                    serve,
                    Task.Delay(
                        TimeSpan.FromSeconds(3)));
            Assert.True(
                ReferenceEquals(
                    serverCompleted,
                    serve),
                "Host was not called; adapterExit="
                    + exitCode
                    + " output="
                    + Encoding.UTF8
                        .GetString(
                            output.ToArray()));
            await serve;

            Assert.Equal(0, exitCode);
            using JsonDocument response =
                SingleOutput(output);
            Assert.Equal(
                ValidRequestId,
                response.RootElement
                    .GetProperty("id")
                    .GetString());
            Assert.Equal(
                "lifecycle_status_test_A",
                response.RootElement
                    .GetProperty("result")
                    .GetProperty("lifecycleRef")
                    .GetString());
        }

        [Fact]
        public async Task JsonlBoundsHungCallClosesPipeWithoutForgedResponse()
        {
            string pipeName =
                "cf7-trusted-jsonl-timeout-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait =
                server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;
            Task<string> hostMethod =
                ReadSingleMethodAsync(server);
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    pipe,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\","
                    + "\"id\":\""
                    + ValidRequestId
                    + "\",\"method\":\"session.status\","
                    + "\"params\":{}}\n");
            using var output =
                new MemoryStream();
            var elapsed = Stopwatch.StartNew();

            TimeoutException error =
                await Assert.ThrowsAsync<
                    TimeoutException>(
                    () =>
                        TrustedUnattendedStdioAdapter
                            .RunAsync(
                                TrustedUnattendedAdapter.Jsonl,
                                client,
                                input,
                                output,
                                TimeSpan
                                    .FromMilliseconds(
                                        250),
                                CancellationToken.None));

            Assert.Equal(
                "trusted_runner_jsonl_call_timeout",
                error.Message);
            Assert.Equal(
                AgentCapabilitiesV1.SessionStatus,
                await hostMethod);
            Assert.Empty(OutputLines(output));
            Assert.True(
                elapsed.Elapsed
                    < TimeSpan.FromSeconds(3));
            byte[] probe = new byte[1];
            int read =
                await server.ReadAsync(
                        probe.AsMemory(),
                        CancellationToken.None)
                    .AsTask()
                    .WaitAsync(
                        TimeSpan.FromSeconds(1));
            Assert.Equal(0, read);
        }

        [Fact]
        public async Task McpInitializeAndToolsListAreProtocolOnly()
        {
            await using var transport =
                new MemoryStream();
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    transport,
                    AgentCapabilitiesV1.SessionStatus,
                    AgentCapabilitiesV1.Click,
                    AgentCapabilitiesV1.LeaseAcquire,
                    AgentCapabilitiesV1
                        .AppearanceHairChange);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
                    + "\"method\":\"initialize\",\"params\":{"
                    + "\"protocolVersion\":\"2025-06-18\","
                    + "\"capabilities\":{\"vendorExtension\":{}},"
                    + "\"clientInfo\":{\"name\":\"cf7-test\","
                    + "\"version\":\"1\"}}}\n"
                    + "{\"jsonrpc\":\"2.0\","
                    + "\"method\":\"notifications/initialized\","
                    + "\"params\":{}}\n"
                    + "{\"jsonrpc\":\"2.0\",\"id\":\"list\","
                    + "\"method\":\"tools/list\"}\n");
            using var output =
                new MemoryStream();

            int exitCode =
                await TrustedUnattendedStdioAdapter
                    .RunAsync(
                        TrustedUnattendedAdapter.Mcp,
                        client,
                        input,
                        output,
                        CancellationToken.None);

            Assert.Equal(0, exitCode);
            string[] lines =
                OutputLines(output);
            Assert.Equal(2, lines.Length);
            using JsonDocument initialize =
                JsonDocument.Parse(lines[0]);
            using JsonDocument list =
                JsonDocument.Parse(lines[1]);
            Assert.Equal(
                "init",
                initialize.RootElement
                    .GetProperty("id")
                    .GetString());
            Assert.Contains(
                list.RootElement
                    .GetProperty("result")
                    .GetProperty("tools")
                    .EnumerateArray(),
                tool =>
                    tool.GetProperty("name")
                        .GetString()
                    == AgentCapabilitiesV1.SessionStatus);
            JsonElement inputSchema =
                list.RootElement
                    .GetProperty("result")
                    .GetProperty("tools")
                    .EnumerateArray()
                    .Single(
                        tool =>
                            tool.GetProperty("name")
                                .GetString()
                            == AgentCapabilitiesV1
                                .SessionStatus)
                    .GetProperty("inputSchema");
            Assert.Equal(
                JsonValueKind.Object,
                inputSchema.GetProperty(
                        "properties")
                    .ValueKind);
            Assert.False(
                inputSchema.GetProperty(
                        "additionalProperties")
                    .GetBoolean());
            JsonElement clickSchema =
                list.RootElement
                    .GetProperty("result")
                    .GetProperty("tools")
                    .EnumerateArray()
                    .Single(
                        tool =>
                            tool.GetProperty("name")
                                .GetString()
                            == AgentCapabilitiesV1
                                .Click)
                    .GetProperty("inputSchema");
            Assert.Equal(
                "integer",
                clickSchema
                    .GetProperty("properties")
                    .GetProperty(
                        "expectedCoordinateSpaceVersion")
                    .GetProperty("type")
                    .GetString());
            JsonElement leaseSchema =
                list.RootElement
                    .GetProperty("result")
                    .GetProperty("tools")
                    .EnumerateArray()
                    .Single(
                        tool =>
                            tool.GetProperty("name")
                                .GetString()
                            == AgentCapabilitiesV1
                                .LeaseAcquire)
                    .GetProperty("inputSchema");
            Assert.Equal(
                "string",
                leaseSchema
                    .GetProperty("properties")
                    .GetProperty(
                        "expectedRevision")
                    .GetProperty("type")
                    .GetString());
            JsonElement hairSchema =
                list.RootElement
                    .GetProperty("result")
                    .GetProperty("tools")
                    .EnumerateArray()
                    .Single(
                        tool =>
                            tool.GetProperty("name")
                                .GetString()
                            == AgentMethodsV1
                                .HairPreview)
                    .GetProperty("inputSchema");
            Assert.Equal(
                "integer",
                hairSchema
                    .GetProperty("properties")
                    .GetProperty(
                        "expectedRevision")
                    .GetProperty("type")
                    .GetString());
        }

        [Theory]
        [InlineData(
            "{\"jsonrpc\":\"2.0\",\"id\":\"list\","
            + "\"method\":\"tools/list\"}\n",
            -32002)]
        [InlineData(
            "{\"jsonrpc\":\"2.0\",\"id\":1.5,"
            + "\"method\":\"initialize\",\"params\":{}}\n",
            -32600)]
        [InlineData(
            "{\"jsonrpc\":\"2.0\","
            + "\"id\":9007199254740992,"
            + "\"method\":\"initialize\",\"params\":{}}\n",
            -32600)]
        [InlineData(
            "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
            + "\"method\":\"initialize\",\"params\":{"
            + "\"protocolVersion\":\"2024-11-05\","
            + "\"capabilities\":{},"
            + "\"clientInfo\":{\"name\":\"cf7\","
            + "\"version\":\"1\"}}}\n",
            -32602)]
        [InlineData(
            "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
            + "\"method\":\"initialize\",\"params\":{"
            + "\"protocolVersion\":\"2025-06-18\","
            + "\"capabilities\":{\"unknown\":true},"
            + "\"clientInfo\":{\"name\":\"cf7\","
            + "\"version\":\"1\"}}}\n",
            -32602)]
        [InlineData(
            "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
            + "\"method\":\"initialize\",\"params\":{"
            + "\"protocolVersion\":\"2025-06-18\","
            + "\"capabilities\":{},"
            + "\"clientInfo\":{\"name\":\"\","
            + "\"version\":\"1\"}}}\n",
            -32602)]
        public async Task McpRejectsInvalidLifecycleOrInitialize(
            string request,
            int expectedCode)
        {
            await using var transport =
                new MemoryStream();
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    transport,
                    AgentCapabilitiesV1.SessionStatus);
            using var input = Input(request);
            using var output =
                new MemoryStream();

            int exitCode =
                await TrustedUnattendedStdioAdapter
                    .RunAsync(
                        TrustedUnattendedAdapter.Mcp,
                        client,
                        input,
                        output,
                        CancellationToken.None);

            Assert.Equal(0, exitCode);
            using JsonDocument response =
                SingleOutput(output);
            Assert.Equal(
                expectedCode,
                response.RootElement
                    .GetProperty("error")
                    .GetProperty("code")
                    .GetInt32());
        }

        [Fact]
        public async Task McpRequiresInitializedNotificationAndRejectsRepeatInitialize()
        {
            await using var transport =
                new MemoryStream();
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    transport,
                    AgentCapabilitiesV1.SessionStatus);
            string initialize =
                "{\"jsonrpc\":\"2.0\",\"id\":\"init-1\","
                + "\"method\":\"initialize\",\"params\":{"
                + "\"protocolVersion\":\"2025-06-18\","
                + "\"capabilities\":{},"
                + "\"clientInfo\":{\"name\":\"cf7\","
                + "\"version\":\"1\"}}}";
            using var input =
                Input(
                    initialize
                    + "\n"
                    + initialize.Replace(
                        "init-1",
                        "init-2",
                        StringComparison.Ordinal)
                    + "\n"
                    + "{\"jsonrpc\":\"2.0\",\"id\":\"list\","
                    + "\"method\":\"tools/list\"}\n");
            using var output =
                new MemoryStream();

            await TrustedUnattendedStdioAdapter
                .RunAsync(
                    TrustedUnattendedAdapter.Mcp,
                    client,
                    input,
                    output,
                    CancellationToken.None);

            string[] lines =
                OutputLines(output);
            Assert.Equal(3, lines.Length);
            using JsonDocument repeated =
                JsonDocument.Parse(lines[1]);
            using JsonDocument beforeNotification =
                JsonDocument.Parse(lines[2]);
            Assert.Equal(
                -32600,
                repeated.RootElement
                    .GetProperty("error")
                    .GetProperty("code")
                    .GetInt32());
            Assert.Equal(
                -32002,
                beforeNotification.RootElement
                    .GetProperty("error")
                    .GetProperty("code")
                    .GetInt32());
        }

        [Fact]
        public async Task McpInvalidNotificationProducesNoResponse()
        {
            await using var transport =
                new MemoryStream();
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    transport,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\","
                    + "\"method\":\"notifications/initialized\","
                    + "\"params\":{}}\n");
            using var output =
                new MemoryStream();

            int exitCode =
                await TrustedUnattendedStdioAdapter
                    .RunAsync(
                        TrustedUnattendedAdapter.Mcp,
                        client,
                        input,
                        output,
                        CancellationToken.None);

            Assert.Equal(0, exitCode);
            Assert.Empty(
                OutputLines(output));
        }

        [Theory]
        [InlineData(
            "call",
            "trusted_runner_mcp_call_cancelled")]
        [InlineData(
            "different",
            "trusted_runner_mcp_cancellation_mismatch")]
        public async Task McpCancellationClosesPipeAndSuppressesActiveToolResponse(
            string cancellationRequestId,
            string expectedReason)
        {
            string pipeName =
                "cf7-trusted-mcp-cancel-test-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait =
                server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;
            Task<string> hostMethod =
                ReadSingleMethodAsync(server);
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    pipe,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
                    + "\"method\":\"initialize\",\"params\":{"
                    + "\"protocolVersion\":\"2025-06-18\","
                    + "\"capabilities\":{},"
                    + "\"clientInfo\":{\"name\":\"cf7\","
                    + "\"version\":\"1\"}}}\n"
                    + "{\"jsonrpc\":\"2.0\","
                    + "\"method\":\"notifications/initialized\","
                    + "\"params\":{}}\n"
                    + "{\"jsonrpc\":\"2.0\",\"id\":\"call\","
                    + "\"method\":\"tools/call\",\"params\":{"
                    + "\"name\":\"session.status\","
                    + "\"arguments\":{}}}\n"
                    + "{\"jsonrpc\":\"2.0\","
                    + "\"method\":\"notifications/cancelled\","
                    + "\"params\":{\"requestId\":\""
                    + cancellationRequestId
                    + "\"}}\n");
            using var output =
                new MemoryStream();

            InvalidDataException error =
                await Assert.ThrowsAsync<
                    InvalidDataException>(
                    () =>
                        TrustedUnattendedStdioAdapter
                            .RunAsync(
                                TrustedUnattendedAdapter.Mcp,
                                client,
                                input,
                                output,
                                CancellationToken.None));

            Assert.Equal(
                expectedReason,
                error.Message);
            try
            {
                string observedMethod =
                    await hostMethod;
                if (observedMethod != null)
                {
                    Assert.Equal(
                        AgentCapabilitiesV1
                            .SessionStatus,
                        observedMethod);
                }
            }
            catch (AgentFrameProtocolException)
            {
                // Fail-close cancellation may interrupt the
                // in-flight frame before the peer has received
                // its full declared payload.
            }
            string protocolOutput =
                Encoding.UTF8.GetString(
                    output.ToArray());
            Assert.Single(
                OutputLines(output));
            Assert.DoesNotContain(
                "trusted_runner_",
                protocolOutput,
                StringComparison.Ordinal);
        }

        [Fact]
        public async Task McpEofBoundsHungCallClosesPipeAndNeverReturnsSuccess()
        {
            string pipeName =
                "cf7-trusted-mcp-eof-timeout-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait =
                server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;
            Task<string> hostMethod =
                ReadSingleMethodAsync(server);
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    pipe,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
                    + "\"method\":\"initialize\",\"params\":{"
                    + "\"protocolVersion\":\"2025-06-18\","
                    + "\"capabilities\":{},"
                    + "\"clientInfo\":{\"name\":\"cf7\","
                    + "\"version\":\"1\"}}}\n"
                    + "{\"jsonrpc\":\"2.0\","
                    + "\"method\":\"notifications/initialized\","
                    + "\"params\":{}}\n"
                    + "{\"jsonrpc\":\"2.0\",\"id\":\"call\","
                    + "\"method\":\"tools/call\",\"params\":{"
                    + "\"name\":\"session.status\","
                    + "\"arguments\":{}}}\n");
            using var output =
                new MemoryStream();
            var elapsed = Stopwatch.StartNew();

            TimeoutException error =
                await Assert.ThrowsAsync<
                    TimeoutException>(
                    () =>
                        TrustedUnattendedStdioAdapter
                            .RunAsync(
                                TrustedUnattendedAdapter.Mcp,
                                client,
                                input,
                                output,
                                TimeSpan
                                    .FromMilliseconds(
                                        250),
                                CancellationToken.None));

            Assert.Equal(
                "trusted_runner_mcp_eof_call_timeout",
                error.Message);
            Assert.Equal(
                AgentCapabilitiesV1.SessionStatus,
                await hostMethod);
            Assert.Single(OutputLines(output));
            Assert.True(
                elapsed.Elapsed
                    < TimeSpan.FromSeconds(3));
            byte[] probe = new byte[1];
            int read =
                await server.ReadAsync(
                        probe.AsMemory(),
                        CancellationToken.None)
                    .AsTask()
                    .WaitAsync(
                        TimeSpan.FromSeconds(1));
            Assert.Equal(0, read);
        }

        [Fact]
        public async Task McpEofDeadlineIncludesBackpressuredResponseCopyAndFlush()
        {
            string pipeName =
                "cf7-trusted-mcp-output-timeout-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait =
                server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;
            Task responseGenerated =
                ServeSingleStatusAsync(server);
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    pipe,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
                    + "\"method\":\"initialize\",\"params\":{"
                    + "\"protocolVersion\":\"2025-06-18\","
                    + "\"capabilities\":{},"
                    + "\"clientInfo\":{\"name\":\"cf7\","
                    + "\"version\":\"1\"}}}\n"
                    + "{\"jsonrpc\":\"2.0\","
                    + "\"method\":\"notifications/initialized\","
                    + "\"params\":{}}\n"
                    + "{\"jsonrpc\":\"2.0\",\"id\":\"call\","
                    + "\"method\":\"tools/call\",\"params\":{"
                    + "\"name\":\"session.status\","
                    + "\"arguments\":{}}}\n");
            using var output =
                new BackpressuredOutputStream();
            var elapsed = Stopwatch.StartNew();
            Task<TimeoutException> observed =
                ObserveTimeoutAsync(
                    TrustedUnattendedStdioAdapter
                        .RunAsync(
                            TrustedUnattendedAdapter.Mcp,
                            client,
                            input,
                            output,
                            TimeSpan
                                .FromMilliseconds(
                                    250),
                            CancellationToken.None));

            await responseGenerated
                .WaitAsync(
                    TimeSpan.FromSeconds(2));
            await output.WriteBlocked
                .WaitAsync(
                    TimeSpan.FromSeconds(2));
            TimeoutException error =
                await observed.WaitAsync(
                    TimeSpan.FromSeconds(2));

            Assert.Equal(
                "trusted_runner_mcp_eof_call_timeout",
                error.Message);
            Assert.True(
                output.BlockedWriteCancellationObserved);
            Assert.Single(
                OutputLines(
                    output.ToArray()));
            Assert.True(
                elapsed.Elapsed
                    < TimeSpan.FromSeconds(2));
            byte[] probe = new byte[1];
            int read =
                await server.ReadAsync(
                        probe.AsMemory(),
                        CancellationToken.None)
                    .AsTask()
                    .WaitAsync(
                        TimeSpan.FromSeconds(1));
            Assert.Equal(0, read);
        }

        [Fact]
        public async Task McpLifecycleOutputBackpressureIsBoundedAndClosesPipe()
        {
            string pipeName =
                "cf7-trusted-mcp-lifecycle-output-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait =
                server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    pipe,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
                    + "\"method\":\"initialize\",\"params\":{"
                    + "\"protocolVersion\":\"2025-06-18\","
                    + "\"capabilities\":{},"
                    + "\"clientInfo\":{\"name\":\"cf7\","
                    + "\"version\":\"1\"}}}\n");
            using var output =
                new BackpressuredOutputStream(
                    acceptedFlushesBeforeBlocking:
                        0);
            var elapsed = Stopwatch.StartNew();
            Task<TimeoutException> observed =
                ObserveTimeoutAsync(
                    TrustedUnattendedStdioAdapter
                        .RunAsync(
                            TrustedUnattendedAdapter.Mcp,
                            client,
                            input,
                            output,
                            TimeSpan
                                .FromMilliseconds(
                                    250),
                            CancellationToken.None));

            await output.WriteBlocked
                .WaitAsync(
                    TimeSpan.FromSeconds(2));
            TimeoutException error =
                await observed.WaitAsync(
                    TimeSpan.FromSeconds(2));

            Assert.Equal(
                "trusted_runner_mcp_protocol_output_timeout",
                error.Message);
            Assert.True(
                output.BlockedWriteCancellationObserved);
            Assert.Empty(output.ToArray());
            Assert.True(
                elapsed.Elapsed
                    < TimeSpan.FromSeconds(2));
            byte[] probe = new byte[1];
            int read =
                await server.ReadAsync(
                        probe.AsMemory(),
                        CancellationToken.None)
                    .AsTask()
                    .WaitAsync(
                        TimeSpan.FromSeconds(1));
            Assert.Equal(0, read);
        }

        [Fact]
        public async Task McpConcurrentErrorOutputReusesActiveCallDeadline()
        {
            string pipeName =
                "cf7-trusted-mcp-concurrent-output-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait =
                server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;
            Task<string> hostMethod =
                ReadSingleMethodAsync(server);
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    pipe,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
                    + "\"method\":\"initialize\",\"params\":{"
                    + "\"protocolVersion\":\"2025-06-18\","
                    + "\"capabilities\":{},"
                    + "\"clientInfo\":{\"name\":\"cf7\","
                    + "\"version\":\"1\"}}}\n"
                    + "{\"jsonrpc\":\"2.0\","
                    + "\"method\":\"notifications/initialized\","
                    + "\"params\":{}}\n"
                    + "{\"jsonrpc\":\"2.0\",\"id\":\"call\","
                    + "\"method\":\"tools/call\",\"params\":{"
                    + "\"name\":\"session.status\","
                    + "\"arguments\":{}}}\n"
                    + "{\"jsonrpc\":\"2.0\",\"id\":\"second\","
                    + "\"method\":\"tools/call\",\"params\":{"
                    + "\"name\":\"session.status\","
                    + "\"arguments\":{}}}\n");
            using var output =
                new BackpressuredOutputStream();
            Task<TimeoutException> observed =
                ObserveTimeoutAsync(
                    TrustedUnattendedStdioAdapter
                        .RunAsync(
                            TrustedUnattendedAdapter.Mcp,
                            client,
                            input,
                            output,
                            TimeSpan
                                .FromMilliseconds(
                                    250),
                            CancellationToken.None));

            await output.WriteBlocked
                .WaitAsync(
                    TimeSpan.FromSeconds(2));
            TimeoutException error =
                await observed.WaitAsync(
                    TimeSpan.FromSeconds(2));

            Assert.Equal(
                "trusted_runner_mcp_call_timeout",
                error.Message);
            Assert.True(
                output.BlockedWriteCancellationObserved);
            Assert.Single(
                OutputLines(
                    output.ToArray()));
            string observedMethod =
                await hostMethod.WaitAsync(
                    TimeSpan.FromSeconds(1));
            if (observedMethod != null)
            {
                Assert.Equal(
                    AgentCapabilitiesV1.SessionStatus,
                    observedMethod);
            }
            byte[] probe = new byte[1];
            int read =
                await server.ReadAsync(
                        probe.AsMemory(),
                        CancellationToken.None)
                    .AsTask()
                    .WaitAsync(
                        TimeSpan.FromSeconds(1));
            Assert.Equal(0, read);
        }

        [Fact]
        public async Task McpInternalFailureDoesNotExposeTrustedRunnerDetail()
        {
            await using var transport =
                new MemoryStream();
            await using TrustedUnattendedAgentClient client =
                CreateClient(
                    transport,
                    AgentCapabilitiesV1.SessionStatus);
            using var input =
                Input(
                    "{\"jsonrpc\":\"2.0\",\"id\":\"init\","
                    + "\"method\":\"initialize\",\"params\":{"
                    + "\"protocolVersion\":\"2025-06-18\","
                    + "\"capabilities\":{},"
                    + "\"clientInfo\":{\"name\":\"cf7\","
                    + "\"version\":\"1\"}}}\n"
                    + "{\"jsonrpc\":\"2.0\","
                    + "\"method\":\"notifications/initialized\","
                    + "\"params\":{}}\n"
                    + "{\"jsonrpc\":\"2.0\",\"id\":\"call\","
                    + "\"method\":\"tools/call\",\"params\":{"
                    + "\"name\":\"session.status\","
                    + "\"arguments\":{}}}\n");
            using var output =
                new MemoryStream();

            int exitCode =
                await TrustedUnattendedStdioAdapter
                    .RunAsync(
                        TrustedUnattendedAdapter.Mcp,
                        client,
                        input,
                        output,
                        CancellationToken.None);

            Assert.Equal(0, exitCode);
            string text =
                Encoding.UTF8.GetString(
                    output.ToArray());
            Assert.Equal(
                2,
                OutputLines(output).Length);
            Assert.DoesNotContain(
                "trusted_runner_",
                text,
                StringComparison.Ordinal);
            Assert.DoesNotContain(
                "\\",
                text,
                StringComparison.Ordinal);
        }

        private static TrustedUnattendedAgentClient
            CreateClient(
                Stream stream,
                params string[] capabilities)
        {
            var credential =
                new TrustedUnattendedCredential(
                    "isolated_candidate",
                    "proof_stdio_adapter_test_A",
                    capabilities,
                    new[]
                    {
                        "target_stdio_adapter_test_A"
                    },
                    "session_stdio_adapter_test_A",
                    "attempt_stdio_adapter_test_A",
                    1,
                    "receipt_stdio_adapter_test_A");
            return TrustedUnattendedAgentClient
                .CreateAuthenticatedForTest(
                    stream,
                    credential,
                    "lifecycle_stdio_adapter_test_A",
                    capabilities);
        }

        private static async Task
            ServeSingleStatusAsync(
                NamedPipeServerStream stream)
        {
            var codec =
                new AgentFrameCodec(
                    AgentRendezvousStore.ProtocolMajor);
            AgentFrame frame =
                await codec.ReadAsync(
                    stream,
                    CancellationToken.None);
            using JsonDocument request =
                JsonDocument.Parse(frame.Payload);
            Assert.Equal(
                AgentCapabilitiesV1.SessionStatus,
                request.RootElement
                    .GetProperty("method")
                    .GetString());
            byte[] payload =
                JsonSerializer.SerializeToUtf8Bytes(
                    new
                    {
                        jsonrpc = "2.0",
                        id = request.RootElement
                            .GetProperty("id")
                            .GetString(),
                        result = new
                        {
                            lifecycleRef =
                                "lifecycle_status_test_A"
                        }
                    },
                    AgentProtocolV1.JsonOptions);
            await codec.WriteAsync(
                stream,
                new AgentFrame(
                    AgentRendezvousStore.ProtocolMajor,
                    AgentFrameKind.JsonRpc,
                    AgentFrameCodec.SupportedFlags,
                    payload),
                CancellationToken.None);
        }

        private static async Task<string>
            ReadSingleMethodAsync(
                NamedPipeServerStream stream)
        {
            var codec =
                new AgentFrameCodec(
                    AgentRendezvousStore.ProtocolMajor);
            AgentFrame frame =
                await codec.ReadAsync(
                    stream,
                    CancellationToken.None);
            if (frame == null)
                return null;
            using JsonDocument request =
                JsonDocument.Parse(
                    frame.Payload);
            return request.RootElement
                .GetProperty("method")
                .GetString();
        }

        private static async Task<TimeoutException>
            ObserveTimeoutAsync(
                Task<int> run)
        {
            return await Assert.ThrowsAsync<
                    TimeoutException>(
                    async () => await run);
        }

        private static MemoryStream Input(
            string value)
        {
            return new MemoryStream(
                Encoding.UTF8.GetBytes(value),
                writable: false);
        }

        private static JsonDocument SingleOutput(
            MemoryStream output)
        {
            string[] lines = OutputLines(output);
            Assert.Single(lines);
            return JsonDocument.Parse(lines[0]);
        }

        private static string[] OutputLines(
            MemoryStream output)
        {
            return OutputLines(
                output.ToArray());
        }

        private static string[] OutputLines(
            byte[] output)
        {
            return Encoding.UTF8
                .GetString(output)
                .Split(
                    new[] { "\r\n", "\n" },
                    StringSplitOptions.RemoveEmptyEntries)
                .ToArray();
        }

        private sealed class BackpressuredOutputStream
            : Stream
        {
            private readonly MemoryStream _accepted =
                new MemoryStream();
            private readonly TaskCompletionSource
                _writeBlocked =
                    new TaskCompletionSource(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
            private int
                _acceptedFlushesBeforeBlocking;
            private volatile bool _blockWrites;

            public BackpressuredOutputStream(
                int acceptedFlushesBeforeBlocking =
                    1)
            {
                if (acceptedFlushesBeforeBlocking
                    < 0)
                {
                    throw new ArgumentOutOfRangeException(
                        nameof(
                            acceptedFlushesBeforeBlocking));
                }
                _acceptedFlushesBeforeBlocking =
                    acceptedFlushesBeforeBlocking;
                _blockWrites =
                    acceptedFlushesBeforeBlocking
                        == 0;
            }

            public Task WriteBlocked =>
                _writeBlocked.Task;
            public bool
                BlockedWriteCancellationObserved
            {
                get;
                private set;
            }

            public byte[] ToArray()
            {
                lock (_accepted)
                {
                    return _accepted.ToArray();
                }
            }

            public override bool CanRead => false;
            public override bool CanSeek => false;
            public override bool CanWrite => true;
            public override long Length =>
                throw new NotSupportedException();
            public override long Position
            {
                get =>
                    throw new NotSupportedException();
                set =>
                    throw new NotSupportedException();
            }

            public override void Flush()
            {
                ObserveAcceptedFlush();
            }

            public override Task FlushAsync(
                CancellationToken cancellationToken)
            {
                ObserveAcceptedFlush();
                return Task.CompletedTask;
            }

            private void ObserveAcceptedFlush()
            {
                if (_blockWrites)
                    return;
                if (Interlocked.Decrement(
                        ref _acceptedFlushesBeforeBlocking)
                    <= 0)
                {
                    _blockWrites = true;
                }
            }

            public override void Write(
                byte[] buffer,
                int offset,
                int count)
            {
                if (_blockWrites)
                    throw new InvalidOperationException(
                        "synchronous_write_not_supported");
                lock (_accepted)
                {
                    _accepted.Write(
                        buffer,
                        offset,
                        count);
                }
            }

            public override Task WriteAsync(
                byte[] buffer,
                int offset,
                int count,
                CancellationToken cancellationToken)
            {
                return WriteAsyncCore(
                    new ReadOnlyMemory<byte>(
                        buffer,
                        offset,
                        count),
                    cancellationToken);
            }

            public override ValueTask WriteAsync(
                ReadOnlyMemory<byte> buffer,
                CancellationToken cancellationToken =
                    default)
            {
                return new ValueTask(
                    WriteAsyncCore(
                        buffer,
                        cancellationToken));
            }

            private async Task WriteAsyncCore(
                ReadOnlyMemory<byte> buffer,
                CancellationToken cancellationToken)
            {
                if (!_blockWrites)
                {
                    lock (_accepted)
                    {
                        _accepted.Write(
                            buffer.Span);
                    }
                    return;
                }

                _writeBlocked.TrySetResult();
                try
                {
                    await Task.Delay(
                            Timeout.InfiniteTimeSpan,
                            cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                    when (cancellationToken
                        .IsCancellationRequested)
                {
                    BlockedWriteCancellationObserved =
                        true;
                    throw;
                }
            }

            public override int Read(
                byte[] buffer,
                int offset,
                int count)
            {
                throw new NotSupportedException();
            }

            public override long Seek(
                long offset,
                SeekOrigin origin)
            {
                throw new NotSupportedException();
            }

            public override void SetLength(long value)
            {
                throw new NotSupportedException();
            }

            protected override void Dispose(
                bool disposing)
            {
                if (disposing)
                    _accepted.Dispose();
                base.Dispose(disposing);
            }
        }
    }
}
