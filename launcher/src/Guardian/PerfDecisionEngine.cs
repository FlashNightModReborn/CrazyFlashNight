using System;
using CF7Launcher.Bus;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Host 唯一性能调度入口。Render 分部绑定真实 AS2 样本、完整目标与呈现确认；
    /// 不再保留旧两档控制器、影子决策或无身份 P 指令。
    /// </summary>
    public partial class PerfDecisionEngine
    {
        private readonly FpsRingBuffer _buffer;
        private readonly XmlSocketServer _socket;
        private AppActivationState _activationState;
        public bool IsActive { get; set; }
        public PerfDecisionEngine(FpsRingBuffer buffer,XmlSocketServer socket)
        {
            _buffer=buffer ?? throw new ArgumentNullException(nameof(buffer));
            _socket=socket;
        }
        public void SetActivationState(AppActivationState state) => _activationState=state;
        public void OnSceneReset() => ResetRenderObservations();
    }
}