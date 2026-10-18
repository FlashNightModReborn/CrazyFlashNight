from pathlib import Path
import datetime,hashlib,importlib.util,json,shutil,subprocess
R=Path.cwd();D=R/'tmp/cf6-combat-calibration-20261017/loader-size-followup'
Q=R/'tools/cf6-elder-assets/evidence/20261018-loader-size-followup'
load=lambda p:json.loads(p.read_text('utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert Q.exists() and not (Q/'integrity.json').exists()
summary=load(Q/'summary.json');assert summary['qualified']
assert summary['headIntegration']['wins']==6 and summary['elderIntegration']['rows']==12
spec=importlib.util.spec_from_file_location('evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py')
u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
pkg=u.Package(Q);pkg.mapping=load(D/'package-state.json')['mapping']
docs=['tools/cf6-elder-assets/README.md','tools/cf6-headbot-assets/README.md','docs/asLoader-README.md']
for name in docs:pkg.copy(R/name,'documentation/before/'+name)
def replace_once(text,old,new):
    assert text.count(old)==1,old
    return text.replace(old,new)
elder=R/docs[0];text=elder.read_bytes().decode('utf-8-sig')
text=replace_once(text,'## 当前校准结果','## 完整强度校准（C5）')
text=replace_once(text,'最终主线源码下重新完成四组真实 CS6 回归','完成强度校准时的主线源码下重新完成四组真实 CS6 回归')
old='汇总入口：[本轮证据](evidence/20261017-calibration/summary.json)。实际对战使用冻结 C5 加载器与 R4 隔离 Host 候选；后来合入的 AI 终端源码只做源码回归，未借此发布新终端功能。测试期间临时保持唤醒已结束，真实存档、原始失败和编译记录均保留。本包在提交前封存，实际 commit／push 以 Git 历史为准；未进行正式 runtime 发布。玩家手感、物理音频、弱机性能和标准入口体验仍分别待验收。'
new=f'''汇总入口：[C5 完整校准证据](evidence/20261017-calibration/summary.json)。以上完整统计绑定冻结 C5 加载器与 R4 隔离 Host 候选，已在 `dabd11a895` 提交封存；原始失败、旧判定和每个文件均保留。

随后修复 asLoader 通信启动函数超过既有 60,000 字节门槛的问题，当前交付为 C6。业务 include 保序拆成两段，最大函数体为 53,041 字节；727 个编译类动作与 C5 相同，唯一变化是此前主线合入的 ServerManager 只读终端状态白名单，Agent 终端兼容脚本也随本轮编译纳入。当前战斗资源、AI 和数值未变。新加载器完成 103 项启动／握手回归及 9 次实际启动事件顺序核对；另跑大头 6 场全胜、老头 12 场（{summary['elderIntegration']['wins']} 胜／{summary['elderIntegration']['losses']} 负），均自然完成，老头逐场恰好交接一次。该 18 场用于加载器集成，不重新宣称完整强度验收，详见 [C6 补充验证](evidence/20261018-loader-size-followup/README.md)。

临时保持唤醒已结束，原编辑器和真实存档均保留。Host 仍为 R4 隔离候选，未进行正式 runtime 发布；玩家手感、物理音频、弱机性能和标准入口体验仍分别待验收。'''
new=new.replace('临时保持唤醒已结束，','C6 首轮有一个 100 级兽王分片被 Worker 所有权探测门拦下，未取得对战结果；原批次仍标不合格，存档与退出核验后以新隔离会话补齐两场，失败原件单独保留。临时保持唤醒已结束，')
text=replace_once(text,old,new);elder.write_bytes(text.encode('utf8'))
head=R/docs[1];text=head.read_bytes().decode('utf-8-sig')
text=replace_once(text,'当前 472 号大头机器人已在整合主线场景的 C5 公共加载器','472 号大头机器人的完整强度矩阵在整合主线场景的 C5 公共加载器')
text=replace_once(text,'当前十三项绑定输入均与本轮原始回执一致','C5 完整矩阵的十三项输入均在原始回执中冻结')
anchor='## 2026-10-17 击退联动、护盾与机械爆炸（校准前历史）'
addition='''当前交付加载器已更新为 C6，修复通信启动函数的大小门。大头战斗资源、AI、数值和相关编译类未改；新增 30／60／99 级、双方各一次共 6 场集成验证，全部自然获胜、无超时，另有 103 项启动／握手回归。上表十八场仍保留 C5 身份，不改记为 C6 完整矩阵，见 [C6 加载器补充验证](../cf6-elder-assets/evidence/20261018-loader-size-followup/README.md)。

'''
text=replace_once(text,anchor,addition+anchor);head.write_bytes(text.encode('utf8'))
boot=R/docs[2];text=boot.read_bytes().decode('utf-8-sig').replace('\r\n','\n')
anchor='`BOOT_SOURCES`、启动状态机和业务脚本未因拆分改写。'
addition=' 本轮新产物的两段分别为 45,559 / 15,472 B，全部函数最大 53,041 B；新鲜 Compiler `0/0`、103 项启动／握手断言、9 次实际候选启动的事件顺序及 18 场集成均通过，详见 [C6 补充证据](../tools/cf6-elder-assets/evidence/20261018-loader-size-followup/README.md)。C5 的完整强度统计保留原执行身份；本次未发布新的正式 Host runtime。'
text=replace_once(text,anchor,anchor+addition);boot.write_bytes(text.replace('\n','\r\n').encode('utf8'))
readme=f'''# C6 加载器大小门修复与补充验证

本包承接 `dabd11a89570125b6fe2125aa45b5ccaf2d60cd2` 的 CF6 校准提交，修复该提交触发的 AS2 CI 失败。父提交已有相同的通信函数体 60,668 B，超过现有 60,000 B 门槛；未提高或跳过门槛。原失败日志和父产物比较保留在本包。

`frame3.as` 沿 Agent 注册边界拆为 `f3_1 → f3_2`，仍在同一 S1 阶段同步执行。相对拆分前的同一主线源码，函数体按原顺序拼接相同，没有跨段顶层局部变量。CS6 本轮发布 `0 错误／0 警告`；两段 45,559 / 15,472 B，全产物最大 53,041 B，生产闭包 715 个 SWF、728 个类的归属检查通过。[改动及字节码范围](records/change-analysis.json)同时保留“近墙门不能单独排除 UI16 回绕”的边界。

727 个既有编译类动作与 C5 相同，ServerManager 随此前已合入主线的只读终端状态白名单更新；Agent 的既有终端兼容源码也编入本轮。战斗源码、AI、资源和数值保持 C5 校准版本。C6 为 `scripts/asLoader.swf`，SHA-256 `{summary['loaderC6']['sha256'].lower()}`；实际执行 Host 仍为 R4 隔离候选，身份与全部绑定见[机器汇总](summary.json)。

- 新鲜 BootSequencer 91 项、BootstrapHandshake 12 项，共 103 项通过，零失败、零 32K 重试；原测试入口恢复，原编辑器保留。
- [大头 6 场](head/integration-summary.json)：30／60／99 级，双方各一次，6 胜，无超时。
- [老头 12 场](elder/integration-summary.json)：60／80／100 级、两个对手、双方各一次，{summary['elderIntegration']['wins']} 胜、{summary['elderIntegration']['losses']} 负，无超时，逐场恰好交接一次。
- [9 次实际启动](records/boot-proof/summary.json)各自绑定原始诊断档案哈希和当前宿主区间，启动事件顺序与既有 golden 相同。私有原件保留在本机，本包只含相应启动消息原文及来源位置。
- 存档保护、候选资源一致性、退出和显示观察均通过；最后一场结束后立即释放临时唤醒。

另保留 [原批次未通过的分片](elder-primary/coordinator/experiment-report.json)及[具体分析](records/failed100-assessment.json)：100 级兽王分片在对战请求的所有权探测处失败，未取得结果；保护与退出核验后，另用[新隔离会话](elder-retry/integration-summary.json)完成缺失两场。原批次的“不合格”状态未改写，也未放宽门禁或重用旧会话。探测进程未返回有效结果的底层原因仍未知，不以补跑通过声称该工具问题已修复。

这 18 场是 C6 加载器集成验证，不代替 [C5 完整 18＋36 场强度校准](../20261017-calibration/summary.json)。C5 的 4,773 个索引文件逐项校验未变；旧包中的当前目录检查需要其原 C5 输入，不能拿更新后的 C6 目录回填旧证据。没有执行正式 runtime 发布，也不代签标准入口、物理音频、玩家手感或弱机性能。

冻结检查：在仓库根运行 `python -X utf8 -B tools/cf6-elder-assets/evidence/20261018-loader-size-followup/verify-followup.py`；交付当时的 C6 工作树可追加 `--check-current`。实际编译源码保存在 [源码原件](records/actual-as2-source.zip)与[逐文件身份](records/inputs-before.json)，复现使用原件字节。大于 8,000,000 字节的采集项按 `lossless-mapping.json` 无损还原，全部文件按 `integrity.json` 核验。该包在提交前封存，commit／push 和远端 CI 结果以随后 Git 历史为准。
'''
u.put(Q/'README.md',readme.encode('utf8'))
pkg.copy(D/'verify-followup.py','verify-followup.py')
before=[{'path':n,'sha256':sha(R/n)} for n in docs]
with (D/'final-documentation-check.log').open('xb') as f:
    run=subprocess.run(['node','tools/validate-doc-governance.js'],stdout=f,stderr=subprocess.STDOUT)
after=[{'path':n,'sha256':sha(R/n)} for n in docs]
doccheck={'qualified':run.returncode==0 and before==after,'exitCode':run.returncode,
          'sourceUnchanged':before==after,'documents':before,'completedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'boundary':'The canonical documentation check retains its warnings; success does not claim zero historical link debt.'}
u.jput(D/'final-documentation-check.json',doccheck)
assert doccheck['qualified']
pkg.copy(D/'final-documentation-check.log','checks/documentation.log')
pkg.copy(D/'final-documentation-check.json','checks/documentation.json')
for name in docs:pkg.copy(R/name,'documentation/current/'+name)
result=pkg.finish()
u.jput(D/'seal-summary.json',{**result,'integritySha256':sha(Q/'integrity.json')})
print(json.dumps(result))
