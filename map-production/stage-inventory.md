# 地图生产关卡清单

**文档角色**：本批次地图生产范围、关卡组和优先级的 canonical 清单。任务机器可读定义在 `map-production/tasks.json`；本文只做人类可读摘要。

**范围基线**：只做无任务且未重置的战斗关卡地图；已有任务、已重置关卡、所有二层、地下2层、异界战场、坠毁战舰、亡灵沙漠、沙漠虫洞、旧副本、外交据点、地铁站深处均不在本批。

**交付边界**：本阶段只交地图资源，不新建或修改关卡 XML，不写 `stage_environment.xml`，不挂正式选关；每个地图组附独立的 `environment.proposal.xml`，供后续脚本一键实装。

## 总量

- 任务定义：68 个；可领取：67 个；草稿/待设计：1 个。
- 主图位：317 张；可领取任务覆盖 315 张。
- 主线 39 关，每关 5 图；支线短关卡 3 图起，长关卡 5 图起。

## 主线：诺亚前线基地深处

指挥部外围已有新图，跳过；防御地带只有 1/7 新图，按“不算整体重置”保留。

| ID | 关卡 | 主图 | 旧图参考 | 设计状态 |
|---|---|---:|---|---|
| ML-NOAH-001 | 僵尸卫队 | 5 | nyqxjdjswd_1_BG.swf、nyqxjdjswd_2_BG.swf、nyqxjdjswd_3_BG.swf、nyqxjdjswd_4_BG.swf | brief_required |
| ML-NOAH-002 | 决战之地 | 5 | nyqxjdjzzd_1_BG.swf、nyqxjdjzzd_2_BG.swf、nyqxjdjzzd_3_BG.swf、nyqxjdjzzd_4_BG.swf、nyqxjdjzzd_5_BG.swf | brief_required |
| ML-NOAH-003 | 初心者 | 5 | nyqxjdfydd_1_BG.swf、nyqxjdfydd_2_BG.swf、nyqxjdfydd_3_BG.swf、nyqxjdfydd_4_BG.swf、nyqxjdjswd_1_BG.swf、nyqxjdjswd_2_BG.swf、nyqxjdjswd_3_BG.swf、nyqxjdjswd_4_BG.swf | brief_required |
| ML-NOAH-004 | 尸母巢穴 | 5 | nyqxjdcd_1_BG.swf、nyqxjdcd_2_BG.swf、nyqxjdcd_3_BG.swf、nyqxjdsmcx_1_BG.swf、nyqxjdsmcx_2_BG.swf、nyqxjdsmcx_3_BG.swf、尸母巢穴中心_BG.swf、尸母巢穴虫洞过渡_BG.swf | brief_required |
| ML-NOAH-005 | 指挥部大厅 | 5 | nyqxjdzhbdt_1_BG.swf、nyqxjdzhbdt_2_BG.swf、nyqxjdzhbdt_3_BG.swf、nyqxjdzhbdt_4_BG.swf | brief_required |
| ML-NOAH-006 | 武器仓库 | 5 | 武器仓库内部1.swf、武器仓库内部2.swf、武器仓库外围.swf、武器仓库数据中心.swf、武器仓库走道.swf | brief_required |
| ML-NOAH-007 | 研究院 | 5 | nyqxjdbgc_1_BG.swf、nyqxjdbgc_3_BG.swf、nyqxjdfqck_1_BG.swf、nyqxjdfqck_3_BG.swf、nyqxjdfydd_1_BG.swf、nyqxjdfydd_3_BG.swf、nyqxjdjzzd_2_BG.swf、nyqxjdyjy_1_BG.swf、nyqxjdyjy_3_BG.swf | brief_required |
| ML-NOAH-008 | 虫洞 | 5 | nyqxjdcd_1_BG.swf、nyqxjdcd_2_BG.swf、nyqxjdcd_3_BG.swf、nyqxjdcd_4_BG.swf | brief_required |
| ML-NOAH-009 | 被摧毁的武器仓库 | 5 | nyqxjdfqck_1_BG.swf、nyqxjdfqck_2_BG.swf、nyqxjdfqck_3_BG.swf、nyqxjdfqck_4_BG.swf | brief_required |
| ML-NOAH-010 | 被清扫的虫洞 | 5 | nyqxjdcd_1_BG.swf、nyqxjdcd_2_BG.swf、nyqxjdcd_3_BG.swf、nyqxjdcd_4_BG.swf | brief_required |
| ML-NOAH-011 | 被炸毁的防御地带 | 5 | nyqxjdfydd_1_BG.swf、nyqxjdfydd_2_BG.swf、nyqxjdfydd_3_BG.swf、nyqxjdfydd_4_BG.swf | brief_required |
| ML-NOAH-012 | 解救A兵团士兵 | 5 | nyqxjdsmcx_1_BG.swf、nyqxjdsmcx_2_BG.swf、nyqxjdsmcx_3_BG.swf、nyqxjdsmcx_4_BG.swf、nyqxjdsmcx_5_BG.swf | brief_required |
| ML-NOAH-013 | 训练场 | 5 | nyqxjdxlc_1_BG.swf、nyqxjdxlc_2_BG.swf、nyqxjdxlc_3_BG.swf、nyqxjdxlc_4_BG.swf | brief_required |
| ML-NOAH-014 | 试验场 | 5 | nyqxjdsyc_1_BG.swf、nyqxjdsyc_2_BG.swf、nyqxjdsyc_3_BG.swf、nyqxjdsyc_4_BG.swf | brief_required |
| ML-NOAH-015 | 防御地带 | 5 | 防御地带内部1.swf、防御地带内部2.swf、防御地带内部3.swf、防御地带战壕.swf、防御地带电子战.swf、防御地带野外.swf、防御地带高地.swf | brief_required |

