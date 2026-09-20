# 磁暴坦克 G08 外交地图静态装配

外交军阀基地原有车辆从左到右为 25 号犀牛、41 号猛虎、27 号犀牛。本工具以磁暴坦克替换最右侧 27 号犀牛，形成“犀牛—猛虎—磁暴”展示。首轮实机反馈确认原 X=1780 的右车会被常驻 UI 遮挡；当前候选把三车世界接地点重排为 X=`600 / 1010 / 1420`，中心间距统一为410。

地图消费者使用 E3 遮挡修正版的水平姿态。可继续加工的 SVG 和经验文档归档在 `flashswf/arts/new/Codex素材源稿/磁暴坦克G08/`；地图从 SVG 派生无位图、无子引用的单帧原生矢量 Graphic，不导入完整 P22 动态 FLA、AS3 控制器、俯仰姿态或履带动画。

转换器来自 G08 包内已经审阅的 `native_vector` 模块，固定依赖见 [requirements-vector.txt](requirements-vector.txt)。直接由 Animate 导入会膨胀为 5487 个元件、约 365MB，禁止作为地图闭包；当前确定性派生为 8302 个 Shape、138 个 LinearGradient、10847 个 Edge，单个 XML 约 6.9MB。

## 比例和摆放

参数真源为 [placements.json](placements.json)。首轮错误地拿27号犀牛“全外框×已退出场景的0.26倍率”与磁暴有效宽比较，导致磁暴实际达到现役猛虎约1.43倍。修正版统一采用车体口径：现役25号犀牛约 `1293.8 × 0.24 = 310.512px`，猛虎约 `1377.448 × 0.23 = 316.813px`；磁暴 E3 有效宽1063px，以 `0.329` 显示为约349.727px，即犀牛1.1263倍、猛虎1.1039倍。

磁暴坦克当前世界接地点为 `(1420,165)`，地图父偏移 `(-25,-80)`，实例位置 `(1445,245)`；以源图履带接地中点 `(720.5,903)` 注册。相比首轮接地点上移20px，使履带收进帐篷遮挡区。沿用后景 RGB 乘数0.86，仍在帐篷之后、地面之前。车辆位于外交地图行走区外，不新增碰撞、脚本或全局 linkage。

## 生成与验证

```powershell
tmp/tesla-vector-env-20260919/Scripts/python.exe -B -X utf8 tools/tesla-map-assets/build.py
tmp/tesla-vector-env-20260919/Scripts/python.exe -B -X utf8 tools/tesla-map-assets/build.py --check
python scripts/tools/xfl/audit.py flashswf/levels/地图-军阀基地
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/levels/地图-军阀基地/地图-军阀基地.xfl" -PublishOnly -VerifySwf "flashswf/levels/地图-军阀基地.swf" -TimeoutSeconds 180
```

当前比例及遮挡修正版在合并上游后的最终树由真实 Flash CS6 发布，新鲜 Compiler Errors为0/0，SWF刷新为1,637,130 bytes。8302 Shape超过试行预算的单状态2000复核线，因此该通过只证明单张静态地图可编译，不外推到动态坦克或20辆同屏。最终比例、帐篷遮挡、三车构图和实际运行画质已由用户验收通过。
