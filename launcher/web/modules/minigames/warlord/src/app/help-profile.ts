export type HelpAnchor =
  | 'overview'
  | 'turn'
  | 'movement'
  | 'action-points'
  | 'garrison-capacity'
  | 'deployment-limit'
  | 'production'
  | 'advancement'
  | 'battle-results'
  | 'diplomacy'
  | 'commanders'
  | 'command-post'
  | 'large-map';

export interface HelpSection {
  anchor: HelpAnchor;
  title: string;
  summary: string;
  details: readonly string[];
}

export interface HelpProfile {
  schemaVersion: 'warlord.help-profile.v1';
  terminologyVersion: 'warlord.player-terminology.zh-cn.v1';
  profileId: string;
  sections: readonly HelpSection[];
}

export interface HelpUiState {
  open: boolean;
  anchor: HelpAnchor;
}

export const HELP_PROFILE: HelpProfile = {
  schemaVersion: 'warlord.help-profile.v1',
  terminologyVersion: 'warlord.player-terminology.zh-cn.v1',
  profileId: 'warlord.demo-01.current-rules.v1',
  sections: [
    {
      anchor: 'overview',
      title: '这关怎样获胜',
      summary: '让敌方失去全部部队、待部署兵力和稳定生产据点即可获胜。',
      details: [
        '我方也会按同一条件失败；不要让最后的部队和生产据点同时丢失。',
        '若第 24 回合仍未分出胜负，会依次比较稳定生产据点、据点价值、现有兵力价值和剩余军费。',
      ],
    },
    {
      anchor: 'turn',
      title: '一回合怎样操作',
      summary: '选择我方部队，向相邻据点下令，然后主动结束本回合。',
      details: [
        '顶栏会显示当前回合、当前行动方和剩余行动点。',
        '双方行动结束后统一进行恢复、占领、收入、升级和生产安排。',
      ],
    },
    {
      anchor: 'movement',
      title: '怎样移动和进攻',
      summary: '同一据点的部队可以临时编队；绿色目标可移动，红色目标会进入战斗。',
      details: [
        '点击一支我方部队开始选择；按住多选键可增减选择或框选同一据点的部队。',
        '移动可直接确认；进攻需要再次确认，避免误触后立即开战。',
      ],
    },
    {
      anchor: 'action-points',
      title: '行动点',
      summary: '行动点是本回合可以调动部队的额度；每支实际行动的部队消耗 1 点。',
      details: [
        '行动点不足时，请减少参战部队，或结束本回合等待下一轮。',
        '中央指挥据点等特殊据点会影响后续回合获得的行动点。',
      ],
    },
    {
      anchor: 'garrison-capacity',
      title: '驻军上限',
      summary: '每个据点能容纳的部队数量有限，界面会同时显示当前驻军数量与这个据点的上限。',
      details: [
        '移动到己方或无主据点时，超过上限的部队不会被静默移动。',
        '请减少本次移动的部队，或先把目标据点的驻军调走。',
      ],
    },
    {
      anchor: 'deployment-limit',
      title: '本次最多投入',
      summary: '狭窄据点会限制一次进攻能投入的部队数量。',
      details: [
        '确认前会同时显示已选部队数和本次最多可投入的部队数；超出时请减少参战部队。',
        '驻军上限限制据点能留下多少部队，本次最多投入限制一次进攻能出动多少部队。',
      ],
    },
    {
      anchor: 'production',
      title: '怎样安排生产',
      summary: '统一结算阶段可以自动安排生产，也可以指定生产据点和槽位。',
      details: [
        '生产会消耗军费并预留人口；据点失稳、人口已满或等级不足都会阻止下单。',
        '尚未获得生产进度的订单可以全额撤销；已经开工的订单不能撤销。',
      ],
    },
    {
      anchor: 'advancement',
      title: '升级和升阶',
      summary: '战后经验可以提升兵种等级，升阶需要达到指定等级并支付军费。',
      details: [
        '每个兵种的升阶有固定顺序，同一结算阶段最多升阶一次。',
        '升级、升阶和生产都只在统一结算阶段开放。',
      ],
    },
    {
      anchor: 'battle-results',
      title: '战斗结果和返回',
      summary: '进攻确认后会进入动作战斗，战斗结束后返回沙盘并更新兵力和据点。',
      details: [
        '结果尚未确认时战略结算会暂停，不会因此直接判负。',
        '返回后先查看战况与据点变化，再继续下达下一条命令。',
      ],
    },
  ],
};

