// 选关界面 inventory 单一真值（golden baseline）。
// 凡新增 / 删除 / 重分类 stageButton、navButton、decoration，或补登 stageNames，
// 必须同批更新本文件 expected 计数与 provenance，然后跑：
//   node tools/audit-stage-select-layout.js --json
//   node tools/run-stage-select-harness.js --browser edge
// tools/audit-stage-select-layout.js 与 dev/qa-suite.js 均消费本文件；
// 文档（testing-guide / 选关界面-webview迁移路线图 / launcher README）引用本文件路径，
// 不再各自手抄计数。
var StageSelectGolden = {
    schema: 'stage-select-golden-inventory-v1',
    updated: '2026-08-16',
    expected: {
        labels: 16,
        // 冻结 .fla 源统计，退役后恒定不变。
        sourceStageButtonInstances: 182,
        // 运行时渲染实例 = 164（.fla 渲染基线）+ 2（web 手写新增：subway + 据点M）。
        stageButtonInstances: 166,
        // entryKind != 'difficulty' 的直达入口（外交绿点 + 副本任务）。
        directStageButtonInstances: 14,
        // entryKind == 'map'（外交地图绿点直达）。
        mapStageButtonInstances: 10,
        // entryKind == 'task'（副本任务 → Web tasks 面板 dungeon 视图）。
        taskStageButtonInstances: 4,
        decorationInstances: 2,
        navButtons: 28,
        // manifest.stageNames 数组长度 = 162（.fla 冻结 assetReport）+ 2（web 手写新增）。
        uniqueStageNames: 164
    },
    // .fla 退役后纯 web 手写新增条目的来源记录；新增条目时在此追加一行。
    provenance: [
        {
            id: 'stage_0_15',
            stageName: '外交-隧道据点',
            frameLabel: '基地门口',
            entryKind: 'map',
            note: '.fla 退役后首个纯 web 手写据点（无 .fla 源），确立「手改 SOT + 上调基线」模式'
        },
        {
            id: 'stage_10_18',
            stageName: '据点M',
            frameLabel: '基地车库',
            entryKind: 'difficulty',
            note: '情报支线半成品（commit 9f7584b3cb「创建交互管理器，并上传做到一半的情报支线关卡」），UnlockCondition 75；2026-08-16 P0 真值闭环时补登 stageNames 与计数基线'
        }
    ]
};
