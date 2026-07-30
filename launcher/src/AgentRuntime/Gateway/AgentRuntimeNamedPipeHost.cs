using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Gateway
{
    internal interface IAgentRuntimeConnectionRunner
    {
        Task<AgentConnectionTermination> RunConnectionAsync(
            string connectionId,
            Stream stream,
            AgentProcessSecurityIdentity peerIdentity,
            CancellationToken cancellationToken);
    }

    internal sealed class AgentRuntimeGatewayConnectionRunner
        : IAgentRuntimeConnectionRunner
    {
        private readonly AgentRuntimeGateway _gateway;

        public AgentRuntimeGatewayConnectionRunner(
            AgentRuntimeGateway gateway)
        {
            _gateway = gateway
                ?? throw new ArgumentNullException(nameof(gateway));
        }

        public Task<AgentConnectionTermination> RunConnectionAsync(
            string connectionId,
            Stream stream,
            AgentProcessSecurityIdentity peerIdentity,
            CancellationToken cancellationToken)
        {
            return _gateway.RunConnectionAsync(
                connectionId,
                stream,
                peerIdentity,
                cancellationToken);
        }
    }

    /// <summary>
    /// Owns the local-only named-pipe accept loop. Every accepted stream has
    /// passed the OS peer verifier before it can reach the protocol gateway.
    /// Individual connection failures are contained to that connection.
    /// </summary>
    internal sealed class AgentRuntimeNamedPipeHost : IAsyncDisposable
    {
        private const int ConnectionIdEntropyBytes = 16;

        private readonly object _gate = new object();
        private readonly string _pipeId;
        private readonly AgentNamedPipeServerFactory _serverFactory;
        private readonly IAgentPipePeerVerifier _peerVerifier;
        private readonly IAgentRuntimeConnectionRunner _connectionRunner;
        private readonly CancellationTokenSource _stop =
            new CancellationTokenSource();
        private readonly HashSet<Task> _activeConnections =
            new HashSet<Task>();

        private AgentPendingPipeServer _pendingServer;
        private Task _runTask;
        private int _runStarted;
        private int _disposeStarted;

        public string PipeName
        {
            get
            {
                return AgentNamedPipeServerFactory.PipeNamePrefix
                    + _pipeId;
            }
        }

        public AgentRuntimeNamedPipeHost(
            string pipeId,
            AgentRuntimeGateway gateway)
            : this(
                pipeId,
                new AgentRuntimeGatewayConnectionRunner(gateway))
        {
        }

        public AgentRuntimeNamedPipeHost(
            string pipeId,
            IAgentRuntimeConnectionRunner connectionRunner)
            : this(
                pipeId,
                new AgentNamedPipeServerFactory(),
                CreateProductionPeerVerifier(),
                connectionRunner)
        {
        }

        internal AgentRuntimeNamedPipeHost(
            string pipeId,
            AgentNamedPipeServerFactory serverFactory,
            IAgentPipePeerVerifier peerVerifier,
            IAgentRuntimeConnectionRunner connectionRunner)
        {
            AgentNamedPipeServerFactory.ValidateOpaquePipeId(pipeId);
            _pipeId = pipeId;
            _serverFactory = serverFactory
                ?? throw new ArgumentNullException(nameof(serverFactory));
            _peerVerifier = peerVerifier
                ?? throw new ArgumentNullException(nameof(peerVerifier));
            _connectionRunner = connectionRunner
                ?? throw new ArgumentNullException(nameof(connectionRunner));
        }

        /// <summary>
        /// Creates the first OS pipe instance before rendezvous publication.
        /// A client may connect and wait as soon as the rendezvous file becomes
        /// visible, while RunAsync remains the sole owner of verification and
        /// protocol dispatch.
        /// </summary>
        public void Prepare()
        {
            lock (_gate)
            {
                if (Volatile.Read(ref _disposeStarted) != 0)
                    throw new ObjectDisposedException(
                        nameof(AgentRuntimeNamedPipeHost));
                if (Volatile.Read(ref _runStarted) != 0)
                    throw new InvalidOperationException(
                        "The named-pipe host must be prepared before it is run.");
                if (_pendingServer != null)
                    return;
                _pendingServer = _serverFactory.Create(_pipeId);
            }
        }

        public Task RunAsync(CancellationToken cancellationToken)
        {
            lock (_gate)
            {
                if (Volatile.Read(ref _disposeStarted) != 0)
                    throw new ObjectDisposedException(
                        nameof(AgentRuntimeNamedPipeHost));
                if (Interlocked.Exchange(ref _runStarted, 1) != 0)
                    throw new InvalidOperationException(
                        "The named-pipe host can only be run once.");

                _runTask = RunCoreAsync(cancellationToken);
                return _runTask;
            }
        }

        public async ValueTask DisposeAsync()
        {
            Interlocked.Exchange(ref _disposeStarted, 1);
            CancelWithoutEscaping(_stop);

            AgentPendingPipeServer pending;
            Task runTask;
            lock (_gate)
            {
                pending = _pendingServer;
                runTask = _runTask;
            }

            // Disposing the current server is the deterministic escape hatch
            // for a WaitForConnectionAsync that is pending in the OS.
            try
            {
                pending?.Dispose();
            }
            catch (Exception)
            {
                // Continue into the run/connection drain even if an OS stream
                // reports an error while the pending accept is interrupted.
            }

            if (runTask != null)
            {
                try
                {
                    await runTask.ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                    when (_stop.IsCancellationRequested)
                {
                    // Host shutdown is a normal terminal state.
                }
            }
        }

        private async Task RunCoreAsync(
            CancellationToken cancellationToken)
        {
            // Keep constructor/RunAsync validation synchronous while avoiding
            // running the accept loop under the lifecycle lock.
            await Task.Yield();

            using var lifetime =
                CancellationTokenSource.CreateLinkedTokenSource(
                    cancellationToken,
                    _stop.Token);
            CancellationToken token = lifetime.Token;

            try
            {
                while (!token.IsCancellationRequested)
                {
                    AgentPendingPipeServer pending;
                    lock (_gate)
                    {
                        pending = _pendingServer;
                    }
                    if (pending == null)
                    {
                        pending = _serverFactory.Create(_pipeId);
                        lock (_gate)
                        {
                            if (token.IsCancellationRequested)
                            {
                                pending.Dispose();
                                break;
                            }
                            _pendingServer = pending;
                        }
                    }

                    AgentVerifiedPipeConnection connection = null;
                    try
                    {
                        connection = await pending.AcceptVerifiedAsync(
                            _peerVerifier,
                            token).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException)
                        when (token.IsCancellationRequested)
                    {
                        break;
                    }
                    catch (ObjectDisposedException)
                        when (token.IsCancellationRequested)
                    {
                        break;
                    }
                    catch (Exception)
                    {
                        // Verification and per-instance transport failures are
                        // fail-closed. Recreate a fresh server for the same
                        // opaque pipe id; never expose the rejected stream.
                        if (token.IsCancellationRequested)
                            break;
                        continue;
                    }
                    finally
                    {
                        lock (_gate)
                        {
                            if (ReferenceEquals(_pendingServer, pending))
                                _pendingServer = null;
                        }
                        await pending.DisposeAsync().ConfigureAwait(false);
                    }

                    StartVerifiedConnection(connection, token);
                }
            }
            finally
            {
                // External cancellation stops both the accept loop and every
                // already accepted gateway connection.
                CancelWithoutEscaping(lifetime);
                await WaitForActiveConnectionsAsync().ConfigureAwait(false);
            }
        }

        private void StartVerifiedConnection(
            AgentVerifiedPipeConnection connection,
            CancellationToken cancellationToken)
        {
            if (connection == null)
                throw new ArgumentNullException(nameof(connection));

            string connectionId = CreateOpaqueConnectionId();
            Task task = RunVerifiedConnectionIsolatedAsync(
                connection,
                connectionId,
                cancellationToken);

            lock (_gate)
            {
                _activeConnections.Add(task);
            }
            _ = task.ContinueWith(
                completed => RemoveActiveConnection(completed),
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }

        private async Task RunVerifiedConnectionIsolatedAsync(
            AgentVerifiedPipeConnection connection,
            string connectionId,
            CancellationToken cancellationToken)
        {
            try
            {
                await using (connection.ConfigureAwait(false))
                {
                    await _connectionRunner.RunConnectionAsync(
                        connectionId,
                        connection.Stream,
                        connection.PeerIdentity,
                        cancellationToken).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
                when (cancellationToken.IsCancellationRequested)
            {
                // Normal host shutdown for this connection.
            }
            catch (Exception)
            {
                // A malformed, disconnected, or faulty client is isolated.
                // The accept loop remains live for the next verified peer.
            }
        }

        private void RemoveActiveConnection(Task task)
        {
            lock (_gate)
            {
                _activeConnections.Remove(task);
            }
        }

        private async Task WaitForActiveConnectionsAsync()
        {
            while (true)
            {
                Task[] snapshot;
                lock (_gate)
                {
                    if (_activeConnections.Count == 0)
                        return;
                    snapshot = new Task[_activeConnections.Count];
                    _activeConnections.CopyTo(snapshot);
                }
                await Task.WhenAll(snapshot).ConfigureAwait(false);
            }
        }

        private static IAgentPipePeerVerifier
            CreateProductionPeerVerifier()
        {
            if (!WindowsAgentPipePeerProbe.TryGetCurrentProcessIdentity(
                    out AgentProcessSecurityIdentity serverIdentity))
            {
                throw new InvalidOperationException(
                    "The Launcher process security identity could not be "
                    + "verified for the Agent Runtime pipe.");
            }

            return new AgentPipePeerVerifier(
                new WindowsAgentPipePeerProbe(),
                serverIdentity);
        }

        private static string CreateOpaqueConnectionId()
        {
            byte[] entropy =
                RandomNumberGenerator.GetBytes(
                    ConnectionIdEntropyBytes);
            return "connection_"
                + Convert.ToHexString(entropy).ToLowerInvariant();
        }

        private static void CancelWithoutEscaping(
            CancellationTokenSource source)
        {
            try
            {
                source.Cancel();
            }
            catch (Exception)
            {
                // A connection-owned cancellation callback is not allowed to
                // bypass the host's mandatory active-connection drain.
            }
        }
    }
}
