using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// B1 的 C# frozen preparation tuple。它只描述固定 identity / short label /
    /// command，不承担 route authorization，也不是运行时 registry。
    /// </summary>
    internal sealed class PreparationRoute
    {
        internal PreparationRoute(
            string identity,
            string label,
            string commandKey)
        {
            Identity = identity;
            Label = label;
            CommandKey = commandKey;
        }

        internal string Identity { get; private set; }
        internal string Label { get; private set; }
        internal string CommandKey { get; private set; }
    }

    /// <summary>
    /// HUD / Web fixture 对照所消费的统一 progression 投影。
    /// visible 与 enabled 分离，reason 只在 disabled 时非空。
    /// </summary>
    internal sealed class PreparationAvailability
    {
        internal PreparationAvailability(
            PreparationRoute route,
            bool visible,
            bool enabled,
            string reason)
        {
            Route = route;
            Visible = visible;
            Enabled = enabled;
            Reason = reason ?? "";
        }

        internal PreparationRoute Route { get; private set; }
        internal bool Visible { get; private set; }
        internal bool Enabled { get; private set; }
        internal string Reason { get; private set; }
    }

    internal static class PreparationNavigationCatalog
    {
        private const int WarehouseQuestThreshold = 13;

        private static readonly ReadOnlyCollection<PreparationRoute> Routes =
            Array.AsReadOnly(new[]
            {
                new PreparationRoute("equipment", "装备", "EQUIP_UI"),
                new PreparationRoute("battlebox", "战备箱", "WAREHOUSE"),
                new PreparationRoute("tuning", "装备调制", "EQUIPMENT_TUNING"),
                new PreparationRoute("skills", "技能", "SKILLS"),
                new PreparationRoute("materials", "材料", "MATERIALS"),
                new PreparationRoute("intelligence", "情报", "INTELLIGENCE")
            });

        internal static IReadOnlyList<PreparationRoute> FrozenRoutes
        {
            get { return Routes; }
        }

        internal static PreparationAvailability[] Project(
            bool gameReady,
            int questProgress)
        {
            PreparationAvailability[] result =
                new PreparationAvailability[Routes.Count];
            for (int i = 0; i < Routes.Count; i++)
            {
                PreparationRoute route = Routes[i];
                bool visible = gameReady;
                bool enabled = gameReady;
                string reason = gameReady ? "" : "进入游戏后可用";

                if ((route.Identity == "battlebox"
                        || route.Identity == "tuning")
                    && questProgress <= WarehouseQuestThreshold)
                {
                    enabled = false;
                    reason = "完成基地整备后开放";
                }

                result[i] = new PreparationAvailability(
                    route,
                    visible,
                    enabled,
                    reason);
            }
            return result;
        }
    }

    internal sealed class NotchToolbarAction
    {
        internal NotchToolbarAction(
            string label,
            string commandKey,
            bool visible,
            bool enabled,
            string reason,
            bool requiresWarehouse = false)
        {
            Label = label;
            CommandKey = commandKey;
            Visible = visible;
            Enabled = enabled;
            Reason = reason ?? "";
            RequiresWarehouse = requiresWarehouse;
        }

        internal string Label { get; private set; }
        internal string CommandKey { get; private set; }
        internal bool Visible { get; private set; }
        internal bool Enabled { get; private set; }
        internal string Reason { get; private set; }
        internal bool RequiresWarehouse { get; private set; }
    }

    internal sealed class NotchToolbarRow
    {
        internal NotchToolbarRow(
            string label,
            NotchToolbarAction[] actions)
        {
            Label = label ?? "";
            Actions = actions ?? new NotchToolbarAction[0];
        }

        internal string Label { get; private set; }
        internal NotchToolbarAction[] Actions { get; private set; }
    }

    /// <summary>
    /// Native 与 legacy 刘海共享的 presentation fixture。默认 rollout-off
    /// 精确保留旧游戏行；rollout-on 才投影新游戏/整备分组。
    /// </summary>
    internal static class NotchToolbarProjection
    {
        private static readonly NotchToolbarAction[] CurrentGame =
        {
            Action("战队", "TEAM"),
            Action("平板", "TABLET"),
            Action("战备箱", "WAREHOUSE", true),
            Action("情报", "INTELLIGENCE"),
            Action("材料", "MATERIALS"),
            Action("技能", "SKILLS"),
            Action("商城", "SHOP")
        };

        private static readonly NotchToolbarAction[] PreparationGame =
        {
            Action("战队", "TEAM"),
            Action("平板", "TABLET"),
            Action("商城", "SHOP")
        };

        private static readonly NotchToolbarAction[] Utility =
        {
            Action("点歌机", "JUKEBOX_EXPAND"),
            Action("地图开关", "MAPHUD_TOGGLE"),
            Action("修改器", "SETTINGS"),
            Action("帮助", "HELP")
        };

        private static readonly NotchToolbarAction[] System =
        {
            Action("全屏", "F"),
            Action("日志", "LOG"),
            Action("其他 ▸", null)
        };

        internal static NotchToolbarRow[] Build(
            bool nativeHud,
            bool preparationNavigationV1,
            bool gameReady,
            int questProgress)
        {
            if (!preparationNavigationV1)
            {
                if (!nativeHud)
                    return new[] { Row("", CurrentGame, gameReady, questProgress) };
                return new[]
                {
                    Row("游戏", CurrentGame, gameReady, questProgress),
                    Row("辅助", Utility, gameReady, questProgress),
                    Row("系统", System, gameReady, questProgress)
                };
            }

            NotchToolbarRow game =
                Row("游戏", PreparationGame, gameReady, questProgress);
            NotchToolbarRow preparation =
                new NotchToolbarRow(
                    "整备",
                    ProjectPreparation(gameReady, questProgress));
            if (!nativeHud)
                return new[] { game, preparation };
            return new[]
            {
                game,
                preparation,
                Row("辅助", Utility, gameReady, questProgress),
                Row("系统", System, gameReady, questProgress)
            };
        }

        private static NotchToolbarRow Row(
            string label,
            NotchToolbarAction[] source,
            bool gameReady,
            int questProgress)
        {
            NotchToolbarAction[] actions =
                new NotchToolbarAction[source.Length];
            for (int i = 0; i < source.Length; i++)
            {
                NotchToolbarAction item = source[i];
                bool visible = gameReady;
                bool enabled = gameReady;
                string reason = gameReady ? "" : "进入游戏后可用";
                if (item.RequiresWarehouse
                    && questProgress <= 13)
                {
                    // rollout-off 的旧 exact layout 保持历史行为：未解锁时隐藏。
                    visible = false;
                    enabled = false;
                    reason = "完成基地整备后开放";
                }
                actions[i] = new NotchToolbarAction(
                    item.Label,
                    item.CommandKey,
                    visible,
                    enabled,
                    reason,
                    item.RequiresWarehouse);
            }
            return new NotchToolbarRow(label, actions);
        }

        private static NotchToolbarAction[] ProjectPreparation(
            bool gameReady,
            int questProgress)
        {
            PreparationAvailability[] source =
                PreparationNavigationCatalog.Project(
                    gameReady,
                    questProgress);
            NotchToolbarAction[] actions =
                new NotchToolbarAction[source.Length];
            for (int i = 0; i < source.Length; i++)
            {
                actions[i] = new NotchToolbarAction(
                    source[i].Route.Label,
                    source[i].Route.CommandKey,
                    source[i].Visible,
                    source[i].Enabled,
                    source[i].Reason);
            }
            return actions;
        }

        private static NotchToolbarAction Action(
            string label,
            string commandKey,
            bool warehouse = false)
        {
            return new NotchToolbarAction(
                label,
                commandKey,
                true,
                true,
                "",
                warehouse);
        }
    }
}