export const DEMO_2_HELP_PROFILE: HelpProfile = {
  ...HELP_PROFILE,
  profileId: 'warlord.demo-02.four-faction.v1',
  sections: [
    {
      anchor: 'overview',
      title: '这关怎样获胜',
      summary: '守住我方指挥所，并消灭另外两个敌对胜利组；东北与西南两名军阀共同胜负。',
      details: [
        '我方指挥所一旦被合法攻占，整关立即失败；局部战斗获胜并不保证战略安全。',
        '敌方指挥所被攻占后，该阵营投降并退出后续回合；盟约中的另一名军阀不会一起消失。',
      ],
    },
    {
      anchor: 'diplomacy',
      title: '四方关系和共同胜负',
      summary: '我方、东南独立军阀、南北盟约是三个胜利组；两支盟约军互为盟军，其余关系均为敌对。',
      details: [
        '盟军可以作为两段移动的中转，但不能共同驻军、共同参战或互相提供数值加成。',
        '地图和列表同时显示文字、短标和线型，不需要只靠颜色判断阵营。',
      ],
    },
    {
      anchor: 'command-post',
      title: '指挥所为什么重要',
      summary: '指挥所既是战略生命线，也是指挥官重建和主角重新出动的地点。',
      details: [
        '基地有双出口与多层纵深；受到威胁时，大地图告警会给出可定位的下一步。',
        '敌方指挥所被攻占会触发无奖励的投降清理，不把撤离部队算作击杀或战利品。',
      ],
    },
    {
      anchor: 'commanders',
      title: '指挥官和我方主角',
      summary: '在前线的指挥官会提供独立的前线行动点；离场后，尚未花掉的这部分行动点立即失效。',
      details: [
        'Boss 指挥官阵亡后可由其 AI 在安全指挥所高价重建；阵营不会因为 Boss 一次阵亡就直接失败。',
        '我方主角倒地后撤往后方；统一结算时只能从仍安全的我方指挥所重新出动。',
      ],
    },
    {
      anchor: 'large-map',
      title: '怎样看大地图',
      summary: '用战区下拉框缩小范围，用中文名称查找据点，用告警按钮直接定位需要处理的位置。',
      details: [
        '四角是基地纵深，中间工业环产出高但暴露；争夺中央不是唯一道路，外围仍有侧翼绕行线。',
        '底部据点索引只显示局部或当前页，避免一次生成全部 80 个节点按钮。',
      ],
    },
    ...HELP_PROFILE.sections.filter((section) => section.anchor !== 'overview'),
  ],
};

export function helpProfileForScenario(scenarioId: string): HelpProfile {
  return scenarioId === 'warlord_demo_02_v1' ? DEMO_2_HELP_PROFILE : HELP_PROFILE;
}

export function createHelpUiState(): HelpUiState {
  return { open: false, anchor: 'overview' };
}

export function openHelpUi(state: HelpUiState, anchor: HelpAnchor = 'overview'): HelpUiState {
  return { ...state, open: true, anchor };
}

export function closeHelpUi(state: HelpUiState): HelpUiState {
  return { ...state, open: false };
}

export function isHelpAnchor(value: string | undefined): value is HelpAnchor {
  return [...HELP_PROFILE.sections, ...DEMO_2_HELP_PROFILE.sections]
    .some((section) => section.anchor === value);
}
