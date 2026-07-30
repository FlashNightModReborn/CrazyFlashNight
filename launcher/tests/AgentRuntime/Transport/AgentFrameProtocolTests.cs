using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Transport;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Transport
{
    public sealed class AgentFrameProtocolTests
    {
        private readonly AgentFrameCodec _codec = new AgentFrameCodec(1);

        [Fact]
        public async Task JsonFrame_UsesFrozenTwelveByteHeader_AndRoundTrips()
        {
            byte[] json = Encoding.UTF8.GetBytes(
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session.list\"}");
            using var stream = new MemoryStream();

            await _codec.WriteAsync(
                stream,
                new AgentFrame(1, AgentFrameKind.JsonRpc, 0, json),
                CancellationToken.None);

            byte[] wire = stream.ToArray();
            Assert.Equal(AgentFrameCodec.HeaderLength + json.Length, wire.Length);
            Assert.Equal((byte)'C', wire[0]);
            Assert.Equal((byte)'F', wire[1]);
            Assert.Equal((byte)'7', wire[2]);
            Assert.Equal((byte)'A', wire[3]);
            Assert.Equal(1, wire[4]);
            Assert.Equal((byte)AgentFrameKind.JsonRpc, wire[5]);
            Assert.Equal(
                0,
                BinaryPrimitives.ReadUInt16LittleEndian(
                    wire.AsSpan(6, sizeof(ushort))));
            Assert.Equal(
                json.Length,
                BinaryPrimitives.ReadInt32LittleEndian(
                    wire.AsSpan(8, sizeof(int))));

            stream.Position = 0;
            AgentFrame decoded =
                await _codec.ReadAsync(stream, CancellationToken.None);
            Assert.Equal(AgentFrameKind.JsonRpc, decoded.Kind);
            Assert.Equal(json, decoded.Payload.ToArray());
            Assert.Null(
                await _codec.ReadAsync(stream, CancellationToken.None));
        }

        [Fact]
        public async Task BinaryFrame_AcceptsFrozenMaximumChunk()
        {
            byte[] payload = new byte[AgentFrameCodec.MaxBinaryChunkLength];
            payload[0] = 0x7a;
            payload[payload.Length - 1] = 0x5c;
            using var stream = new MemoryStream();

            await _codec.WriteAsync(
                stream,
                new AgentFrame(1, AgentFrameKind.BinaryChunk, 0, payload),
                CancellationToken.None);
            stream.Position = 0;
            AgentFrame decoded =
                await _codec.ReadAsync(stream, CancellationToken.None);

            Assert.Equal(payload.Length, decoded.Payload.Length);
            Assert.Equal(0x7a, decoded.Payload.Span[0]);
            Assert.Equal(0x5c, decoded.Payload.Span[payload.Length - 1]);
        }

        [Theory]
        [InlineData(0, (int)AgentFrameProtocolError.InvalidMagic)]
        [InlineData(4, (int)AgentFrameProtocolError.UnsupportedProtocolVersion)]
        [InlineData(5, (int)AgentFrameProtocolError.UnsupportedKind)]
        [InlineData(6, (int)AgentFrameProtocolError.UnsupportedFlags)]
        public async Task HeaderContractViolation_IsConnectionFatal(
            int mutatedOffset,
            int expectedError)
        {
            byte[] wire = CreateRawFrame(
                AgentFrameKind.JsonRpc,
                Encoding.UTF8.GetBytes("{}"));
            wire[mutatedOffset] = mutatedOffset switch
            {
                0 => (byte)'X',
                4 => (byte)2,
                5 => (byte)99,
                6 => (byte)1,
                _ => throw new InvalidOperationException()
            };

            AgentFrameProtocolException error =
                await Assert.ThrowsAsync<AgentFrameProtocolException>(
                    () => _codec.ReadAsync(
                        new MemoryStream(wire),
                        CancellationToken.None));

            Assert.Equal((AgentFrameProtocolError)expectedError, error.Error);
        }

        [Fact]
        public async Task OversizeLength_IsRejectedBeforePayloadAllocationOrRead()
        {
            byte[] header = CreateRawHeader(
                AgentFrameKind.JsonRpc,
                AgentFrameCodec.MaxJsonPayloadLength + 1);
            var stream = new CountingMemoryStream(header);

            AgentFrameProtocolException error =
                await Assert.ThrowsAsync<AgentFrameProtocolException>(
                    () => _codec.ReadAsync(
                        stream,
                        CancellationToken.None));

            Assert.Equal(AgentFrameProtocolError.PayloadTooLarge, error.Error);
            Assert.Equal(AgentFrameCodec.HeaderLength, stream.BytesRead);
        }

        [Theory]
        [InlineData(1)]
        [InlineData(11)]
        public async Task PartialHeader_IsRejected(int length)
        {
            byte[] partial = CreateRawHeader(AgentFrameKind.JsonRpc, 0);
            Array.Resize(ref partial, length);

            AgentFrameProtocolException error =
                await Assert.ThrowsAsync<AgentFrameProtocolException>(
                    () => _codec.ReadAsync(
                        new MemoryStream(partial),
                        CancellationToken.None));

            Assert.Equal(
                AgentFrameProtocolError.TruncatedHeader,
                error.Error);
        }

        [Fact]
        public async Task PartialPayload_IsRejected()
        {
            byte[] wire = CreateRawFrame(
                AgentFrameKind.BinaryChunk,
                new byte[] { 1, 2 });
            BinaryPrimitives.WriteUInt32LittleEndian(
                wire.AsSpan(8, sizeof(uint)),
                3);

            AgentFrameProtocolException error =
                await Assert.ThrowsAsync<AgentFrameProtocolException>(
                    () => _codec.ReadAsync(
                        new MemoryStream(wire),
                        CancellationToken.None));

            Assert.Equal(AgentFrameProtocolError.TruncatedPayload, error.Error);
        }

        [Fact]
        public async Task InvalidUtf8Json_IsRejected()
        {
            byte[] wire = CreateRawFrame(
                AgentFrameKind.JsonRpc,
                new byte[] { (byte)'{', (byte)'"', 0xff, (byte)'"', (byte)'}' });

            AgentFrameProtocolException error =
                await Assert.ThrowsAsync<AgentFrameProtocolException>(
                    () => _codec.ReadAsync(
                        new MemoryStream(wire),
                        CancellationToken.None));

            Assert.Equal(AgentFrameProtocolError.InvalidUtf8, error.Error);
        }

        [Theory]
        [InlineData("{")]
        [InlineData("{} trailing")]
        [InlineData("{\"a\":1,}")]
        [InlineData("/*comment*/{}")]
        public async Task InvalidJson_IsRejected(string invalidJson)
        {
            byte[] wire = CreateRawFrame(
                AgentFrameKind.JsonRpc,
                Encoding.UTF8.GetBytes(invalidJson));

            AgentFrameProtocolException error =
                await Assert.ThrowsAsync<AgentFrameProtocolException>(
                    () => _codec.ReadAsync(
                        new MemoryStream(wire),
                        CancellationToken.None));

            Assert.Equal(AgentFrameProtocolError.InvalidJson, error.Error);
        }

        [Fact]
        public async Task FramePump_ClosesOnlyOffendingConnection_AndRevokesState()
        {
            var revocations = new RecordingRevocationSink();
            var pump = new AgentConnectionFramePump(_codec, revocations);
            var malformed = new TrackingMemoryStream(
                CreateRawFrame(
                    AgentFrameKind.JsonRpc,
                    Encoding.UTF8.GetBytes("{")));
            int malformedDispatches = 0;

            AgentConnectionTermination first = await pump.RunAsync(
                "connection-a",
                malformed,
                delegate(AgentFrame frame, CancellationToken token)
                {
                    malformedDispatches++;
                    return Task.CompletedTask;
                },
                CancellationToken.None);

            Assert.Equal(
                AgentConnectionTerminationKind.ProtocolViolation,
                first.Kind);
            Assert.Equal("malformed_frame", first.ReasonCode);
            Assert.True(first.RevokeLeaseAndHeldInput);
            Assert.Equal(0, malformedDispatches);
            Assert.True(malformed.Disposed);

            byte[] goodWire = CreateRawFrame(
                AgentFrameKind.JsonRpc,
                Encoding.UTF8.GetBytes("{}"));
            var good = new TrackingMemoryStream(goodWire);
            int goodDispatches = 0;
            AgentConnectionTermination second = await pump.RunAsync(
                "connection-b",
                good,
                delegate(AgentFrame frame, CancellationToken token)
                {
                    goodDispatches++;
                    return Task.CompletedTask;
                },
                CancellationToken.None);

            Assert.Equal(
                AgentConnectionTerminationKind.CleanDisconnect,
                second.Kind);
            Assert.Equal(1, goodDispatches);
            Assert.True(good.Disposed);
            Assert.Equal(
                new[] { "connection-a", "connection-b" },
                revocations.ConnectionIds);
        }

        [Fact]
        public async Task HandlerFailure_IsContainedToConnection()
        {
            var revocations = new RecordingRevocationSink();
            var pump = new AgentConnectionFramePump(_codec, revocations);
            using var stream = new MemoryStream(
                CreateRawFrame(
                    AgentFrameKind.JsonRpc,
                    Encoding.UTF8.GetBytes("{}")));

            AgentConnectionTermination result = await pump.RunAsync(
                "connection-handler-failure",
                stream,
                delegate(AgentFrame frame, CancellationToken token)
                {
                    throw new InvalidOperationException("handler failed");
                },
                CancellationToken.None);

            Assert.Equal(
                AgentConnectionTerminationKind.HandlerFailure,
                result.Kind);
            Assert.Equal("connection_handler_failed", result.ReasonCode);
            Assert.Single(revocations.ConnectionIds);
        }

        private static byte[] CreateRawHeader(
            AgentFrameKind kind,
            int payloadLength)
        {
            byte[] header = new byte[AgentFrameCodec.HeaderLength];
            header[0] = (byte)'C';
            header[1] = (byte)'F';
            header[2] = (byte)'7';
            header[3] = (byte)'A';
            header[4] = 1;
            header[5] = (byte)kind;
            BinaryPrimitives.WriteUInt16LittleEndian(
                header.AsSpan(6, sizeof(ushort)),
                0);
            BinaryPrimitives.WriteUInt32LittleEndian(
                header.AsSpan(8, sizeof(uint)),
                checked((uint)payloadLength));
            return header;
        }

        private static byte[] CreateRawFrame(
            AgentFrameKind kind,
            byte[] payload)
        {
            byte[] wire = new byte[
                AgentFrameCodec.HeaderLength + payload.Length];
            CreateRawHeader(kind, payload.Length).CopyTo(wire, 0);
            payload.CopyTo(wire, AgentFrameCodec.HeaderLength);
            return wire;
        }

        private sealed class RecordingRevocationSink
            : IAgentConnectionRevocationSink
        {
            public List<string> ConnectionIds { get; } = new List<string>();

            public Task RevokeAsync(
                string connectionId,
                AgentConnectionTermination termination)
            {
                ConnectionIds.Add(connectionId);
                return Task.CompletedTask;
            }
        }

        private sealed class TrackingMemoryStream : MemoryStream
        {
            public bool Disposed { get; private set; }

            public TrackingMemoryStream(byte[] bytes)
                : base(bytes)
            {
            }

            protected override void Dispose(bool disposing)
            {
                Disposed = true;
                base.Dispose(disposing);
            }
        }

        private sealed class CountingMemoryStream : MemoryStream
        {
            public int BytesRead { get; private set; }

            public CountingMemoryStream(byte[] bytes)
                : base(bytes)
            {
            }

            public override ValueTask<int> ReadAsync(
                Memory<byte> buffer,
                CancellationToken cancellationToken = default)
            {
                ValueTask<int> read = base.ReadAsync(buffer, cancellationToken);
                if (read.IsCompletedSuccessfully)
                {
                    BytesRead += read.Result;
                    return new ValueTask<int>(read.Result);
                }
                return CountAsync(read);
            }

            private async ValueTask<int> CountAsync(ValueTask<int> pending)
            {
                int count = await pending;
                BytesRead += count;
                return count;
            }
        }
    }
}
