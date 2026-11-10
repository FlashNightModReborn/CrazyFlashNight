using System;
using System.Collections.Generic;
using CF7Launcher.AgentRuntime.TrustedRunner;

namespace CF7Launcher.Bus
{
    // Candidate qualification only: existing AS2 debug-start preparation and
    // fixed read probes. No caller-selected expression, slot, item or function.
    internal static class QualificationConsolePolicy
    {
        internal const string PlayerProbe = "#eval:hero._name + \"|\" + hero._x + \"|\" + hero._y + \"|\" + hero[\"状态\"] + \"|\" + hero[\"攻击模式\"] + \"|\" + hero[\"强制奔跑\"] + \"|\" + hero[\"移动射击\"] + \"|\" + hero.man[\"换弹标签\"] + \"|\" + hero.man.reloadFrameControlActive + \"|\" + hero.hp";
        internal const string SceneProbe = "#eval:root.savePath + \"|\" + root._currentframe + \"|\" + root[\"帧计时器\"][\"当前帧数\"] + \"|\" + root.gameworld[\"场景名\"] + \"|\" + root.gameworld.__combatAdmitted + \"|\" + root.gameworld.__playerSceneGate.started + \"|\" + root.gameworld.__playerSceneGate.wavesStarted + \"|\" + root._saveExt.bookRun.bookId + \"|\" + root._saveExt.bookRun.routeId + \"|\" + root._saveExt.bookRun.debug";
        internal const string CoreProbe = "#eval:root.savePath + \"|\" + root._currentframe + \"|\" + root[\"帧计时器\"][\"当前帧数\"] + \"|\" + root[\"当前为战斗地图\"] + \"|\" + root[\"暂停\"] + \"|\" + root.gameworld[\"场景名\"] + \"|\" + root.gameworld.__combatAdmitted + \"|\" + root[\"当前关卡名\"] + \"|\" + root[\"当前关卡难度\"]";
        private static readonly HashSet<string> Commands = Build();
        private static HashSet<string> Build()
        {
            var result = new HashSet<string>(StringComparer.Ordinal) {
                "#get:savePath", PlayerProbe, SceneProbe, CoreProbe,
                "#_root.当前关卡名=尸母巢穴", "#_root.关卡类型=无限过图",
                "#_root.关卡路径=data/stages/诺亚前线基地深处/尸母巢穴.xml",
                "#_root.淡出跳转帧=wuxianguotu_1",
                "#func:_root.选关界面进入关卡(简单)", "#func:_root.返回基地()",
                "#give:机枪贫铀穿甲弹,1000",
                "#get:gameworld.__combatAdmitted",
                "#get:gameworld.__playerSceneGate.started",
                "#get:gameworld.__playerSceneGate.wavesStarted",
                "#get:_saveExt.bookRun.routeId",
                "#get:_saveExt.bookRun.debug"
            };
            foreach (string route in new[] { "historical", "type61" })
                foreach (int map in new[] { 7, 10, 13 })
                    result.Add("#func:_root.书中调试(1110," + map + ",cf6-sting," + route + ")1:int2:int");
            return result;
        }
        internal static bool TryApprove(string slot, string command, out string encoded)
        {
            encoded = null;
            if (!TrustedRegressionSlots.IsQualification(slot) || command == null || command.Length > 2048) return false;
            string decoded;
            try { decoded = Uri.UnescapeDataString(command); } catch { return false; }
            if (!Commands.Contains(decoded)) return false;
            // ServerManager performs AS2 unescape once. UTF-8 percent encoding
            // also avoids the legacy console's incompatible %uXXXX expansion.
            encoded = Uri.EscapeDataString(decoded);
            return true;
        }
    }
}
