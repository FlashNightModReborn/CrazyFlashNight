using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.TrustedRunner
{
    internal static class TrustedUnattendedStdioAdapter
    {
        private const string McpProtocolVersion =
            "2025-06-18";
        private static readonly TimeSpan
            ForwardedCallTimeout =
                TimeSpan.FromSeconds(30);
        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);

        public static async Task<int> RunAsync(
            TrustedUnattendedAdapter adapter,
            TrustedUnattendedAgentClient client,
            Stream input,
            Stream output,
            CancellationToken cancellationToken)
        {
            return await RunAsync(
                    adapter,
                    client,
                    input,
                    output,
                    ForwardedCallTimeout,
                    cancellationToken)
                .ConfigureAwait(false);
        }

        internal static async Task<int> RunAsync(
            TrustedUnattendedAdapter adapter,
            TrustedUnattendedAgentClient client,
            Stream input,
            Stream output,
            TimeSpan forwardedCallTimeout,
            CancellationToken cancellationToken)
        {
            if (client == null)
                throw new ArgumentNullException(
                    nameof(client));
            if (forwardedCallTimeout
                <= TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(forwardedCallTimeout));
            }
            var reader = new BoundedUtf8LineReader(
                input,
                AgentFrameCodec.MaxJsonPayloadLength);
            if (adapter
                == TrustedUnattendedAdapter.Mcp)
            {
                return await RunMcpAsync(
                    reader,
                    client,
                    output,
                    forwardedCallTimeout,
                    cancellationToken)
                    .ConfigureAwait(false);
            }
            bool inputError = false;
            while (true)
            {
                string line =
                    await reader.ReadLineAsync(
                        cancellationToken)
                        .ConfigureAwait(false);
                if (line == null)
                    break;
                if (string.IsNullOrWhiteSpace(line))
                    continue;

                try
                {
                    await HandleJsonlWithDeadlineAsync(
                            client,
                            line,
                            output,
                            forwardedCallTimeout,
                            cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (Exception exception)
                    when (IsJsonlInputError(
                        exception))
                {
                    inputError = true;
                    await WriteJsonlInputErrorAsync(
                        output,
                        TryReadJsonRpcId(line),
                        exception,
                        cancellationToken)
                        .ConfigureAwait(false);
                }
            }
            return inputError ? 2 : 0;
        }

        private static async Task
            HandleJsonlWithDeadlineAsync(
                TrustedUnattendedAgentClient client,
                string line,
                Stream output,
                TimeSpan timeout,
                CancellationToken cancellationToken)
        {
            using var callSource =
                CancellationTokenSource
                    .CreateLinkedTokenSource(
                        cancellationToken);
            Task call =
                Task.Run(
                    () =>
                        HandleJsonlAsync(
                            client,
                            line,
                            output,
                            callSource.Token),
                    CancellationToken.None);
            try
            {
                await call.WaitAsync(
                        timeout,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (TimeoutException)
            {
                callSource.Cancel();
                BeginAuthenticatedConnectionAbort(
                    client);
                ObserveDetached(call);
                throw new TimeoutException(
                    "trusted_runner_jsonl_call_timeout");
            }
        }

        private static void ObserveDetached(Task task)
        {
            _ = task.ContinueWith(
                completed =>
                {
                    _ = completed.Exception;
                },
                CancellationToken.None,
                TaskContinuationOptions
                    .OnlyOnFaulted
                    | TaskContinuationOptions
                        .ExecuteSynchronously,
                TaskScheduler.Default);
        }

        private static async Task<int> RunMcpAsync(
            BoundedUtf8LineReader reader,
            TrustedUnattendedAgentClient client,
            Stream output,
            TimeSpan toolCallTimeout,
            CancellationToken cancellationToken)
        {
            var state =
                new McpSessionState();
            Task<string> pendingRead =
                reader.ReadLineAsync(
                    cancellationToken);
            ActiveMcpCall active = null;
            while (true)
            {
                if (active == null)
                {
                    string line =
                        await pendingRead
                            .ConfigureAwait(false);
                    if (line == null)
                        return 0;
                    pendingRead =
                        reader.ReadLineAsync(
                            cancellationToken);
                    if (string.IsNullOrWhiteSpace(
                            line))
                    {
                        continue;
                    }
                    if (state
                            .InitializedNotificationReceived
                        && TryReadMcpRequest(
                            line,
                            "tools/call",
                            out string requestId))
                    {
                        active =
                            ActiveMcpCall.Start(
                                requestId,
                                (buffer, token) =>
                                    HandleMcpAsync(
                                        client,
                                        line,
                                        buffer,
                                        state,
                                        token),
                                toolCallTimeout,
                                cancellationToken);
                        continue;
                    }
                    await RunMcpProtocolOutputAsync(
                            client,
                            token =>
                                HandleMcpAsync(
                                    client,
                                    line,
                                    output,
                                    state,
                                    token),
                            toolCallTimeout,
                            cancellationToken)
                        .ConfigureAwait(false);
                    continue;
                }

                Task completed =
                    await Task.WhenAny(
                            active.Completion,
                            pendingRead,
                            active.Timeout)
                        .ConfigureAwait(false);
                if (completed == active.Completion)
                {
                    try
                    {
                        await active.Completion
                            .ConfigureAwait(false);
                        await RunActiveMcpOutputAsync(
                                active,
                                client,
                                token =>
                                    active.CopyResponseAsync(
                                        output,
                                        token),
                                "trusted_runner_mcp_call_timeout",
                                cancellationToken)
                            .ConfigureAwait(false);
                    }
                    finally
                    {
                        active.Dispose();
                    }
                    active = null;
                    continue;
                }
                if (completed == active.Timeout)
                {
                    await FailActiveMcpCallAsync(
                            active,
                            client,
                            "trusted_runner_mcp_call_timeout")
                        .ConfigureAwait(false);
                }

                string concurrentLine =
                    await pendingRead
                        .ConfigureAwait(false);
                if (active.DeadlineExpired)
                {
                    await FailActiveMcpCallAsync(
                            active,
                            client,
                            "trusted_runner_mcp_call_timeout")
                        .ConfigureAwait(false);
                }
                if (concurrentLine == null)
                {
                    Task eofCompletion =
                        await Task.WhenAny(
                                active.Completion,
                                active.Timeout)
                            .ConfigureAwait(false);
                    if (eofCompletion
                        != active.Completion)
                    {
                        await FailActiveMcpCallAsync(
                                active,
                                client,
                                "trusted_runner_mcp_eof_call_timeout")
                            .ConfigureAwait(false);
                    }
                    try
                    {
                        await active.Completion
                            .ConfigureAwait(false);
                        await RunActiveMcpOutputAsync(
                                active,
                                client,
                                token =>
                                    active.CopyResponseAsync(
                                        output,
                                        token),
                                "trusted_runner_mcp_eof_call_timeout",
                                cancellationToken)
                            .ConfigureAwait(false);
                    }
                    finally
                    {
                        active.Dispose();
                    }
                    return 0;
                }
                pendingRead =
                    reader.ReadLineAsync(
                        cancellationToken);
                if (string.IsNullOrWhiteSpace(
                        concurrentLine))
                {
                    continue;
                }
                if (TryReadMcpCancellation(
                        concurrentLine,
                        out string cancelledId))
                {
                    if (!string.Equals(
                            cancelledId,
                            active.RequestId,
                            StringComparison.Ordinal))
                    {
                        await AbandonActiveMcpCallAsync(
                                active,
                                client)
                            .ConfigureAwait(false);
                        throw new InvalidDataException(
                            "trusted_runner_mcp_cancellation_mismatch");
                    }
                    await AbandonActiveMcpCallAsync(
                            active,
                            client)
                        .ConfigureAwait(false);
                    throw new InvalidDataException(
                        "trusted_runner_mcp_call_cancelled");
                }
                if (TryReadMcpRequest(
                        concurrentLine,
                        "tools/call",
                        out string concurrentId))
                {
                    await RunActiveMcpOutputAsync(
                            active,
                            client,
                            token =>
                                WriteMcpErrorAsync(
                                    output,
                                    ParseMcpId(
                                        concurrentId),
                                    -32000,
                                    "Only one tools/call may be active",
                                    token),
                            "trusted_runner_mcp_call_timeout",
                            cancellationToken)
                        .ConfigureAwait(false);
                    continue;
                }
                await RunActiveMcpOutputAsync(
                        active,
                        client,
                        token =>
                            HandleMcpAsync(
                                client,
                                concurrentLine,
                                output,
                                state,
                                token),
                        "trusted_runner_mcp_call_timeout",
                        cancellationToken)
                    .ConfigureAwait(false);
            }
        }

        private static async Task
            RunMcpProtocolOutputAsync(
                TrustedUnattendedAgentClient client,
                Func<CancellationToken, Task> operation,
                TimeSpan timeout,
                CancellationToken cancellationToken)
        {
            using var outputSource =
                CancellationTokenSource
                    .CreateLinkedTokenSource(
                        cancellationToken);
            Task outputTask =
                Task.Run(
                    () => operation(
                        outputSource.Token),
                    CancellationToken.None);
            try
            {
                await outputTask.WaitAsync(
                        timeout,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (TimeoutException)
            {
                outputSource.Cancel();
                BeginAuthenticatedConnectionAbort(
                    client);
                ObserveDetached(outputTask);
                throw new TimeoutException(
                    "trusted_runner_mcp_protocol_output_timeout");
            }
            catch (OperationCanceledException)
                when (cancellationToken
                    .IsCancellationRequested)
            {
                outputSource.Cancel();
                BeginAuthenticatedConnectionAbort(
                    client);
                ObserveDetached(outputTask);
                throw;
            }
        }

        private static async Task
            RunActiveMcpOutputAsync(
                ActiveMcpCall active,
                TrustedUnattendedAgentClient client,
                Func<CancellationToken, Task> operation,
                string timeoutReason,
                CancellationToken cancellationToken)
        {
            if (active == null)
                throw new ArgumentNullException(
                    nameof(active));
            if (operation == null)
                throw new ArgumentNullException(
                    nameof(operation));

            // Invoke on the thread pool so a Stream implementation that
            // blocks synchronously before returning its Task cannot prevent
            // this loop from observing the call's original wall-clock
            // deadline. Thread-pool workers are background threads; no
            // dedicated foreground thread is left behind on fail-close.
            Task outputTask =
                Task.Run(
                    () => operation(
                        active.OperationToken),
                    CancellationToken.None);
            Task externalCancellation =
                cancellationToken.CanBeCanceled
                    ? Task.Delay(
                        Timeout.InfiniteTimeSpan,
                        cancellationToken)
                    : Task.Delay(
                        Timeout.InfiniteTimeSpan);
            Task completed =
                await Task.WhenAny(
                        outputTask,
                        active.Timeout,
                        externalCancellation)
                    .ConfigureAwait(false);
            if (completed == outputTask
                && !active.DeadlineExpired)
            {
                await outputTask
                    .ConfigureAwait(false);
                return;
            }

            ObserveDetached(outputTask);
            await AbandonActiveMcpCallAsync(
                    active,
                    client)
                .ConfigureAwait(false);
            if (cancellationToken
                .IsCancellationRequested
                && !active.DeadlineExpired)
            {
                cancellationToken
                    .ThrowIfCancellationRequested();
            }
            throw new TimeoutException(
                timeoutReason);
        }

        private static async Task
            FailActiveMcpCallAsync(
                ActiveMcpCall active,
                TrustedUnattendedAgentClient client,
                string reason)
        {
            await AbandonActiveMcpCallAsync(
                    active,
                    client)
                .ConfigureAwait(false);
            throw new TimeoutException(reason);
        }

        private static async Task
            AbandonActiveMcpCallAsync(
                ActiveMcpCall active,
                TrustedUnattendedAgentClient client)
        {
            active.Cancel();
            BeginAuthenticatedConnectionAbort(
                client);
            active.DisposeWhenCompleted();
            await Task.CompletedTask
                .ConfigureAwait(false);
        }

        private static void
            BeginAuthenticatedConnectionAbort(
                TrustedUnattendedAgentClient client)
        {
            // DisposeAsync is synchronous for the production named-pipe
            // client today. Keep invocation off the active loop anyway so a
            // hostile test Stream (or future transport) cannot turn timeout
            // cleanup into another unbounded synchronous wait.
            Task abort =
                Task.Run(
                    async () =>
                    {
                        await client.DisposeAsync()
                            .ConfigureAwait(false);
                    },
                    CancellationToken.None);
            ObserveDetached(abort);
        }

        private static bool IsJsonlInputError(
            Exception exception)
        {
            if (exception is JsonException
                || exception is DecoderFallbackException)
            {
                return true;
            }
            if (exception is not InvalidDataException data)
                return false;
            return data.Message.StartsWith(
                    "trusted_runner_request_invalid:",
                    StringComparison.Ordinal)
                || string.Equals(
                    data.Message,
                    "trusted_runner_capability_not_granted",
                    StringComparison.Ordinal)
                || string.Equals(
                    data.Message,
                    "trusted_runner_hello_reserved",
                    StringComparison.Ordinal)
                || string.Equals(
                    data.Message,
                    "JSON object required",
                    StringComparison.Ordinal)
                || string.Equals(
                    data.Message,
                    "Duplicate JSON property",
                    StringComparison.Ordinal);
        }

        private static string TryReadJsonRpcId(
            string line)
        {
            try
            {
                using JsonDocument document =
                    JsonDocument.Parse(line);
                if (document.RootElement.ValueKind
                        == JsonValueKind.Object
                    && document.RootElement
                        .TryGetProperty(
                            "id",
                            out JsonElement id)
                    && id.ValueKind
                        == JsonValueKind.String)
                {
                    string value = id.GetString();
                    if (value != null
                        && value.Length
                            >= AgentProtocolV1
                                .MinimumOpaqueIdCharacters
                        && value.Length
                            <= AgentProtocolV1
                                .MaximumOpaqueIdCharacters
                        && value.All(
                            character =>
                                character >= 'A'
                                    && character <= 'Z'
                                || character >= 'a'
                                    && character <= 'z'
                                || character >= '0'
                                    && character <= '9'
                                || character == '-'
                                || character == '_'))
                    {
                        return value;
                    }
                }
            }
            catch (JsonException)
            {
            }
            return null;
        }

        private static Task WriteJsonlInputErrorAsync(
            Stream output,
            string id,
            Exception exception,
            CancellationToken cancellationToken)
        {
            bool capabilityDenied =
                exception is InvalidDataException data
                && string.Equals(
                    data.Message,
                    "trusted_runner_capability_not_granted",
                    StringComparison.Ordinal);
            return WriteJsonAsync(
                output,
                new
                {
                    jsonrpc = "2.0",
                    id = id == null
                        ? JsonSerializer
                            .SerializeToElement<
                                object>(null)
                        : JsonSerializer
                            .SerializeToElement(id),
                    error = new
                    {
                        code = capabilityDenied
                            ? -32601
                            : -32600,
                        message = capabilityDenied
                            ? "Method not available"
                            : "Invalid Request",
                        data = new
                        {
                            reasonCode =
                                capabilityDenied
                                    ? "capability_denied"
                                    : "malformed_json"
                        }
                    }
                },
                cancellationToken);
        }

        private static async Task HandleJsonlAsync(
            TrustedUnattendedAgentClient client,
            string line,
            Stream output,
            CancellationToken cancellationToken)
        {
            using JsonDocument request =
                ParseStrictObject(line);
            TrustedAgentCallResult call =
                await client.CallAsync(
                    request.RootElement,
                    cancellationToken)
                    .ConfigureAwait(false);
            JsonElement response = call.Response;
            if (call.Binary == null
                || !response.TryGetProperty(
                    "result",
                    out JsonElement result))
            {
                await WriteJsonAsync(
                    output,
                    response,
                    cancellationToken)
                    .ConfigureAwait(false);
                return;
            }

            var envelope = new
            {
                jsonrpc = "2.0",
                id = response.GetProperty("id")
                    .GetString(),
                result = new
                {
                    result,
                    metadata =
                        call.Binary.Metadata,
                    contentBase64 =
                        Convert.ToBase64String(
                            call.Binary.Content)
                }
            };
            await WriteJsonAsync(
                output,
                envelope,
                cancellationToken)
                .ConfigureAwait(false);
        }

        private static async Task HandleMcpAsync(
            TrustedUnattendedAgentClient client,
            string line,
            Stream output,
            McpSessionState state,
            CancellationToken cancellationToken)
        {
            JsonElement? outerId = null;
            bool notification = false;
            try
            {
                using JsonDocument document =
                    ParseStrictObject(line);
                JsonElement root =
                    document.RootElement;
                notification =
                    !root.TryGetProperty(
                        "id",
                        out _);
                ValidateMcpEnvelope(root);
                bool hasId =
                    root.TryGetProperty(
                        "id",
                        out JsonElement id);
                if (hasId)
                    outerId = id.Clone();
                string method =
                    root.GetProperty("method")
                        .GetString();

                if (notification)
                {
                    if (string.Equals(
                            method,
                            "notifications/initialized",
                            StringComparison.Ordinal))
                    {
                        if (!state
                                .InitializeResponded
                            || state
                                .InitializedNotificationReceived
                            || !HasNoOrEmptyParams(
                                root))
                        {
                            throw new McpError(
                                -32600,
                                "Invalid initialized notification");
                        }
                        state
                            .InitializedNotificationReceived =
                                true;
                        return;
                    }
                    if (!string.Equals(
                            method,
                            "notifications/cancelled",
                            StringComparison.Ordinal)
                        || !state
                            .InitializedNotificationReceived)
                    {
                        throw new McpError(
                            -32601,
                            "Method not found");
                    }
                    return;
                }

                object result;
                if (string.Equals(
                        method,
                        "initialize",
                        StringComparison.Ordinal))
                {
                    if (state.InitializeResponded)
                        throw new McpError(
                            -32600,
                            "initialize may be called only once");
                    ValidateInitializeParams(root);
                    state.InitializeResponded =
                        true;
                    result = new
                    {
                        protocolVersion =
                            McpProtocolVersion,
                        capabilities = new
                        {
                            tools = new
                            {
                                listChanged = false
                            }
                        },
                        serverInfo = new
                        {
                            name =
                                "cf7-agent-runtime",
                            version = "1.0.0"
                        },
                        instructions =
                            "Tools map directly to the compiled closed CF7 Agent Runtime v1 registry."
                    };
                }
                else
                {
                    if (!state
                            .InitializedNotificationReceived)
                    {
                        throw new McpError(
                            -32002,
                            "MCP adapter is not initialized");
                    }
                    if (string.Equals(
                            method,
                            "tools/list",
                            StringComparison.Ordinal))
                    {
                        if (!HasNoOrEmptyParams(
                                root))
                        {
                            throw new McpError(
                                -32602,
                                "Pagination cursor is not supported");
                        }
                        result = new
                        {
                            tools = AgentMethodsV1.All
                                .Values
                                .Where(
                                    definition =>
                                        !definition
                                            .PreAuthentication
                                        && client
                                            .GrantedCapabilities
                                            .Contains(
                                                definition
                                                    .RequiredCapability))
                                .OrderBy(
                                    definition =>
                                        definition.Name,
                                    StringComparer.Ordinal)
                                .Select(
                                    definition => new
                                    {
                                        name =
                                            definition.Name,
                                        description =
                                            "CF7 Agent Runtime v1 method; requires "
                                            + definition
                                                .RequiredCapability
                                            + ".",
                                        inputSchema =
                                            BuildInputSchema(
                                                definition)
                                    })
                                .ToArray()
                        };
                    }
                    else if (string.Equals(
                        method,
                        "tools/call",
                        StringComparison.Ordinal))
                    {
                        JsonElement parameters =
                            RequireObjectParams(root);
                        if (parameters
                                .EnumerateObject()
                                .Select(
                                    property =>
                                        property.Name)
                                .OrderBy(
                                    value => value,
                                    StringComparer.Ordinal)
                                .SequenceEqual(
                                    new[]
                                    {
                                        "arguments",
                                        "name"
                                    },
                                    StringComparer.Ordinal)
                            == false
                            || !parameters.TryGetProperty(
                                "name",
                                out JsonElement nameElement)
                            || nameElement.ValueKind
                                != JsonValueKind.String
                            || !parameters.TryGetProperty(
                                "arguments",
                                out JsonElement arguments)
                            || arguments.ValueKind
                                != JsonValueKind.Object)
                        {
                            throw new McpError(
                                -32602,
                                "tools/call requires exact name and arguments");
                        }
                        string toolName =
                            nameElement.GetString();
                        if (!AgentMethodsV1.TryGet(
                                toolName,
                                out AgentMethodDefinition
                                    definition)
                            || definition.PreAuthentication
                            || !client
                                .GrantedCapabilities
                                .Contains(
                                    definition
                                        .RequiredCapability))
                        {
                            throw new McpError(
                                -32602,
                                "Unknown or ungranted tool");
                        }
                        JsonElement inner =
                            JsonSerializer
                                .SerializeToElement(
                                    new AgentJsonRpcRequest
                                    {
                                        Id =
                                            AgentRendezvousStore
                                                .GenerateOpaqueId(),
                                        Method = toolName,
                                        Params =
                                            arguments.Clone()
                                    },
                                    AgentProtocolV1
                                        .JsonOptions);
                        TrustedAgentCallResult call =
                            await client.CallAsync(
                                inner,
                                cancellationToken)
                                .ConfigureAwait(false);
                        object toolPayload =
                            ToToolPayload(call);
                        result = toolPayload;
                    }
                    else
                    {
                        throw new McpError(
                            -32601,
                            "Method not found");
                    }
                }

                await WriteJsonAsync(
                    output,
                    new
                    {
                        jsonrpc = "2.0",
                        id = outerId.Value,
                        result
                    },
                    cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (McpError error)
            {
                if (notification)
                    return;
                await WriteMcpErrorAsync(
                    output,
                    outerId,
                    error.Code,
                    error.Message,
                    cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (Exception)
            {
                if (notification)
                    return;
                await WriteMcpErrorAsync(
                    output,
                    outerId,
                    outerId.HasValue
                        ? -32603
                        : -32700,
                    outerId.HasValue
                        ? "Internal error"
                        : "Parse error",
                    cancellationToken)
                    .ConfigureAwait(false);
            }
        }

        private static object ToToolPayload(
            TrustedAgentCallResult call)
        {
            JsonElement response = call.Response;
            if (response.TryGetProperty(
                    "error",
                    out JsonElement error))
            {
                return new
                {
                    isError = true,
                    content = new[]
                    {
                        new
                        {
                            type = "text",
                            text = error.GetRawText()
                        }
                    }
                };
            }
            JsonElement result =
                response.GetProperty("result");
            string text;
            if (call.Binary == null)
            {
                text = result.GetRawText();
            }
            else
            {
                text = JsonSerializer.Serialize(
                    new
                    {
                        result,
                        metadata =
                            call.Binary.Metadata,
                        contentBase64 =
                            Convert.ToBase64String(
                                call.Binary.Content)
                    },
                    AgentProtocolV1.JsonOptions);
            }
            return new
            {
                content = new[]
                {
                    new
                    {
                        type = "text",
                        text
                    }
                }
            };
        }

        private static JsonDocument ParseStrictObject(
            string line)
        {
            byte[] bytes =
                StrictUtf8.GetBytes(line);
            JsonDocument document =
                JsonDocument.Parse(
                    bytes,
                    new JsonDocumentOptions
                    {
                        AllowTrailingCommas = false,
                        CommentHandling =
                            JsonCommentHandling.Disallow,
                        MaxDepth = 32
                    });
            if (document.RootElement.ValueKind
                != JsonValueKind.Object)
            {
                document.Dispose();
                throw new InvalidDataException(
                    "JSON object required");
            }
            RejectDuplicateProperties(
                document.RootElement);
            return document;
        }

        private static void RejectDuplicateProperties(
            JsonElement element)
        {
            if (element.ValueKind
                == JsonValueKind.Object)
            {
                var seen = new HashSet<string>(
                    StringComparer.Ordinal);
                foreach (JsonProperty property
                    in element.EnumerateObject())
                {
                    if (!seen.Add(property.Name))
                    {
                        throw new InvalidDataException(
                            "Duplicate JSON property");
                    }
                    RejectDuplicateProperties(
                        property.Value);
                }
            }
            else if (element.ValueKind
                == JsonValueKind.Array)
            {
                foreach (JsonElement item
                    in element.EnumerateArray())
                {
                    RejectDuplicateProperties(item);
                }
            }
        }

        private static void ValidateMcpEnvelope(
            JsonElement root)
        {
            var allowed = new HashSet<string>(
                new[]
                {
                    "jsonrpc",
                    "id",
                    "method",
                    "params"
                },
                StringComparer.Ordinal);
            if (root.EnumerateObject().Any(
                    property =>
                        !allowed.Contains(
                            property.Name))
                || !root.TryGetProperty(
                    "jsonrpc",
                    out JsonElement version)
                || version.ValueKind
                    != JsonValueKind.String
                || !string.Equals(
                    version.GetString(),
                    "2.0",
                    StringComparison.Ordinal)
                || !root.TryGetProperty(
                    "method",
                    out JsonElement method)
                || method.ValueKind
                    != JsonValueKind.String
                || string.IsNullOrEmpty(
                    method.GetString()))
            {
                throw new McpError(
                    -32600,
                    "Invalid Request");
            }
            if (root.TryGetProperty(
                    "id",
                    out JsonElement id)
                && !IsValidMcpId(id))
            {
                throw new McpError(
                    -32600,
                    "Invalid Request");
            }
        }

        private static bool IsValidMcpId(
            JsonElement id)
        {
            if (id.ValueKind
                == JsonValueKind.String)
            {
                string value = id.GetString();
                return !string.IsNullOrEmpty(value)
                    && value.Length <= 128;
            }
            return id.ValueKind
                    == JsonValueKind.Number
                && id.TryGetInt64(
                    out long numeric)
                && numeric
                    >= -9_007_199_254_740_991L
                && numeric
                    <= 9_007_199_254_740_991L;
        }

        private static bool TryReadMcpRequest(
            string line,
            string expectedMethod,
            out string requestId)
        {
            requestId = null;
            try
            {
                using JsonDocument document =
                    ParseStrictObject(line);
                JsonElement root =
                    document.RootElement;
                ValidateMcpEnvelope(root);
                if (!root.TryGetProperty(
                        "id",
                        out JsonElement id)
                    || !root.TryGetProperty(
                        "method",
                        out JsonElement method)
                    || !string.Equals(
                        method.GetString(),
                        expectedMethod,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                requestId = McpIdKey(id);
                return true;
            }
            catch (Exception exception)
                when (exception
                    is JsonException
                    || exception
                        is InvalidDataException
                    || exception is McpError)
            {
                return false;
            }
        }

        private static bool TryReadMcpCancellation(
            string line,
            out string requestId)
        {
            requestId = null;
            try
            {
                using JsonDocument document =
                    ParseStrictObject(line);
                JsonElement root =
                    document.RootElement;
                ValidateMcpEnvelope(root);
                if (root.TryGetProperty(
                        "id",
                        out _)
                    || !string.Equals(
                        root.GetProperty("method")
                            .GetString(),
                        "notifications/cancelled",
                        StringComparison.Ordinal)
                    || !root.TryGetProperty(
                        "params",
                        out JsonElement parameters)
                    || parameters.ValueKind
                        != JsonValueKind.Object
                    || !parameters.TryGetProperty(
                        "requestId",
                        out JsonElement cancelledId)
                    || !IsValidMcpId(
                        cancelledId))
                {
                    return false;
                }
                string[] names =
                    parameters
                        .EnumerateObject()
                        .Select(
                            property =>
                                property.Name)
                        .OrderBy(
                            name => name,
                            StringComparer.Ordinal)
                        .ToArray();
                if (!names.SequenceEqual(
                        new[] { "requestId" },
                        StringComparer.Ordinal)
                    && !names.SequenceEqual(
                        new[]
                        {
                            "reason",
                            "requestId"
                        },
                        StringComparer.Ordinal))
                {
                    return false;
                }
                if (parameters.TryGetProperty(
                        "reason",
                        out JsonElement reason)
                    && (reason.ValueKind
                            != JsonValueKind.String
                        || reason.GetString()
                            .Length > 512))
                {
                    return false;
                }
                requestId =
                    McpIdKey(cancelledId);
                return true;
            }
            catch (Exception exception)
                when (exception
                    is JsonException
                    || exception
                        is InvalidDataException
                    || exception is McpError)
            {
                return false;
            }
        }

        private static string McpIdKey(
            JsonElement id)
        {
            return id.ValueKind
                == JsonValueKind.String
                ? "s:" + id.GetString()
                : "n:"
                    + id.GetInt64()
                        .ToString(
                            System.Globalization
                                .CultureInfo.InvariantCulture);
        }

        private static JsonElement ParseMcpId(
            string key)
        {
            if (key.StartsWith(
                    "s:",
                    StringComparison.Ordinal))
            {
                return JsonSerializer
                    .SerializeToElement(
                        key.Substring(2));
            }
            return JsonSerializer
                .SerializeToElement(
                    long.Parse(
                        key.Substring(2),
                        System.Globalization
                            .CultureInfo.InvariantCulture));
        }

        private static JsonElement RequireObjectParams(
            JsonElement root)
        {
            if (!root.TryGetProperty(
                    "params",
                    out JsonElement parameters)
                || parameters.ValueKind
                    != JsonValueKind.Object)
            {
                throw new McpError(
                    -32602,
                    "Object params are required");
            }
            return parameters;
        }

        private static void ValidateInitializeParams(
            JsonElement root)
        {
            JsonElement parameters =
                RequireObjectParams(root);
            if (!ExactPropertyNames(
                    parameters,
                    "protocolVersion",
                    "capabilities",
                    "clientInfo")
                || !parameters.TryGetProperty(
                    "protocolVersion",
                    out JsonElement version)
                || version.ValueKind
                    != JsonValueKind.String
                || !string.Equals(
                    version.GetString(),
                    McpProtocolVersion,
                    StringComparison.Ordinal)
                || !parameters.TryGetProperty(
                    "capabilities",
                    out JsonElement capabilities)
                || capabilities.ValueKind
                    != JsonValueKind.Object
                || !parameters.TryGetProperty(
                    "clientInfo",
                    out JsonElement clientInfo)
                || clientInfo.ValueKind
                    != JsonValueKind.Object)
            {
                throw new McpError(
                    -32602,
                    "Invalid initialize parameters");
            }
            if (capabilities
                .EnumerateObject()
                .Any(
                    property =>
                        property.Value
                            .ValueKind
                            != JsonValueKind
                                .Object))
            {
                throw new McpError(
                    -32602,
                    "Invalid client capabilities");
            }
            if (capabilities.TryGetProperty(
                    "roots",
                    out JsonElement roots)
                && roots.EnumerateObject()
                    .Any(
                        property =>
                            !string.Equals(
                                property.Name,
                                "listChanged",
                                StringComparison.Ordinal)
                            || property.Value
                                .ValueKind
                                != JsonValueKind.True
                                && property.Value
                                    .ValueKind
                                    != JsonValueKind
                                        .False))
            {
                throw new McpError(
                    -32602,
                    "Invalid roots capability");
            }
            var clientInfoNames =
                clientInfo
                    .EnumerateObject()
                    .Select(
                        property =>
                            property.Name)
                    .OrderBy(
                        name => name,
                        StringComparer.Ordinal)
                    .ToArray();
            if (!clientInfoNames.SequenceEqual(
                    new[] { "name", "version" },
                    StringComparer.Ordinal)
                && !clientInfoNames.SequenceEqual(
                    new[]
                    {
                        "name",
                        "title",
                        "version"
                    },
                    StringComparer.Ordinal))
            {
                throw new McpError(
                    -32602,
                    "Invalid clientInfo");
            }
            RequireBoundedMcpString(
                clientInfo,
                "name",
                128);
            RequireBoundedMcpString(
                clientInfo,
                "version",
                64);
            if (clientInfo.TryGetProperty(
                    "title",
                    out _))
            {
                RequireBoundedMcpString(
                    clientInfo,
                    "title",
                    128);
            }
        }

        private static void RequireBoundedMcpString(
            JsonElement parent,
            string name,
            int maximumLength)
        {
            if (!parent.TryGetProperty(
                    name,
                    out JsonElement value)
                || value.ValueKind
                    != JsonValueKind.String
                || string.IsNullOrWhiteSpace(
                    value.GetString())
                || value.GetString().Length
                    > maximumLength)
            {
                throw new McpError(
                    -32602,
                    "Invalid " + name);
            }
        }

        private static bool HasNoOrEmptyParams(
            JsonElement root)
        {
            if (!root.TryGetProperty(
                    "params",
                    out JsonElement parameters))
            {
                return true;
            }
            return parameters.ValueKind
                    == JsonValueKind.Object
                && !parameters
                    .EnumerateObject()
                    .Any();
        }

        private static bool ExactPropertyNames(
            JsonElement element,
            params string[] expected)
        {
            return element
                .EnumerateObject()
                .Select(
                    property =>
                        property.Name)
                .OrderBy(
                    name => name,
                    StringComparer.Ordinal)
                .SequenceEqual(
                    expected.OrderBy(
                        name => name,
                        StringComparer.Ordinal),
                    StringComparer.Ordinal);
        }

        private static object BuildInputSchema(
            AgentMethodDefinition definition)
        {
            if (!AgentParameterContractsV1
                .TryGet(
                    definition.ParameterContract,
                    out AgentParameterContractDefinition
                        contract))
            {
                throw new InvalidOperationException(
                    "trusted_runner_mcp_contract_missing");
            }
            var properties =
                contract.RequiredProperties
                    .Concat(
                        contract.OptionalProperties)
                    .Distinct(
                        StringComparer.Ordinal)
                    .ToDictionary(
                        name => name,
                        name =>
                            PropertySchema(
                                contract.Name,
                                name),
                        StringComparer.Ordinal);
            return new
            {
                type = "object",
                properties,
                required =
                    contract.RequiredProperties
                        .ToArray(),
                additionalProperties = false,
                x_cf7ParameterContract =
                    definition.ParameterContract
            };
        }

        private static object PropertySchema(
            string parameterContract,
            string name)
        {
            if (string.Equals(
                    parameterContract,
                    AgentParameterContractsV1
                        .LeaseAcquire,
                    StringComparison.Ordinal)
                && string.Equals(
                    name,
                    "expectedRevision",
                    StringComparison.Ordinal))
            {
                return new
                {
                    type = "string"
                };
            }
            if (name.StartsWith(
                    "allow",
                    StringComparison.Ordinal))
            {
                return new
                {
                    type = "boolean"
                };
            }
            if (name is "capabilities"
                or "targetScope"
                or "targetIds"
                or "targetKinds"
                or "dataScopes")
            {
                return new
                {
                    type = "array",
                    items = new
                    {
                        type = "string"
                    }
                };
            }
            if (name is "arguments"
                or "binding")
            {
                return new
                {
                    type = "object"
                };
            }
            if (name.EndsWith(
                    "Generation",
                    StringComparison.Ordinal)
                || name.EndsWith(
                    "Epoch",
                    StringComparison.Ordinal)
                || name.EndsWith(
                    "Revision",
                    StringComparison.Ordinal)
                || name.EndsWith(
                    "Version",
                    StringComparison.Ordinal)
                || name.EndsWith(
                    "TtlMs",
                    StringComparison.Ordinal)
                || name.EndsWith(
                    "Limit",
                    StringComparison.Ordinal)
                || name is "deadlineMs"
                    or "offset"
                    or "count"
                    or "fromServerSequence"
                    or "maximumRecords")
            {
                return new
                {
                    type = "integer"
                };
            }
            return new
            {
                type = "string"
            };
        }

        private static Task WriteMcpErrorAsync(
            Stream output,
            JsonElement? id,
            int code,
            string message,
            CancellationToken cancellationToken)
        {
            return WriteJsonAsync(
                output,
                new
                {
                    jsonrpc = "2.0",
                    id,
                    error = new
                    {
                        code,
                        message,
                        data = new
                        {
                            reasonCode =
                                code == -32700
                                    ? "parse_error"
                                    : "request_rejected"
                        }
                    }
                },
                cancellationToken);
        }

        private static async Task WriteJsonAsync(
            Stream output,
            object value,
            CancellationToken cancellationToken)
        {
            byte[] payload =
                JsonSerializer.SerializeToUtf8Bytes(
                    value,
                    AgentProtocolV1.JsonOptions);
            try
            {
                await output.WriteAsync(
                    payload,
                    cancellationToken)
                    .ConfigureAwait(false);
                await output.WriteAsync(
                    new byte[] { (byte)'\n' },
                    cancellationToken)
                    .ConfigureAwait(false);
                await output.FlushAsync(
                    cancellationToken)
                    .ConfigureAwait(false);
            }
            finally
            {
                Array.Clear(
                    payload,
                    0,
                    payload.Length);
            }
        }

        private sealed class McpError : Exception
        {
            public McpError(
                int code,
                string message)
                : base(message)
            {
                Code = code;
            }

            public int Code { get; }
        }

        private sealed class ActiveMcpCall
            : IDisposable
        {
            private readonly MemoryStream
                _response;
            private readonly
                CancellationTokenSource _cancellation;
            private readonly
                CancellationTokenSource
                    _timeoutCancellation;
            private readonly long
                _deadlineTimestamp;
            private int _disposed;

            private ActiveMcpCall(
                string requestId,
                MemoryStream response,
                CancellationTokenSource cancellation,
                CancellationTokenSource
                    timeoutCancellation,
                long deadlineTimestamp,
                Task timeout,
                Task completion)
            {
                RequestId = requestId;
                _response = response;
                _cancellation = cancellation;
                _timeoutCancellation =
                    timeoutCancellation;
                _deadlineTimestamp =
                    deadlineTimestamp;
                Timeout = timeout;
                Completion = completion;
            }

            public string RequestId { get; }
            public Task Completion { get; }
            public Task Timeout { get; }
            public CancellationToken OperationToken =>
                _cancellation.Token;
            public bool DeadlineExpired =>
                Stopwatch.GetTimestamp()
                    >= _deadlineTimestamp;

            public static ActiveMcpCall Start(
                string requestId,
                Func<
                    Stream,
                    CancellationToken,
                    Task> handler,
                TimeSpan timeout,
                CancellationToken cancellationToken)
            {
                var response =
                    new MemoryStream();
                var cancellation =
                    CancellationTokenSource
                        .CreateLinkedTokenSource(
                            cancellationToken);
                var timeoutCancellation =
                    new CancellationTokenSource();
                long started =
                    Stopwatch.GetTimestamp();
                long timeoutTicks =
                    checked(
                        (long)Math.Ceiling(
                            timeout.TotalSeconds
                                * Stopwatch
                                    .Frequency));
                long deadlineTimestamp =
                    started > long.MaxValue
                            - timeoutTicks
                        ? long.MaxValue
                        : started + timeoutTicks;
                Task timeoutTask =
                    Task.Delay(
                        timeout,
                        timeoutCancellation.Token);
                Task completion =
                    Task.Run(
                        () => handler(
                            response,
                            cancellation.Token),
                        CancellationToken.None);
                return new ActiveMcpCall(
                    requestId,
                    response,
                    cancellation,
                    timeoutCancellation,
                    deadlineTimestamp,
                    timeoutTask,
                    completion);
            }

            public void Cancel()
            {
                _cancellation.Cancel();
            }

            public void DisposeWhenCompleted()
            {
                _ = Completion.ContinueWith(
                    (completed, state) =>
                    {
                        _ = completed.Exception;
                        ((ActiveMcpCall)state)
                            .Dispose();
                    },
                    this,
                    CancellationToken.None,
                    TaskContinuationOptions
                        .ExecuteSynchronously,
                    TaskScheduler.Default);
            }

            public async Task CopyResponseAsync(
                Stream output,
                CancellationToken cancellationToken)
            {
                byte[] bytes =
                    _response.ToArray();
                try
                {
                    await output.WriteAsync(
                        bytes,
                        cancellationToken)
                        .ConfigureAwait(false);
                    await output.FlushAsync(
                        cancellationToken)
                        .ConfigureAwait(false);
                }
                finally
                {
                    Array.Clear(
                        bytes,
                        0,
                        bytes.Length);
                }
            }

            public void Dispose()
            {
                if (Interlocked.Exchange(
                        ref _disposed,
                        1) != 0)
                {
                    return;
                }
                _timeoutCancellation.Cancel();
                _timeoutCancellation.Dispose();
                _cancellation.Dispose();
                _response.Dispose();
            }
        }

        private sealed class McpSessionState
        {
            public bool InitializeResponded
            {
                get;
                set;
            }

            public bool InitializedNotificationReceived
            {
                get;
                set;
            }
        }

        private sealed class BoundedUtf8LineReader
        {
            private readonly Stream _stream;
            private readonly int _maximumBytes;
            private readonly byte[] _readBuffer =
                new byte[4096];
            private readonly MemoryStream _line =
                new MemoryStream();
            private int _offset;
            private int _count;

            public BoundedUtf8LineReader(
                Stream stream,
                int maximumBytes)
            {
                _stream = stream
                    ?? throw new ArgumentNullException(
                        nameof(stream));
                _maximumBytes = maximumBytes;
            }

            public async Task<string> ReadLineAsync(
                CancellationToken cancellationToken)
            {
                _line.SetLength(0);
                while (true)
                {
                    if (_offset == _count)
                    {
                        _count =
                            await _stream.ReadAsync(
                                _readBuffer,
                                cancellationToken)
                                .ConfigureAwait(false);
                        _offset = 0;
                        if (_count == 0)
                        {
                            if (_line.Length == 0)
                                return null;
                            return DecodeLine();
                        }
                    }
                    byte value =
                        _readBuffer[_offset++];
                    if (value == (byte)'\n')
                        return DecodeLine();
                    if (_line.Length
                        >= _maximumBytes)
                    {
                        throw new InvalidDataException(
                            "trusted_runner_stdio_line_too_large");
                    }
                    _line.WriteByte(value);
                }
            }

            private string DecodeLine()
            {
                int length =
                    checked((int)_line.Length);
                if (length > 0
                    && _line.GetBuffer()[length - 1]
                        == (byte)'\r')
                {
                    length--;
                }
                return StrictUtf8.GetString(
                    _line.GetBuffer(),
                    0,
                    length);
            }
        }
    }
}
