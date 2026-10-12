using System;
using CF7Launcher.Data;
using CF7Launcher.Guardian;
using CF7Launcher.Save;

namespace CF7Launcher.RagTerminal
{
    /// <summary>
    /// 进程级「当前绑定存档槽位」上下文（AI 聊天终端阶段四）。
    ///
    /// 写入点只有两处，都已经在自己的路径上算出了槽位：
    ///   - <see cref="RagTerminalService"/> 的 bind / 刷新绑定（用 bind 载荷里的 slot_key）；
    ///   - MapDomainTask 的 task_sync（AS2「请求槽位目录同步」上报的 savePath）。
    /// 读取点是 DataQueryTask 的 NPC 对话查询：按存档的对话覆盖层
    /// （data/rag/agent_saves/&lt;slotKey&gt;/dialogue_overrides.json）只对该槽位生效。
    ///
    /// 槽位为空或非法＝不应用任何覆盖层，standalone 行为与现状逐字一致。
    /// 换槽位必须立刻生效，所以每次写入都让 AgentDialogueOverrides 的覆盖层缓存失效；
    /// base 数据缓存（DataCache）与此完全无关，绝不被触碰。
    /// </summary>
    internal static class AgentSaveContext
    {
        private static readonly object Gate = new object();
        private static string _currentSlotKey;

        /// <summary>当前绑定的槽位键；未绑定 / 非法形态为 null。</summary>
        internal static string CurrentSlotKey
        {
            get { lock (Gate) return _currentSlotKey; }
        }

        /// <summary>记录当前绑定槽位。空值或非槽位键形态等同 <see cref="Clear"/>（不派生覆盖层路径）。</summary>
        internal static void Set(string slotKey)
        {
            string valid;
            if (!SaveSlotKey.TryValidateExisting(slotKey ?? "", out valid))
            {
                Clear();
                return;
            }

            bool changed;
            lock (Gate)
            {
                changed = !string.Equals(_currentSlotKey, valid, StringComparison.Ordinal);
                _currentSlotKey = valid;
            }

            // 覆盖层是小文件，失效只意味着下次查询按文件指纹重读；即使槽位没变，
            // 一次 bind / 刷新也是一次「后端可能已改写覆盖层」的信号。
            AgentDialogueOverrides.Invalidate();
            if (changed)
                LogManager.Log("[AgentSaveContext] slot bound slot=" + valid);
        }

        /// <summary>解除绑定（未加载存档 / AS2 上报空 savePath）。</summary>
        internal static void Clear()
        {
            bool changed;
            lock (Gate)
            {
                changed = _currentSlotKey != null;
                _currentSlotKey = null;
            }
            if (!changed) return;

            AgentDialogueOverrides.Invalidate();
            LogManager.Log("[AgentSaveContext] slot cleared");
        }
    }
}