## 主线：雪山

| ID | 关卡 | 主图 | 旧图参考 | 设计状态 |
|---|---|---:|---|---|
| ML-SNOW-001 | 冰雪之心 | 5 | bxzx_1_BG.swf、bxzx_2_BG.swf、bxzx_3_BG.swf | brief_required |
| ML-SNOW-002 | 诺亚精英部队 | 5 | nyxsjybd_1_BG.swf、nyxsjybd_2_BG.swf、nyxsjybd_3_BG.swf | brief_required |
| ML-SNOW-003 | 诺亚雪山 | 5 | nyxs_1_BG.swf、nyxs_2_BG.swf、nyxs_3_BG.swf | brief_required |
| ML-SNOW-004 | 诺亚雪山山脊 | 5 | nyxssj1_1_BG.swf、nyxssj1_2_BG.swf、nyxssj1_3_BG.swf | brief_required |
| ML-SNOW-005 | 诺亚雪山山脚 | 5 | nyxssj_1_BG.swf、nyxssj_2_BG.swf、nyxssj_3_BG.swf | brief_required |
| ML-SNOW-006 | 诺亚雪山山顶 | 5 | nyxssd_1_BG.swf、nyxssd_2_BG.swf、nyxssd_3_BG.swf | brief_required |
| ML-SNOW-007 | 诺亚雪山部队 | 5 | nyxsbd_1_BG.swf、nyxsbd_2_BG.swf、nyxsbd_3_BG.swf | brief_required |
| ML-SNOW-008 | 雪原坡地 | 5 | xypd_1_BG.swf、xypd_2_BG.swf、xypd_3_BG.swf | brief_required |
| ML-SNOW-009 | 雪原基地 | 5 | xyjd_1_BG.swf、xyjd_2_BG.swf、xyjd_3_BG.swf | brief_required |
| ML-SNOW-010 | 雪原深处 | 5 | xysc_1_BG.swf、xysc_2_BG.swf、xysc_3_BG.swf | brief_required |
| ML-SNOW-011 | 雪原防御带 | 5 | xyfyd_1_BG.swf、xyfyd_2_BG.swf、xyfyd_3_BG.swf | brief_required |
| ML-SNOW-012 | 雪地平原 | 5 | xdpy_1_BG.swf、xdpy_2_BG.swf、xdpy_3_BG.swf | brief_required |

## 主线：雪山内部

| ID | 关卡 | 主图 | 旧图参考 | 设计状态 |
|---|---|---:|---|---|
| ML-SNOWIN-001 | 熔岩基地 | 5 | ryjd_1_BG.swf、ryjd_2_BG.swf、ryjd_3_BG.swf | brief_required |
| ML-SNOWIN-002 | 熔岩基地外围 | 5 | ryjdww_1_BG.swf、ryjdww_2_BG.swf、ryjdww_3_BG.swf | brief_required |
| ML-SNOWIN-003 | 熔岩广场 | 5 | rygc_1_BG.swf、rygc_2_BG.swf、rygc_3_BG.swf | brief_required |
| ML-SNOWIN-004 | 熔岩秘洞 | 5 | rymd_1_BG.swf、rymd_2_BG.swf、rymd_3_BG.swf | brief_required |
| ML-SNOWIN-005 | 熔岩营地 | 5 | ryyd_1_BG.swf、ryyd_2_BG.swf、ryyd_3_BG.swf | brief_required |
| ML-SNOWIN-006 | 熔岩隧道 | 5 | rysd_1_BG.swf、rysd_2_BG.swf、rysd_3_BG.swf | brief_required |
| ML-SNOWIN-007 | 秘密通道 | 5 | mmtd_1_BG.swf、mmtd_2_BG.swf、mmtd_3_BG.swf | brief_required |
| ML-SNOWIN-008 | 隧道入口 | 5 | sdrk_1_BG.swf、sdrk_2_BG.swf、sdrk_3_BG.swf | brief_required |
| ML-SNOWIN-009 | 集结点A | 5 | jjda_1_BG.swf、jjda_2_BG.swf、jjda_3_BG.swf | brief_required |
| ML-SNOWIN-010 | 集结点B | 5 | jjdb_1_BG.swf、jjdb_2_BG.swf、jjdb_3_BG.swf | brief_required |
| ML-SNOWIN-011 | 集结点C | 5 | jjdc_1_BG.swf、jjdc_2_BG.swf、jjdc_3_BG.swf | brief_required |
| ML-SNOWIN-012 | 雪山入口 | 5 | xsrk_1_BG.swf、xsrk_2_BG.swf、xsrk_3_BG.swf | brief_required |

