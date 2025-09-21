// ========== 集中管理的import语句 ==========
// 所有装备函数文件共享的类库引用
import org.flashNight.gesh.object.*;
import org.flashNight.neur.Event.*;
import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.camera.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.unit.Action.Regeneration.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.sara.util.*;
import org.flashNight.naki.DataStructures.*;
import flash.geom.ColorTransform;
import flash.filters.*;

// ========== 装备函数文件include列表 ==========
#include "../逻辑/装备函数/外观类挂载.as"
#include "../逻辑/装备函数/红外夜视仪.as"
#include "../逻辑/装备函数/电感切割刃.as"
#include "../逻辑/装备函数/炎魔斩new.as"
#include "../逻辑/装备函数/死者之手.as"

#include "../逻辑/装备函数/斩马刀.as"
#include "../逻辑/装备函数/烈焰斩马刀.as"

#include "../逻辑/装备函数/键盘镰刀.as"
#include "../逻辑/装备函数/吉他喷火.as"
#include "../逻辑/装备函数/主唱光剑.as"
#include "../逻辑/装备函数/火药燃气液压打桩机.as"
#include "../逻辑/装备函数/刀口触发特效.as"
#include "../逻辑/装备函数/XM25.as"
#include "../逻辑/装备函数/XM556_Microgun.as"
#include "../逻辑/装备函数/XM556-OC-Overlord.as"
#include "../逻辑/装备函数/XM556_H_Stinger.as"
#include "../逻辑/装备函数/NEGEV.as"
#include "../逻辑/装备函数/M249.as"
#include "../逻辑/装备函数/Jackhammer.as"
#include "../逻辑/装备函数/G11.as"
#include "../逻辑/装备函数/G111.as"
#include "../逻辑/装备函数/G1111.as"
#include "../逻辑/装备函数/XM214-CageFrame.as"
#include "../逻辑/装备函数/M134.as"
#include "../逻辑/装备函数/M134暴力版.as"
#include "../逻辑/装备函数/wa90变形款.as"
#include "../逻辑/装备函数/镜之虎彻.as"
#include "../逻辑/装备函数/铁枪.as"
#include "../逻辑/装备函数/黑铁的剑.as"
#include "../逻辑/装备函数/僵尸割草机.as"
#include "../逻辑/装备函数/混凝土切割机.as"
#include "../逻辑/装备函数/MACSIII.as"
#include "../逻辑/装备函数/等离子切割机.as"

#include "../逻辑/装备函数/P90.as"
#include "../逻辑/装备函数/AR57.as"

#include "../逻辑/装备函数/GM6_LYNX.as"