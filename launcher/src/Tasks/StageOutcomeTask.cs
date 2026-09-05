using System;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    public interface IStageOutcomePresenter
    {
        event Action<string, string, int> IntentRequested;
        void SetReady();
        void ApplyState(StageOutcomeState state);
        void ResetState();
    }

    /// <summary>
    /// StageRunSession → 常驻 HUD 条件状态槽的严格只读桥，以及原生按钮 → AS2 cmd 的意图桥。
    /// 不在 Host 内判定复活、扣币、转场或奖励终态。
    /// </summary>
    public sealed class StageOutcomeTask : IDisposable
    {
        private readonly XmlSocketServer _socket;
        private readonly Func<string, bool> _trySend;
        private readonly IStageOutcomePresenter _presenter;
        private long _intentSequence;
        private bool _disposed;

        public StageOutcomeTask(
            XmlSocketServer socket, IStageOutcomePresenter presenter)
            : this(
                socket,
                delegate(string payload)
                {
                    return socket != null && socket.TrySend(payload);
                },
                presenter)
        {
        }

        internal StageOutcomeTask(
            Func<string, bool> trySend, IStageOutcomePresenter presenter)
            : this(null, trySend, presenter)
        {
        }

        private StageOutcomeTask(
            XmlSocketServer socket,
            Func<string, bool> trySend,
            IStageOutcomePresenter presenter)
        {
            _socket = socket;
            _trySend = trySend ?? delegate { return false; };
            _presenter = presenter ?? throw new ArgumentNullException("presenter");
            _presenter.IntentRequested += OnIntentRequested;
            if (_socket != null)
            {
                _socket.OnClientReady += OnClientReady;
                _socket.OnClientDisconnected += HandleTransportDisconnected;
            }
        }

        public string Handle(JObject message)
        {
            if (_disposed) return null;
            StageOutcomeState state;
            string error;
            if (!StageOutcomeState.TryParseMessage(message, out state, out error))
            {
                LogManager.Log("event=stage_outcome_rejected reason=" + error);
                return null;
            }
            _presenter.ApplyState(state);
            return null;
        }

        public void SetReady()
        {
            if (_disposed) return;
            _presenter.SetReady();
            SendSync();
        }

        private void OnClientReady()
        {
            if (!_disposed) SendSync();
        }

        internal void HandleTransportDisconnected()
        {
            if (_disposed) return;
            _presenter.ResetState();
        }

        private void SendSync()
        {
            JObject command = new JObject
            {
                ["task"] = "cmd",
                ["action"] = "stageOutcomeSync",
                ["v"] = 1
            };
            TrySend(command);
        }

        private void OnIntentRequested(
            string intent, string runId, int expectedRevision)
        {
            if (_disposed || !IsIntent(intent)
                    || string.IsNullOrEmpty(runId) || expectedRevision < 1)
                return;
            long sequence = Interlocked.Increment(ref _intentSequence);
            string intentId = "host." + sequence + "." + Guid.NewGuid().ToString("N");
            JObject command = new JObject
            {
                ["task"] = "cmd",
                ["action"] = "stageOutcomeAction",
                ["v"] = 1,
                ["runId"] = runId,
                ["expectedRevision"] = expectedRevision,
                ["intent"] = intent,
                ["intentId"] = intentId
            };
            TrySend(command);
        }

        private bool TrySend(JObject command)
        {
            bool sent = false;
            try
            {
                sent = _trySend(command.ToString(Formatting.None) + "\0");
            }
            catch (Exception ex)
            {
                LogManager.Log("event=stage_outcome_send_failed type="
                    + ex.GetType().Name);
            }
            if (!sent)
                LogManager.Log("event=stage_outcome_send_failed type=disconnected");
            return sent;
        }

        private static bool IsIntent(string intent)
        {
            return intent == "revive" || intent == "return_base"
                || intent == "return_deliverable"
                || intent == "resume_rewards";
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            if (_socket != null)
            {
                _socket.OnClientReady -= OnClientReady;
                _socket.OnClientDisconnected -= HandleTransportDisconnected;
            }
            _presenter.IntentRequested -= OnIntentRequested;
        }
    }
}
