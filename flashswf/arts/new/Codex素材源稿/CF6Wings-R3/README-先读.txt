CF6 Wings873：R3 亮面材质精修候选

本轮变化
R2冻结保留。本轮只调整材质与光照表达，保留其比例、剪裁、身体构造、两种手套视角、枪刃设计及全部原注册矩阵。
- 深蓝贴身服：连续、较低亮度的大面转折，加外上胸和上臂随曲面弯折的短反射带，不用两颗独立白色圆光点。
- 腰部、淡紫腿面：更柔和的连续过渡；腰侧与胸下仍有连续暗面，淡紫表面不作金属处理。
- 长靴：沿小腿和脚背走向的长窄反光，保留膝踝褶皱和鞋型。
- 手套与腰包：反差和高光更低，保持指节/拳背视角与布缝结构，不与躯干同样发亮。
- 护目筒、枪刃：更明确的暗反射带、窄亮边和钢刃反光，设计、握点和双持关系不变。
材质判断是从原图推断渲染意图，不能凭图断言服装真实由乳胶、皮革或金属制成。详见MATERIAL-NOTES.txt。

素材范围
11件身体/头部及自有枪刃855，共12件可编辑SVG。使用SVG渐变与曲线透明描边组织亮面，无嵌入光照位图、无模糊滤镜。
原图集、原Shape855、原时间轴完整保留，R2的12件SVG与站姿也冻结为对照。
共用烟火503–505、挥斩864/865/867及血/受击特效仍原样复用；带共用特效的整套装配并非全纯矢量。

审图入口
- previews/original-r2-r3-stand.png：原/R2/R3同尺度全身。
- previews/original-r2-r3-head-torso.png：头、胸腰材质对照。
- previews/original-r2-r3-limbs.png：上臂、腕套、大腿、长靴和脚背。
- previews/original-r2-r3-glove-views.png：857横叠手指与859拳背视角。
- previews/head-torso-original-r3.png：原/R3真彩重点大图。
- previews/weapon855-original-r3.png：原/R3枪刃。
- previews/live-actions-original-r3.png、death-original-r3.png：原/R3关键动作。
- previews/joints-grips-original-r3.png：站姿肩肘腕/握柄、走4髋膝、攻2帧36举臂、死亡66髋膝。
- previews/*.gif及qa/contact-*.png：全部动作和死亡分支。
交付为两个普通独立ZIP，均小于15,000,000字节：cf6-wings-redraw-r3.zip源包与cf6-wings-redraw-r3-detail-review.zip重点审图包。三代对照、全部身体分件原新对照与接缝放大在审图包直接可看；源包独立重建也会生成全部图片。不是压缩分卷，无须拼接。

静态检查范围
861站15、862走18、863攻1 40、868攻2 49、869受击25、870被抓13、871倒65、872死亡132，共357帧。
12件替换保留原viewBox、图集→形状矩阵及原裁切；透明轮廓延续R2亚像素矢量近似。详细检查结果见qa/verification.json。
每个候选帧均渲染检查非空、不触碰动作固定画布边缘；13张contact显示全部357帧，不能用关键帧或死亡差集代替全量覆盖。
受击a0/a1分开；死亡a0=1–58、a1=59–95、a2=96–132分开。GIF速度用于审图，不代表游戏计时。

验收边界
美术仍为待用户认可的材质候选。结构检查、父级视觉抽查与用户美术认可分别记录。
没有运行EXE、SWF或ActionScript，没有修改生产工程，没有占用用户Windows。
未验证CS6接入、实际游戏播放、脚本停帧/分支/循环、碰撞伤害、动态挂点或声音。静态覆盖不等于CS6/游戏验收。
R3特别需要在实际转换链中检查SVG渐变、透明描边、clipPath和镜像后的观感；不可仅因Inkscape正确就宣称Flash接入通过。

重建
依赖Python 3、Pillow、NumPy、Inkscape命令行。
完整重建：python source/rebuild.py
仅重建12件SVG：python source/rebuild.py --assets-only
只需本包reference；不依赖外部R2文件夹或原EXE/SWF。全部逐帧SVG/PNG未装进ZIP以控制体积，重建会生成qa/frames、对照、GIF和检查报告。
冷重建实际结果见qa/cold-rebuild.json。

审图压缩
仅动作总览和contact为256色，全部材质/三代/分件/接缝重点图保留真彩，GIF为128色。渐变在小型动作预览中可能有轻微色阶；材质判断请看真彩重点图、SVG或逐帧真彩PNG。
