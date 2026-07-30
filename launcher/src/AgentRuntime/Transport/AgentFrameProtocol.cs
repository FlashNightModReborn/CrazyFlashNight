using System;
using System.Buffers.Binary;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace CF7Launcher.AgentRuntime.Transport
{
    internal enum AgentFrameKind : byte
    {
        JsonRpc = 1,
        BinaryChunk = 2
    }

    internal enum AgentFrameProtocolError
    {
        TruncatedHeader,
        InvalidMagic,
        UnsupportedProtocolVersion,
        UnsupportedKind,
        UnsupportedFlags,
        PayloadTooLarge,
        TruncatedPayload,
        InvalidUtf8,
        InvalidJson
    }

    internal sealed class AgentFrameProtocolException : IOException
    {
        public AgentFrameProtocolError Error { get; private set; }

        public AgentFrameProtocolException(
            AgentFrameProtocolError error,
            string message)
            : base(message)
        {
            Error = error;
        }

        public AgentFrameProtocolException(
            AgentFrameProtocolError error,
            string message,
            Exception innerException)
            : base(message, innerException)
        {
            Error = error;
        }
    }

    internal sealed class AgentFrame
    {
        private readonly byte[] _payload;

        public byte ProtocolMajor { get; private set; }
        public AgentFrameKind Kind { get; private set; }
        public ushort Flags { get; private set; }
        public ReadOnlyMemory<byte> Payload { get { return _payload; } }

        public AgentFrame(
            byte protocolMajor,
            AgentFrameKind kind,
            ushort flags,
            ReadOnlySpan<byte> payload)
        {
            ProtocolMajor = protocolMajor;
            Kind = kind;
            Flags = flags;
            _payload = payload.ToArray();
        }
    }

    /// <summary>
    /// Bounded CF7A byte-stream framing. Framing errors are connection-fatal:
    /// callers must not attempt to resynchronize a damaged stream.
    /// </summary>
    internal sealed class AgentFrameCodec
    {
        internal const int HeaderLength = 12;
        internal const int MaxJsonPayloadLength = 1024 * 1024;
        internal const int MaxBinaryChunkLength = 4 * 1024 * 1024;
        internal const ushort SupportedFlags = 0;

        private static readonly byte[] Magic =
            new byte[] { (byte)'C', (byte)'F', (byte)'7', (byte)'A' };
        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);

        private readonly byte _protocolMajor;

        public AgentFrameCodec(byte protocolMajor)
        {
            if (protocolMajor == 0)
                throw new ArgumentOutOfRangeException(
                    nameof(protocolMajor),
                    "Protocol major zero is reserved.");
            _protocolMajor = protocolMajor;
        }

        public async Task<AgentFrame> ReadAsync(
            Stream stream,
            CancellationToken cancellationToken)
        {
            if (stream == null) throw new ArgumentNullException(nameof(stream));
            if (!stream.CanRead)
                throw new ArgumentException("The stream must be readable.", nameof(stream));

            byte[] header = new byte[HeaderLength];
            int firstByteCount = await stream.ReadAsync(
                header.AsMemory(0, 1),
                cancellationToken).ConfigureAwait(false);
            if (firstByteCount == 0) return null;

            await ReadExactlyOrProtocolFailureAsync(
                stream,
                header,
                1,
                HeaderLength - 1,
                AgentFrameProtocolError.TruncatedHeader,
                cancellationToken).ConfigureAwait(false);

            ValidateMagic(header);

            byte protocolMajor = header[4];
            if (protocolMajor != _protocolMajor)
            {
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.UnsupportedProtocolVersion,
                    "The CF7A protocol major is not supported.");
            }

            AgentFrameKind kind = ParseKind(header[5]);
            ushort flags = BinaryPrimitives.ReadUInt16LittleEndian(
                header.AsSpan(6, sizeof(ushort)));
            if (flags != SupportedFlags)
            {
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.UnsupportedFlags,
                    "The CF7A frame contains unsupported flags.");
            }

            uint declaredLength = BinaryPrimitives.ReadUInt32LittleEndian(
                header.AsSpan(8, sizeof(uint)));
            int maximumLength = GetMaximumPayloadLength(kind);
            if (declaredLength > maximumLength)
            {
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.PayloadTooLarge,
                    "The CF7A payload exceeds the bound for its frame kind.");
            }

            int payloadLength = checked((int)declaredLength);
            byte[] payload = new byte[payloadLength];
            if (payloadLength != 0)
            {
                await ReadExactlyOrProtocolFailureAsync(
                    stream,
                    payload,
                    0,
                    payloadLength,
                    AgentFrameProtocolError.TruncatedPayload,
                    cancellationToken).ConfigureAwait(false);
            }

            if (kind == AgentFrameKind.JsonRpc)
                ValidateJson(payload);

            return new AgentFrame(protocolMajor, kind, flags, payload);
        }

        public async Task WriteAsync(
            Stream stream,
            AgentFrame frame,
            CancellationToken cancellationToken)
        {
            if (stream == null) throw new ArgumentNullException(nameof(stream));
            if (frame == null) throw new ArgumentNullException(nameof(frame));
            if (!stream.CanWrite)
                throw new ArgumentException("The stream must be writable.", nameof(stream));
            if (frame.ProtocolMajor != _protocolMajor)
            {
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.UnsupportedProtocolVersion,
                    "The CF7A protocol major is not supported.");
            }

            ValidateKind(frame.Kind);
            if (frame.Flags != SupportedFlags)
            {
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.UnsupportedFlags,
                    "The CF7A frame contains unsupported flags.");
            }

            int payloadLength = frame.Payload.Length;
            if (payloadLength > GetMaximumPayloadLength(frame.Kind))
            {
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.PayloadTooLarge,
                    "The CF7A payload exceeds the bound for its frame kind.");
            }
            if (frame.Kind == AgentFrameKind.JsonRpc)
                ValidateJson(frame.Payload.Span);

            byte[] header = new byte[HeaderLength];
            Magic.CopyTo(header, 0);
            header[4] = frame.ProtocolMajor;
            header[5] = (byte)frame.Kind;
            BinaryPrimitives.WriteUInt16LittleEndian(
                header.AsSpan(6, sizeof(ushort)),
                frame.Flags);
            BinaryPrimitives.WriteUInt32LittleEndian(
                header.AsSpan(8, sizeof(uint)),
                checked((uint)payloadLength));

            await stream.WriteAsync(header, cancellationToken).ConfigureAwait(false);
            if (payloadLength != 0)
            {
                await stream.WriteAsync(
                    frame.Payload,
                    cancellationToken).ConfigureAwait(false);
            }
        }

        private static void ValidateMagic(byte[] header)
        {
            for (int index = 0; index < Magic.Length; index++)
            {
                if (header[index] == Magic[index]) continue;
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.InvalidMagic,
                    "The CF7A frame magic is invalid.");
            }
        }

        private static AgentFrameKind ParseKind(byte value)
        {
            AgentFrameKind kind = (AgentFrameKind)value;
            ValidateKind(kind);
            return kind;
        }

        private static void ValidateKind(AgentFrameKind kind)
        {
            if (kind == AgentFrameKind.JsonRpc
                || kind == AgentFrameKind.BinaryChunk)
                return;

            throw new AgentFrameProtocolException(
                AgentFrameProtocolError.UnsupportedKind,
                "The CF7A frame kind is not supported.");
        }

        private static int GetMaximumPayloadLength(AgentFrameKind kind)
        {
            ValidateKind(kind);
            return kind == AgentFrameKind.JsonRpc
                ? MaxJsonPayloadLength
                : MaxBinaryChunkLength;
        }

        private static void ValidateJson(ReadOnlySpan<byte> payload)
        {
            try
            {
                StrictUtf8.GetCharCount(payload);
            }
            catch (DecoderFallbackException exception)
            {
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.InvalidUtf8,
                    "The JSON frame is not strict UTF-8.",
                    exception);
            }

            try
            {
                using JsonDocument document = JsonDocument.Parse(
                    payload.ToArray(),
                    new JsonDocumentOptions
                    {
                        AllowTrailingCommas = false,
                        CommentHandling = JsonCommentHandling.Disallow,
                        MaxDepth = 128
                    });
            }
            catch (JsonException exception)
            {
                throw new AgentFrameProtocolException(
                    AgentFrameProtocolError.InvalidJson,
                    "The JSON frame does not contain a complete JSON value.",
                    exception);
            }
        }

        private static async Task ReadExactlyOrProtocolFailureAsync(
            Stream stream,
            byte[] buffer,
            int offset,
            int count,
            AgentFrameProtocolError error,
            CancellationToken cancellationToken)
        {
            int consumed = 0;
            while (consumed < count)
            {
                int read = await stream.ReadAsync(
                    buffer.AsMemory(offset + consumed, count - consumed),
                    cancellationToken).ConfigureAwait(false);
                if (read == 0)
                {
                    throw new AgentFrameProtocolException(
                        error,
                        error == AgentFrameProtocolError.TruncatedHeader
                            ? "The CF7A header ended before 12 bytes."
                            : "The CF7A payload ended before its declared length.");
                }
                consumed += read;
            }
        }
    }

    internal enum AgentConnectionTerminationKind
    {
        CleanDisconnect,
        ProtocolViolation,
        TransportFailure,
        HandlerFailure,
        Cancelled
    }

    internal sealed class AgentConnectionTermination
    {
        public AgentConnectionTerminationKind Kind { get; private set; }
        public string ReasonCode { get; private set; }
        public AgentFrameProtocolError? ProtocolError { get; private set; }
        public bool RevokeLeaseAndHeldInput { get { return true; } }

        internal AgentConnectionTermination(
            AgentConnectionTerminationKind kind,
            string reasonCode,
            AgentFrameProtocolError? protocolError)
        {
            Kind = kind;
            ReasonCode = reasonCode;
            ProtocolError = protocolError;
        }
    }

    internal interface IAgentConnectionRevocationSink
    {
        Task RevokeAsync(
            string connectionId,
            AgentConnectionTermination termination);
    }

    internal sealed class AgentConnectionFramePump
    {
        private readonly AgentFrameCodec _codec;
        private readonly IAgentConnectionRevocationSink _revocationSink;

        public AgentConnectionFramePump(
            AgentFrameCodec codec,
            IAgentConnectionRevocationSink revocationSink)
        {
            _codec = codec ?? throw new ArgumentNullException(nameof(codec));
            _revocationSink = revocationSink
                ?? throw new ArgumentNullException(nameof(revocationSink));
        }

        public async Task<AgentConnectionTermination> RunAsync(
            string connectionId,
            Stream stream,
            Func<AgentFrame, CancellationToken, Task> frameHandler,
            CancellationToken cancellationToken)
        {
            if (string.IsNullOrWhiteSpace(connectionId))
                throw new ArgumentException(
                    "A connection id is required.",
                    nameof(connectionId));
            if (stream == null) throw new ArgumentNullException(nameof(stream));
            if (frameHandler == null)
                throw new ArgumentNullException(nameof(frameHandler));

            AgentConnectionTermination termination;
            bool dispatching = false;
            try
            {
                while (true)
                {
                    AgentFrame frame = await _codec.ReadAsync(
                        stream,
                        cancellationToken).ConfigureAwait(false);
                    if (frame == null)
                    {
                        termination = new AgentConnectionTermination(
                            AgentConnectionTerminationKind.CleanDisconnect,
                            "connection_closed",
                            null);
                        break;
                    }

                    dispatching = true;
                    await frameHandler(frame, cancellationToken).ConfigureAwait(false);
                    dispatching = false;
                }
            }
            catch (AgentFrameProtocolException exception)
            {
                termination = new AgentConnectionTermination(
                    AgentConnectionTerminationKind.ProtocolViolation,
                    "malformed_frame",
                    exception.Error);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                termination = new AgentConnectionTermination(
                    AgentConnectionTerminationKind.Cancelled,
                    "connection_cancelled",
                    null);
            }
            catch (Exception)
            {
                termination = new AgentConnectionTermination(
                    dispatching
                        ? AgentConnectionTerminationKind.HandlerFailure
                        : AgentConnectionTerminationKind.TransportFailure,
                    dispatching
                        ? "connection_handler_failed"
                        : "connection_transport_failed",
                    null);
            }
            try
            {
                stream.Dispose();
            }
            catch
            {
                // A broken transport must not prevent the mandatory
                // connection-state revocation below.
            }

            // Cleanup is deliberately independent from the connection cancellation
            // token: disconnect/corruption must still revoke leases and owned input.
            await _revocationSink.RevokeAsync(
                connectionId,
                termination).ConfigureAwait(false);
            return termination;
        }
    }
}
