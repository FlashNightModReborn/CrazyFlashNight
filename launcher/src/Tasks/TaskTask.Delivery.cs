using System;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    public interface ITaskDeliveryPresenter
    {
        event Action<string, string, string> DeliveryRequested;
        void ApplyDeliveryState(string scope, TaskDestinationChoices options);
        void ResetDeliveryState();
    }
    public sealed partial class TaskTask
    {
        private XmlSocketServer _deliverySocket;
        private ITaskDeliveryPresenter _deliveryPresenter;
        public void SetDeliveryPresenter(ITaskDeliveryPresenter presenter)
        {
            if (_deliveryPresenter != null) _deliveryPresenter.DeliveryRequested -= SendDeliveryAction;
            _deliveryPresenter = presenter;
            if (presenter != null) presenter.DeliveryRequested += SendDeliveryAction;
        }
        public string HandleDeliveryState(JObject message)
        {
            if (_disposed || _deliveryPresenter == null) return null;
            JObject payload = message?["payload"] as JObject;
            if (!TaskDestinationChoices.HasExactKeys(message, "task", "payload")
                || message["task"]?.Type != JTokenType.String || (string)message["task"] != "task_delivery"
                || !TaskDestinationChoices.HasExactKeys(payload, "v", "scope", "options")
                || payload["v"]?.Type != JTokenType.Integer || payload["v"].ToString(Formatting.None) != "1"
                || payload["scope"]?.Type != JTokenType.String
                || !TaskDestinationChoices.TryParse(payload["options"] as JObject, out var options)
                || (options.Status != "none" && options.Status != "ready" && options.Status != "confirming")
                || (options.Status == "none" ? (string)payload["scope"] != ""
                    : !TaskDestinationChoices.TryReadOpaque(payload["scope"], 96, out _)))
            {
                LogManager.Log("event=task_delivery_rejected reason=invalid_message");
                ResetDelivery();
                return null;
            }
            _deliveryPresenter.ApplyDeliveryState((string)payload["scope"], options);
            return null;
        }
        public void SyncDelivery()
        {
            if (!_disposed && _deliveryPresenter != null && _isClientReady())
                _send(new JObject { ["task"] = "cmd", ["action"] = "taskDeliverySync", ["v"] = 1 }.ToString(Formatting.None) + "\0");
        }
        private void SendDeliveryAction(string intent, string token, string choice)
        {
            if (_disposed || !_isClientReady() || (intent != "navigate" && intent != "refresh")
                || !TaskDestinationChoices.TryReadOpaque(new JValue(token), 96, out _)
                || (intent == "navigate" ? !TaskDestinationChoices.TryReadOpaque(new JValue(choice), 96, out _) : choice != "")) return;
            _send(new JObject { ["task"] = "cmd", ["action"] = "taskDeliveryAction", ["v"] = 1,
                ["intent"] = intent, ["choicesToken"] = token, ["choiceId"] = choice }.ToString(Formatting.None) + "\0");
        }
        private void ResetDelivery() { _deliveryPresenter?.ResetDeliveryState(); }
        private void DisposeDelivery()
        {
            if (_deliverySocket != null) { _deliverySocket.OnClientReady -= SyncDelivery; _deliverySocket.OnClientDisconnected -= ResetDelivery; }
            if (_deliveryPresenter != null) { _deliveryPresenter.DeliveryRequested -= SendDeliveryAction; _deliveryPresenter.ResetDeliveryState(); }
            _deliveryPresenter = null;
        }
    }
}