## 支线：大学二期

按剧情流程拆 7 关；教学楼、操场、教室、走廊等非战斗场景已有，只作风格参考。另补 1 个下水道出口/后勤房间场景。

| ID | 关卡 | 主图 | 参考 | 设计状态 |
|---|---|---:|---|---|
| SQ-UNIV-001 | 校门/校园冲突 | 5 | 大学城周边 | doc_ready |
| SQ-UNIV-002 | 学生会办公楼（含秘密通道） | 5 | 大学城周边 | doc_ready |
| SQ-UNIV-003 | 校园广场 | 5 | 地图-联合大学 | doc_ready |
| SQ-UNIV-004 | 会议室 | 5 | 地图-联合大学 | doc_ready |
| SQ-UNIV-005 | 独立派校内据点大楼 | 5 | 地图-联合大学 | doc_ready |
| SQ-UNIV-006 | 禁区独立派基地 | 5 | 基地禁区边缘地带 | doc_ready |
| SQ-UNIV-007 | 天网试验基地 | 5 | 基地禁区边缘地带 | doc_ready |
| SQ-UNIV-008 | 下水道出口/后勤房间 | 2 | 堕落城下水道入口 | brief_required |

## 支线：将军 / 丽丽丝

研究所是同一地点，共用一套新图；丽丽丝只额外做模因电子战。

| ID | 关卡 | 主图 | 参考 | 共享 |
|---|---|---:|---|---|
| SQ-GEN-001 | 数据之海 | 5 | 电子战接入设备间 | - |
| SQ-GEN-002 | 禁区雪山边缘 | 5 | 雪原坡地 | - |
| SQ-GEN-003 | A兵团研究所 | 5 | 指挥部外围 | SQ-LILITH-001 |
| SQ-LILITH-001 | 模因电子战 | 5 | 电子战接入设备间 | SQ-GEN-003 |

## 支线：余烬

只给“明确提到地图变化”或“全新地点”的内容立任务。黑铁会、革命军哨所、难民营地、堕落城深处、军阀秘密基地、禁区边缘目前只换支援或难度，暂不做地图变体；第三集结点只有“追加携带任务道具的盗贼”，先保留一个待设计任务。

| ID | 关卡 | 主图 | 参考 | 可领取 |
|---|---|---:|---|---|
| SQ-EMBER-001 | 尘霾4号线/废城物资线 | 5 | 废城环线 | 是 |
| SQ-EMBER-002 | 公园外场 | 5 | 摇滚公园 | 是 |
| SQ-EMBER-003 | 一枚筹码 | 3 | 挑战罪袋练舞室 | 是 |
| SQ-EMBER-004 | 千金一掷 | 3 | 挑战齐天大圣 | 是 |
| SQ-EMBER-005 | 光子杀手 | 3 | 医院 | 是 |
| SQ-EMBER-006 | 百炼成锋 | 3 | 黑铁会 | 是 |
| SQ-EMBER-007 | 抽芯行动 | 5 | 军阀前线基地 | 是 |
| SQ-EMBER-008 | 锈蚀行动 | 5 | 黑铁会 | 是 |
| SQ-EMBER-009 | 不速之客 | 5 | 黑铁会 | 是 |
| SQ-EMBER-010 | 十步剑冢 | 5 | 黑铁会 | 是 |
| SQ-EMBER-011 | 金蝉脱壳 | 5 | 黑铁会 | 是 |
| SQ-EMBER-012 | 总部交界地带 | 5 | 黑铁会总部边缘 | 是 |
| SQ-EMBER-013 | 外环分基地 | 3 | 基地车库 | 是 |
| SQ-EMBER-014 | 挑战剑痴 | 3 | 剑圣的叹息 | 是 |
| SQ-EMBER-015 | 直升机前置 | 2 | 基地房顶 | 是 |
| SQ-EMBER-016 | 第三集结点（状态变体） | 2 | 第三集结点 | 否 |

## 支线：剑术大师

| ID | 关卡 | 主图 | 参考 |
|---|---|---:|---|
| SQ-SWORD-001 | 特制贫民窟 | 3 | 贫民窟 |

## 暂不排期的阻塞项

- 铁枪会二期：只有 70002 详细设计；70003 之后没有规格，无法定关卡数。
- 牛仔：没有剧情/关卡文档，需要 lsy 提供。
- 黑铁会外交部长：W699 PDF 不可可靠读取，需要文字版或剧情组口述；外交据点地图不在本批。
- 摇滚、天网、异形：没有可执行的任务/关卡文档，或只有规划表标签，暂不排期。
- 地铁站深处：组员独占，不派任务。

## 优先级

1. 主线诺亚 15 关。
2. 主线雪山 12 关。
3. 主线雪山内部 12 关。
4. 大学二期 8 个地图组。
5. 将军/丽丽丝 4 个地图组。
6. 余烬 15 个可领取地图组 + 1 个待设计变体。
7. 剑术大师 1 个地图组。
