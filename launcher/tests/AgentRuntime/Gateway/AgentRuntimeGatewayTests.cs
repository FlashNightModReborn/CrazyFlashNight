using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentRuntimeGatewayTests
    {
        [Fact]
        public async Task HelloConsumesTicketAndDisconnectRevokesPrincipal()
        {
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.SessionStatus);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_AAAAAAAAAAAAA",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(
                    AgentCapabilitiesV1.SessionStatus));
            JsonElement welcome = await ReadJsonAsync(
                pair.Client);

            Assert.Equal(
                "principal_AAAAAAAAAAAAA",
                welcome.GetProperty("result")
                    .GetProperty("securityPrincipalId")
                    .GetString());
            Assert.Equal(
                AgentCapabilitiesV1.SessionStatus,
                Assert.Single(
                    welcome.GetProperty("result")
                        .GetProperty("grantedCapabilities")
                        .EnumerateArray())
                    .GetString());
            Assert.Equal(1, fixture.Tickets.ConsumptionCount);
            Assert.Equal(
                "connection_AAAAAAAAAAAAA",
                fixture.Resources.RegisteredConnectionId);

            await WriteRequestAsync(
                pair.Client,
                "status",
                AgentCapabilitiesV1.SessionStatus,
                new { });
            JsonElement status = await ReadJsonAsync(pair.Client);
            Assert.True(
                status.GetProperty("result")
                    .GetProperty("ok")
                    .GetBoolean());

            pair.Client.Dispose();
            AgentConnectionTermination termination =
                await run.WaitAsync(TimeSpan.FromSeconds(5));

            Assert.Equal(
                AgentConnectionTerminationKind.CleanDisconnect,
                termination.Kind);
            Assert.Equal(
                "connection_AAAAAAAAAAAAA",
                fixture.Resources.RevokedConnectionId);
        }

        [Fact]
        public async Task ContentReadResponseAndBinaryChunkAreOneWriterPair()
        {
            byte[] content = { 1, 2, 3, 4, 5 };
            string handle =
                "content_AAAAAAAAAAAAAAAAAAAAA";
            string hash =
                Convert.ToHexString(
                    SHA256.HashData(content))
                    .ToLowerInvariant();
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new
                        {
                            handle,
                            offset = 0,
                            count = content.Length
                        },
                        new AgentRuntimeBinaryChunk(
                            new BinaryChunkMetadata
                            {
                                Handle = handle,
                                Offset = 0,
                                TotalLength = content.Length,
                                Final = true,
                                ContentHash = hash
                            },
                            content)));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.ContentRead,
                dispatcher);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_BBBBBBBBBBBBB",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(
                    AgentCapabilitiesV1.ContentRead));
            _ = await ReadJsonAsync(pair.Client);
            await WriteRequestAsync(
                pair.Client,
                "content",
                AgentMethodsV1.ContentRead,
                new
                {
                    handle,
                    offset = 0,
                    count = content.Length
                });

            JsonElement response = await ReadJsonAsync(pair.Client);
            Assert.Equal(
                handle,
                response.GetProperty("result")
                    .GetProperty("handle")
                    .GetString());
            AgentFrame binary = await Codec.ReadAsync(
                pair.Client,
                CancellationToken.None);
            Assert.Equal(AgentFrameKind.BinaryChunk, binary.Kind);
            DecodedBinaryChunk decoded =
                BinaryChunkCodecV1.Decode(binary.Payload.Span);
            Assert.Equal(content, decoded.Content);
            Assert.Equal(handle, decoded.Metadata.Handle);
            Assert.True(decoded.Metadata.Final);

            pair.Client.Dispose();
            _ = await run.WaitAsync(TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task
            DeadlineStartsWhenCompleteRequestFrameIsReceived()
        {
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { ok = true }));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.Click,
                dispatcher);
            var frameReceived =
                new TaskCompletionSource<bool>(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            fixture.Gateway
                .AfterRequestFrameReceivedForTests =
                    delegate
                    {
                        fixture.Clock.Advance(
                            TimeSpan.FromMilliseconds(501));
                        frameReceived.TrySetResult(true);
                    };
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_deadline_origin_A",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(AgentCapabilitiesV1.Click));
            _ = await ReadJsonAsync(pair.Client);
            await WriteRequestAsync(
                pair.Client,
                "click",
                AgentCapabilitiesV1.Click,
                ClickParams(500));
            await frameReceived.Task.WaitAsync(
                TimeSpan.FromSeconds(5));

            pair.Client.Dispose();
            _ = await run.WaitAsync(TimeSpan.FromSeconds(5));
            Assert.Equal(0, dispatcher.InvocationCount);
        }

        [Fact]
        public async Task
            DeadlineCoversEveryFrameInBinarySuccessResponse()
        {
            byte[] content = { 7, 8, 9 };
            string handle =
                "content_DEADLINEAAAAAAAAAAAA";
            string hash =
                Convert.ToHexString(
                    SHA256.HashData(content))
                    .ToLowerInvariant();
            int prepareCount = 0;
            int commitCount = 0;
            int abortBeforeWriteCount = 0;
            int abortAfterWriteStartedCount = 0;
            var aborted =
                new TaskCompletionSource<bool>(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var completion =
                new AgentRuntimeResponseCompletion(
                    delegate
                    {
                        Interlocked.Increment(ref prepareCount);
                        return true;
                    },
                    () => Interlocked.Increment(
                        ref commitCount),
                    writeStarted =>
                    {
                        if (writeStarted)
                        {
                            Interlocked.Increment(
                                ref abortAfterWriteStartedCount);
                        }
                        else
                        {
                            Interlocked.Increment(
                                ref abortBeforeWriteCount);
                        }
                        aborted.TrySetResult(true);
                    });
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { handle },
                        new AgentRuntimeBinaryChunk(
                            new BinaryChunkMetadata
                            {
                                Handle = handle,
                                Offset = 0,
                                TotalLength = content.Length,
                                Final = true,
                                ContentHash = hash
                            },
                            content),
                        completion));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.Click,
                dispatcher);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_binary_deadline_A",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(AgentCapabilitiesV1.Click));
            _ = await ReadJsonAsync(pair.Client);
            // One CF7A frame is two stream writes (header + payload).
            // Let the JSON frame complete, then stall the binary header.
            pair.ServerWrites.BlockWriteAfter(
                completeWritesBeforeBlock: 2);
            await WriteRequestAsync(
                pair.Client,
                "click",
                AgentCapabilitiesV1.Click,
                ClickParams(1_000));

            JsonElement response =
                await ReadJsonAsync(pair.Client);
            Assert.Equal(
                handle,
                response.GetProperty("result")
                    .GetProperty("handle")
                    .GetString());
            await pair.ServerWrites.WriteEntered.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Equal(1, Volatile.Read(ref prepareCount));
            Assert.Equal(0, Volatile.Read(ref commitCount));

            await aborted.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Equal(0, Volatile.Read(ref commitCount));
            Assert.Equal(
                0,
                Volatile.Read(ref abortBeforeWriteCount));
            Assert.Equal(
                1,
                Volatile.Read(ref abortAfterWriteStartedCount));

            pair.Client.Dispose();
            _ = await run.WaitAsync(TimeSpan.FromSeconds(5));
        }

        [Fact]
        public Task
            ResponseCompletionRejectionBeforeWriteProducesNoSuccessFrame()
        {
            return AssertResponsePreparationFailureProducesNoSuccessFrameAsync(
                throwBeforeWrite: false);
        }

        [Fact]
        public Task
            ResponseCompletionPrepareExceptionProducesNoSuccessFrame()
        {
            return AssertResponsePreparationFailureProducesNoSuccessFrameAsync(
                throwBeforeWrite: true);
        }

        [Fact]
        public async Task
            ResponseCompletionCommitsOnlyAfterCompleteSuccessFrameWrite()
        {
            int commitCount = 0;
            int abortCount = 0;
            var committed =
                new TaskCompletionSource<bool>(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var completion =
                new AgentRuntimeResponseCompletion(
                    delegate
                    {
                        Interlocked.Increment(ref commitCount);
                        committed.TrySetResult(true);
                    },
                    () => Interlocked.Increment(
                        ref abortCount));
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { ok = true },
                        responseCompletion: completion));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.SessionStatus,
                dispatcher);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_flush_commit_A",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(
                    AgentCapabilitiesV1.SessionStatus));
            _ = await ReadJsonAsync(pair.Client);
            pair.ServerWrites.BlockNextWrite();
            await WriteRequestAsync(
                pair.Client,
                "status",
                AgentCapabilitiesV1.SessionStatus,
                new { });
            await pair.ServerWrites.WriteEntered.WaitAsync(
                TimeSpan.FromSeconds(5));

            Assert.Equal(0, Volatile.Read(ref commitCount));
            Assert.Equal(0, Volatile.Read(ref abortCount));

            pair.ServerWrites.ReleaseBlockedWrite();
            JsonElement response =
                await ReadJsonAsync(pair.Client);
            Assert.True(
                response.GetProperty("result")
                    .GetProperty("ok")
                    .GetBoolean());
            await committed.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Equal(1, Volatile.Read(ref commitCount));
            Assert.Equal(0, Volatile.Read(ref abortCount));

            pair.Client.Dispose();
            _ = await run.WaitAsync(TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task
            ResponseCompletionCommitFailureKeepsWrittenFrameAndLosesContinuity()
        {
            var ledger = new ActionIdempotencyLedger();
            int abortCount = 0;
            var postWriteFailureReported =
                new TaskCompletionSource<bool>(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var completion =
                new AgentRuntimeResponseCompletion(
                    beforeWrite: () => true,
                    afterWrite: () =>
                        throw new InvalidOperationException(
                            "synthetic_commit_failure"),
                    afterAbort: _ =>
                        Interlocked.Increment(ref abortCount),
                    afterPostWriteCommitFailure: () =>
                    {
                        ledger.MarkContinuityLost();
                        postWriteFailureReported
                            .TrySetResult(true);
                    });
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { ok = true },
                        responseCompletion: completion));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.SessionStatus,
                dispatcher);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_commit_failure_A",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(
                    AgentCapabilitiesV1.SessionStatus));
            _ = await ReadJsonAsync(pair.Client);
            await WriteRequestAsync(
                pair.Client,
                "status",
                AgentCapabilitiesV1.SessionStatus,
                new { });

            JsonElement response =
                await ReadJsonAsync(pair.Client);
            Assert.True(
                response.GetProperty("result")
                    .GetProperty("ok")
                    .GetBoolean());
            await postWriteFailureReported.Task
                .WaitAsync(TimeSpan.FromSeconds(5));
            Assert.Equal(
                ActionLookupKind.Unknown,
                ledger.Get(
                    "principal_commit_failure_A",
                    "session_commit_failure_A",
                    "unseen_after_commit_failure_A")
                    .Kind);
            Assert.Equal(0, Volatile.Read(ref abortCount));

            pair.Client.Dispose();
            _ = await run.WaitAsync(TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task ResponseCompletionAbortsWhenSuccessWriteFails()
        {
            int prepareCount = 0;
            int commitCount = 0;
            int abortBeforeWriteCount = 0;
            int abortAfterWriteStartedCount = 0;
            var aborted =
                new TaskCompletionSource<bool>(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var completion =
                new AgentRuntimeResponseCompletion(
                    delegate
                    {
                        Interlocked.Increment(ref prepareCount);
                        return true;
                    },
                    () => Interlocked.Increment(
                        ref commitCount),
                    writeStarted =>
                    {
                        if (writeStarted)
                        {
                            Interlocked.Increment(
                                ref abortAfterWriteStartedCount);
                        }
                        else
                        {
                            Interlocked.Increment(
                                ref abortBeforeWriteCount);
                        }
                        aborted.TrySetResult(true);
                    });
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { ok = true },
                        responseCompletion: completion));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.SessionStatus,
                dispatcher);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_flush_abort_AA",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(
                    AgentCapabilitiesV1.SessionStatus));
            _ = await ReadJsonAsync(pair.Client);
            pair.ServerWrites.FailNextWrite();
            await WriteRequestAsync(
                pair.Client,
                "status",
                AgentCapabilitiesV1.SessionStatus,
                new { });

            await aborted.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Equal(1, Volatile.Read(ref prepareCount));
            Assert.Equal(0, Volatile.Read(ref commitCount));
            Assert.Equal(
                0,
                Volatile.Read(ref abortBeforeWriteCount));
            Assert.Equal(
                1,
                Volatile.Read(ref abortAfterWriteStartedCount));

            pair.Client.Dispose();
            _ = await run.WaitAsync(TimeSpan.FromSeconds(5));
            Assert.Equal(
                0,
                Volatile.Read(ref abortBeforeWriteCount));
            Assert.Equal(
                1,
                Volatile.Read(ref abortAfterWriteStartedCount));
        }

        [Fact]
        public async Task
            FlushFailureAfterFrameWriteCannotRollBackDeliveredSuccess()
        {
            int commitCount = 0;
            int abortCount = 0;
            var committed =
                new TaskCompletionSource<bool>(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var completion =
                new AgentRuntimeResponseCompletion(
                    delegate
                    {
                        Interlocked.Increment(ref commitCount);
                        committed.TrySetResult(true);
                    },
                    () => Interlocked.Increment(
                        ref abortCount));
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { ok = true },
                        responseCompletion: completion));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.SessionStatus,
                dispatcher);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_flush_truth_A",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(
                    AgentCapabilitiesV1.SessionStatus));
            _ = await ReadJsonAsync(pair.Client);
            pair.ServerWrites.FailNextFlush();
            await WriteRequestAsync(
                pair.Client,
                "status",
                AgentCapabilitiesV1.SessionStatus,
                new { });

            JsonElement response =
                await ReadJsonAsync(pair.Client);
            Assert.True(
                response.GetProperty("result")
                    .GetProperty("ok")
                    .GetBoolean());
            await committed.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Equal(1, Volatile.Read(ref commitCount));
            Assert.Equal(0, Volatile.Read(ref abortCount));

            pair.Client.Dispose();
            _ = await run.WaitAsync(TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task ClientBinaryFrameBeforeHelloIsConnectionFatal()
        {
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.SessionStatus);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_CCCCCCCCCCCCC",
                    pair.Server,
                    CancellationToken.None);

            await Codec.WriteAsync(
                pair.Client,
                new AgentFrame(
                    1,
                    AgentFrameKind.BinaryChunk,
                    0,
                    new byte[] { 0, 0, 0, 0 }),
                CancellationToken.None);

            AgentConnectionTermination termination =
                await run.WaitAsync(TimeSpan.FromSeconds(5));
            Assert.Equal(
                AgentConnectionTerminationKind.ProtocolViolation,
                termination.Kind);
            Assert.Equal("malformed_frame", termination.ReasonCode);
            Assert.Equal(0, fixture.Tickets.ConsumptionCount);
            Assert.Null(fixture.Resources.RegisteredConnectionId);
        }

        [Fact]
        public async Task
            RevocationAfterFrameReadPreventsDispatcherInvocation()
        {
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { ok = true }));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.SessionStatus,
                dispatcher);
            using DuplexPair pair = DuplexPair.Create();
            using var authorizationReached =
                new ManualResetEventSlim(false);
            using var releaseAuthorization =
                new ManualResetEventSlim(false);
            fixture.Gateway
                .BeforeDispatchAuthorizationForTests =
                    delegate
                    {
                        authorizationReached.Set();
                        Assert.True(
                            releaseAuthorization.Wait(
                                TimeSpan.FromSeconds(5)));
                    };
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    "connection_DDDDDDDDDDDDD",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(
                    AgentCapabilitiesV1.SessionStatus));
            _ = await ReadJsonAsync(pair.Client);
            await WriteRequestAsync(
                pair.Client,
                "status",
                AgentCapabilitiesV1.SessionStatus,
                new { });
            Assert.True(
                authorizationReached.Wait(
                    TimeSpan.FromSeconds(5)));

            fixture.Resources.RevokeForTest(
                "developer_enrollment_rotated");
            releaseAuthorization.Set();

            AgentConnectionTermination termination =
                await run.WaitAsync(
                    TimeSpan.FromSeconds(5));
            Assert.Equal(
                AgentConnectionTerminationKind.Cancelled,
                termination.Kind);
            Assert.Equal(
                "developer_enrollment_rotated",
                termination.ReasonCode);
            Assert.Equal(
                0,
                dispatcher.InvocationCount);
        }

        private static readonly AgentFrameCodec Codec =
            new AgentFrameCodec(1);

        private static GatewayFixture CreateFixture(
            string capability,
            RecordingDispatcher dispatcher = null)
        {
            var clock = new ManualAgentRuntimeClock();
            PrincipalCredential principal =
                new PrincipalCredential(
                    "credential_AAAAAAAAAAAAA",
                    "principal_AAAAAAAAAAAAA",
                    "client_AAAAAAAAAAAAAAAAA",
                    AgentPrincipalKind.DeveloperAgent,
                    AgentSessionMode.DeveloperInteractive,
                    1,
                    0,
                    60_000,
                    clock.UtcNow,
                    new[]
                    {
                        capability,
                        "observe:pixels"
                    },
                    new[] { "target_AAAAAAAAAAAAAAAAA" },
                    "enrollment_AAAAAAAAAAAA",
                    null,
                    null,
                    null,
                    null);
            var tickets = new AcceptingTicketAuthority();
            var authentication =
                new StaticAuthenticationAuthority(
                    principal);
            var resources = new RecordingResourceAuthority();
            dispatcher ??= new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { ok = true }));
            var gateway = new AgentRuntimeGateway(
                tickets,
                authentication,
                resources,
                clock,
                new StaticMinimalSessionProvider(),
                dispatcher,
                "server_AAAAAAAAAAAAAAAAA");
            return new GatewayFixture(
                gateway,
                tickets,
                resources,
                dispatcher,
                clock);
        }

        private static object HelloParams(string capability)
        {
            return new
            {
                protocolVersion = AgentProtocolV1.Version,
                clientInstanceId =
                    "client_AAAAAAAAAAAAAAAAA",
                clientKind = "jsonl_cli",
                requestedCapabilities =
                    new[] { capability },
                nonce = "nonce_AAAAAAAAAAAAAAAAAA",
                connectionToken =
                    "ticket_AAAAAAAAAAAAAAAAA",
                credentialProof = "proof-value"
            };
        }

        private static object ClickParams(int deadlineMs)
        {
            return new
            {
                actionId = "action_DEADLINEAAAAAAAA",
                idempotencyKey =
                    "idempotency_DEADLINEAAA",
                deadlineMs,
                sessionId = "session_DEADLINEAAAAAA",
                observationGrantId =
                    "grant_DEADLINEAAAAAAAA",
                leaseId = "lease_DEADLINEAAAAAAAA",
                observationId =
                    "observation_DEADLINEAA",
                expectedLifecycleGeneration = 1,
                targetId = "target_AAAAAAAAAAAAAAAAA",
                expectedSurfaceEpoch = 1,
                expectedCoordinateSpaceVersion = 1,
                expectedFocusEpoch = 1,
                expectedModalEpoch = 1,
                operation = AgentCapabilitiesV1.Click,
                reason = "deadline boundary test",
                frameId = "frame_DEADLINEAAAAAAAA",
                arguments = new
                {
                    coordinateSpace = "observation_px",
                    x = 10,
                    y = 20,
                    button = "primary",
                    clickCount = 1
                }
            };
        }

        private static async Task WriteRequestAsync(
            Stream stream,
            string id,
            string method,
            object parameters)
        {
            byte[] payload = JsonSerializer.SerializeToUtf8Bytes(
                new
                {
                    jsonrpc = "2.0",
                    id,
                    method,
                    @params = parameters
                },
                AgentProtocolV1.JsonOptions);
            await Codec.WriteAsync(
                stream,
                new AgentFrame(
                    1,
                    AgentFrameKind.JsonRpc,
                    0,
                    payload),
                CancellationToken.None);
            await stream.FlushAsync();
        }

        private static async Task<JsonElement> ReadJsonAsync(
            Stream stream)
        {
            AgentFrame frame = await Codec.ReadAsync(
                stream,
                CancellationToken.None)
                .WaitAsync(TimeSpan.FromSeconds(5));
            Assert.NotNull(frame);
            Assert.Equal(AgentFrameKind.JsonRpc, frame.Kind);
            using JsonDocument document =
                JsonDocument.Parse(frame.Payload);
            return document.RootElement.Clone();
        }

        private static async Task
            AssertResponsePreparationFailureProducesNoSuccessFrameAsync(
                bool throwBeforeWrite)
        {
            int prepareCount = 0;
            int commitCount = 0;
            int abortBeforeWriteCount = 0;
            int abortAfterWriteStartedCount = 0;
            var aborted =
                new TaskCompletionSource<bool>(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var completion =
                new AgentRuntimeResponseCompletion(
                    delegate
                    {
                        Interlocked.Increment(ref prepareCount);
                        if (throwBeforeWrite)
                        {
                            throw new InvalidOperationException(
                                "synthetic_prepare_failure");
                        }
                        return false;
                    },
                    () => Interlocked.Increment(
                        ref commitCount),
                    writeStarted =>
                    {
                        if (writeStarted)
                        {
                            Interlocked.Increment(
                                ref abortAfterWriteStartedCount);
                        }
                        else
                        {
                            Interlocked.Increment(
                                ref abortBeforeWriteCount);
                        }
                        aborted.TrySetResult(true);
                    });
            var dispatcher = new RecordingDispatcher(
                (context, request) =>
                    AgentRuntimeDispatchResult.Completed(
                        new { ok = true },
                        responseCompletion: completion));
            GatewayFixture fixture = CreateFixture(
                AgentCapabilitiesV1.SessionStatus,
                dispatcher);
            using DuplexPair pair = DuplexPair.Create();
            Task<AgentConnectionTermination> run =
                fixture.Gateway.RunConnectionAsync(
                    throwBeforeWrite
                        ? "connection_prepare_throw_A"
                        : "connection_prepare_reject_A",
                    pair.Server,
                    CancellationToken.None);

            await WriteRequestAsync(
                pair.Client,
                "hello",
                AgentMethodsV1.RuntimeHello,
                HelloParams(
                    AgentCapabilitiesV1.SessionStatus));
            _ = await ReadJsonAsync(pair.Client);
            int writesAfterHello =
                pair.ServerWrites.WriteInvocationCount;

            await WriteRequestAsync(
                pair.Client,
                "status",
                AgentCapabilitiesV1.SessionStatus,
                new { });

            await aborted.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Equal(1, Volatile.Read(ref prepareCount));
            Assert.Equal(0, Volatile.Read(ref commitCount));
            Assert.Equal(
                1,
                Volatile.Read(ref abortBeforeWriteCount));
            Assert.Equal(
                0,
                Volatile.Read(ref abortAfterWriteStartedCount));
            Assert.Equal(
                writesAfterHello,
                pair.ServerWrites.WriteInvocationCount);

            pair.Client.Dispose();
            _ = await run.WaitAsync(TimeSpan.FromSeconds(5));
            Assert.Equal(
                1,
                Volatile.Read(ref abortBeforeWriteCount));
            Assert.Equal(
                0,
                Volatile.Read(ref abortAfterWriteStartedCount));
        }

        private sealed record GatewayFixture(
            AgentRuntimeGateway Gateway,
            AcceptingTicketAuthority Tickets,
            RecordingResourceAuthority Resources,
            RecordingDispatcher Dispatcher,
            ManualAgentRuntimeClock Clock);

        private sealed class AcceptingTicketAuthority
            : IAgentConnectionTicketAuthority
        {
            public int ConsumptionCount { get; private set; }

            public bool TryConsumeAndRotate(
                string presentedTicket,
                out string reasonCode)
            {
                ConsumptionCount++;
                reasonCode = "accepted";
                return true;
            }
        }

        private sealed class StaticAuthenticationAuthority
            : IAgentConnectionAuthenticationAuthority
        {
            private readonly PrincipalCredential _principal;

            public StaticAuthenticationAuthority(
                PrincipalCredential principal)
            {
                _principal = principal;
            }

            public AgentConnectionAuthenticationResult Authenticate(
                HelloMessage hello,
                AgentProcessSecurityIdentity peerIdentity)
            {
                return AgentConnectionAuthenticationResult
                    .Authenticated(
                        _principal,
                        hello.RequestedCapabilities);
            }
        }

        private sealed class RecordingResourceAuthority
            : IAgentConnectionResourceAuthority
        {
            public string RegisteredConnectionId { get; private set; }
            public string RevokedConnectionId { get; private set; }
            public PrincipalCredential RegisteredPrincipal
            {
                get;
                private set;
            }
            private Action<string> _terminateConnection;
            private int _active;

            public void RegisterConnection(
                string connectionId,
                PrincipalCredential principal,
                Action<string> terminateConnection)
            {
                RegisteredConnectionId = connectionId;
                RegisteredPrincipal = principal;
                _terminateConnection = terminateConnection;
                Volatile.Write(ref _active, 1);
            }

            public bool IsDispatchAuthorized(
                string connectionId,
                PrincipalCredential principal)
            {
                return Volatile.Read(ref _active) == 1
                    && string.Equals(
                        RegisteredConnectionId,
                        connectionId,
                        StringComparison.Ordinal)
                    && ReferenceEquals(
                        RegisteredPrincipal,
                        principal)
                    && principal.State
                        == CredentialState.Active;
            }

            public Task RevokeAsync(
                string connectionId,
                AgentConnectionTermination termination)
            {
                RevokedConnectionId = connectionId;
                Volatile.Write(ref _active, 0);
                return Task.CompletedTask;
            }

            public void RevokeForTest(string reasonCode)
            {
                Volatile.Write(ref _active, 0);
                RegisteredPrincipal.State =
                    CredentialState.Revoked;
                RegisteredPrincipal.RevokeReason =
                    reasonCode;
                _terminateConnection?.Invoke(
                    reasonCode);
            }
        }

        private sealed class StaticMinimalSessionProvider
            : IMinimalSessionReferenceProvider
        {
            public MinimalSessionReference GetMinimalReference()
            {
                return new MinimalSessionReference
                {
                    ProjectRunning = true,
                    QualificationState =
                        RuntimeQualificationState.Verified,
                    LifecycleRef =
                        "lifecycle_AAAAAAAAAAAAA"
                };
            }

            public bool TryResolveLifecycleReference(
                string lifecycleRef,
                out string sessionId,
                out ulong lifecycleGeneration)
            {
                sessionId = null;
                lifecycleGeneration = 0;
                return false;
            }
        }

        private sealed class RecordingDispatcher
            : IAgentRuntimeMethodDispatcher
        {
            private readonly Func<
                AgentRuntimeDispatchContext,
                AgentJsonRpcRequest,
                AgentRuntimeDispatchResult> _handler;
            private int _invocationCount;

            public int InvocationCount
            {
                get
                {
                    return Volatile.Read(
                        ref _invocationCount);
                }
            }

            public RecordingDispatcher(
                Func<
                    AgentRuntimeDispatchContext,
                    AgentJsonRpcRequest,
                    AgentRuntimeDispatchResult> handler)
            {
                _handler = handler;
            }

            public Task<AgentRuntimeDispatchResult> DispatchAsync(
                AgentRuntimeDispatchContext context,
                AgentJsonRpcRequest request,
                CancellationToken cancellationToken)
            {
                Interlocked.Increment(
                    ref _invocationCount);
                return Task.FromResult(
                    _handler(context, request));
            }
        }

        private sealed class DuplexPair : IDisposable
        {
            private readonly AnonymousPipeServerStream
                _clientToServerReader;
            private readonly AnonymousPipeClientStream
                _clientToServerWriter;
            private readonly AnonymousPipeServerStream
                _serverToClientWriter;
            private readonly AnonymousPipeClientStream
                _serverToClientReader;

            private DuplexPair(
                AnonymousPipeServerStream clientToServerReader,
                AnonymousPipeClientStream clientToServerWriter,
                AnonymousPipeServerStream serverToClientWriter,
                AnonymousPipeClientStream serverToClientReader,
                ControllableFlushStream serverWrites)
            {
                _clientToServerReader = clientToServerReader;
                _clientToServerWriter = clientToServerWriter;
                _serverToClientWriter = serverToClientWriter;
                _serverToClientReader = serverToClientReader;
                Server = new SplitDuplexStream(
                    _clientToServerReader,
                    serverWrites);
                Client = new SplitDuplexStream(
                    _serverToClientReader,
                    _clientToServerWriter);
                ServerWrites = serverWrites;
            }

            public Stream Server { get; }
            public Stream Client { get; }
            public ControllableFlushStream ServerWrites { get; }

            public static DuplexPair Create()
            {
                var clientToServerReader =
                    new AnonymousPipeServerStream(
                        PipeDirection.In,
                        HandleInheritability.None);
                var clientToServerWriter =
                    new AnonymousPipeClientStream(
                        PipeDirection.Out,
                        clientToServerReader
                            .GetClientHandleAsString());

                var serverToClientWriter =
                    new AnonymousPipeServerStream(
                        PipeDirection.Out,
                        HandleInheritability.None);
                var serverToClientReader =
                    new AnonymousPipeClientStream(
                        PipeDirection.In,
                        serverToClientWriter
                            .GetClientHandleAsString());
                var serverWrites =
                    new ControllableFlushStream(
                        serverToClientWriter);
                return new DuplexPair(
                    clientToServerReader,
                    clientToServerWriter,
                    serverToClientWriter,
                    serverToClientReader,
                    serverWrites);
            }

            public void Dispose()
            {
                Client.Dispose();
                Server.Dispose();
            }
        }

        private sealed class ControllableFlushStream : Stream
        {
            private readonly Stream _inner;
            private readonly
                TaskCompletionSource<bool> _flushEntered =
                    new(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
            private readonly
                TaskCompletionSource<bool> _flushRelease =
                    new(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
            private int _nextFlushMode;
            private readonly
                TaskCompletionSource<bool> _writeEntered =
                    new(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
            private readonly
                TaskCompletionSource<bool> _writeRelease =
                    new(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
            private int _writeInvocationCount;
            private int _nextWriteMode;
            private int _writesUntilNextMode;

            public ControllableFlushStream(Stream inner)
            {
                _inner = inner;
            }

            public Task FlushEntered => _flushEntered.Task;
            public Task WriteEntered => _writeEntered.Task;
            public int WriteInvocationCount =>
                Volatile.Read(ref _writeInvocationCount);
            public override bool CanRead => false;
            public override bool CanSeek => false;
            public override bool CanWrite => true;
            public override long Length =>
                throw new NotSupportedException();

            public override long Position
            {
                get => throw new NotSupportedException();
                set => throw new NotSupportedException();
            }

            public void BlockNextFlush()
            {
                Assert.Equal(
                    0,
                    Interlocked.CompareExchange(
                        ref _nextFlushMode,
                        1,
                        0));
            }

            public void FailNextFlush()
            {
                Assert.Equal(
                    0,
                    Interlocked.CompareExchange(
                        ref _nextFlushMode,
                        2,
                        0));
            }

            public void ReleaseBlockedFlush()
            {
                _flushRelease.TrySetResult(true);
            }

            public void BlockNextWrite()
            {
                ConfigureWriteMode(
                    mode: 1,
                    completeWritesBeforeMode: 0);
            }

            public void BlockWriteAfter(
                int completeWritesBeforeBlock)
            {
                ConfigureWriteMode(
                    mode: 1,
                    completeWritesBeforeBlock);
            }

            public void FailNextWrite()
            {
                ConfigureWriteMode(
                    mode: 2,
                    completeWritesBeforeMode: 0);
            }

            private void ConfigureWriteMode(
                int mode,
                int completeWritesBeforeMode)
            {
                Assert.True(
                    completeWritesBeforeMode >= 0);
                Volatile.Write(
                    ref _writesUntilNextMode,
                    checked(completeWritesBeforeMode + 1));
                Assert.Equal(
                    0,
                    Interlocked.CompareExchange(
                        ref _nextWriteMode,
                        mode,
                        0));
            }

            public void ReleaseBlockedWrite()
            {
                _writeRelease.TrySetResult(true);
            }

            public override void Flush()
            {
                _inner.Flush();
            }

            public override async Task FlushAsync(
                CancellationToken cancellationToken)
            {
                int mode = Interlocked.Exchange(
                    ref _nextFlushMode,
                    0);
                if (mode != 0)
                    _flushEntered.TrySetResult(true);
                if (mode == 1)
                {
                    await _flushRelease.Task.WaitAsync(
                        cancellationToken);
                }
                if (mode == 2)
                {
                    throw new IOException(
                        "synthetic_response_flush_failure");
                }
                await _inner.FlushAsync(cancellationToken);
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

            public override void Write(
                byte[] buffer,
                int offset,
                int count)
            {
                Interlocked.Increment(
                    ref _writeInvocationCount);
                _inner.Write(buffer, offset, count);
            }

            public override async ValueTask WriteAsync(
                ReadOnlyMemory<byte> buffer,
                CancellationToken cancellationToken = default)
            {
                Interlocked.Increment(
                    ref _writeInvocationCount);
                int mode = 0;
                if (Volatile.Read(ref _nextWriteMode) != 0
                    && Interlocked.Decrement(
                        ref _writesUntilNextMode) == 0)
                {
                    mode = Interlocked.Exchange(
                        ref _nextWriteMode,
                        0);
                }
                if (mode != 0)
                    _writeEntered.TrySetResult(true);
                if (mode == 1)
                {
                    await _writeRelease.Task.WaitAsync(
                        cancellationToken);
                }
                if (mode == 2)
                {
                    throw new IOException(
                        "synthetic_response_write_failure");
                }
                await _inner.WriteAsync(
                    buffer,
                    cancellationToken);
            }

            protected override void Dispose(bool disposing)
            {
                if (disposing)
                    _inner.Dispose();
                base.Dispose(disposing);
            }
        }

        private sealed class SplitDuplexStream : Stream
        {
            private readonly Stream _read;
            private readonly Stream _write;
            private int _disposed;

            public SplitDuplexStream(
                Stream read,
                Stream write)
            {
                _read = read;
                _write = write;
            }

            public override bool CanRead => true;
            public override bool CanSeek => false;
            public override bool CanWrite => true;
            public override long Length =>
                throw new NotSupportedException();

            public override long Position
            {
                get => throw new NotSupportedException();
                set => throw new NotSupportedException();
            }

            public override void Flush()
            {
                _write.Flush();
            }

            public override Task FlushAsync(
                CancellationToken cancellationToken)
            {
                return _write.FlushAsync(cancellationToken);
            }

            public override int Read(
                byte[] buffer,
                int offset,
                int count)
            {
                return _read.Read(buffer, offset, count);
            }

            public override ValueTask<int> ReadAsync(
                Memory<byte> buffer,
                CancellationToken cancellationToken = default)
            {
                return _read.ReadAsync(
                    buffer,
                    cancellationToken);
            }

            public override void Write(
                byte[] buffer,
                int offset,
                int count)
            {
                _write.Write(buffer, offset, count);
            }

            public override ValueTask WriteAsync(
                ReadOnlyMemory<byte> buffer,
                CancellationToken cancellationToken = default)
            {
                return _write.WriteAsync(
                    buffer,
                    cancellationToken);
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

            protected override void Dispose(bool disposing)
            {
                if (disposing
                    && Interlocked.Exchange(
                        ref _disposed,
                        1) == 0)
                {
                    _write.Dispose();
                    _read.Dispose();
                }
                base.Dispose(disposing);
            }
        }
    }
}
