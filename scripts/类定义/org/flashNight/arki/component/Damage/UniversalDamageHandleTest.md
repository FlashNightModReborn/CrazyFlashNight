// UniversalDamageHandle 测试套件
trace("[TestLoader] start");

import org.flashNight.arki.component.Damage.*;

UniversalDamageHandleTest.runTests();


[TestLoader] start
===== UniversalDamageHandle 测试套件 =====
[PASS] 物理: 100*(300/600)=50
[PASS] undefined类型fallback物理: 200*1=200
[PASS] undefined类型: 友方颜色=2
[PASS] 空字符串fallback物理: 100*0.5=50
[PASS] 物理敌方: 颜色=1
[PASS] 物理友方: 颜色=2
[PASS] 真伤: 无视防御(999)和抗性(80), 损伤=150
[PASS] 真伤敌方: 颜色=3
[PASS] 真伤: EF_DMG_TYPE_LABEL(bit3)已设置
[PASS] 真伤敌方: isEnemy(bit7)已设置
[PASS] 真伤: efText='真'
[PASS] 真伤友方: 颜色=4
[PASS] 真伤友方: isEnemy位未设置
[PASS] 魔法专属抗性: 100*(100-20)/100=80
[PASS] 魔法回退基础抗性: 100*(100-30)/100=70
[PASS] 魔法默认抗性: 10+10/2=15, 100*85/100=85
[PASS] 魔法零抗性: 0不被误判, 100*(100/100)=100
[PASS] 魔法NaN抗性: fallback到20, 100*80/100=80
[PASS] 魔法负抗性: 增伤, 100*150/100=150
[PASS] 魔法抗性95: 不触发软上限, 1000*5/100=50
[PASS] 魔法抗性96: 软上限生效, rv=95.0909090909091
[PASS] 魔法抗性150: 恰好100%减免
[PASS] 魔法抗性200: 截断到100%, 零伤害
[PASS] 魔法抗性-2000: 夹取到-1000, 11倍增伤
[PASS] 魔法敌方: 颜色=5
[PASS] 魔法: EF_DMG_TYPE_LABEL(bit3)已设置
[PASS] 魔法敌方: isEnemy(bit7)已设置
[PASS] 魔法: efText='火'
[PASS] 魔法null属性: efText默认='能'
[PASS] 魔法null属性: 走默认抗性=15
[PASS] 破击魔法属性: phys=50 + magic=5 = 55
[PASS] 破击非魔法属性: phys=50 + bonus=25 = 75
[PASS] 破击无匹配抗性: 退化纯物理=50
[PASS] 破击无匹配: EF_CRUSH_LABEL位未设置
[PASS] 破击敌方: 颜色=1(物理色)
[PASS] 破击: EF_CRUSH_LABEL(bit4)已设置
[PASS] 破击: efText='电'
[PASS] 破击魔法属性: emoji=sparkle
[PASS] 破击非魔法属性: emoji=skull
[PASS] 破击零抗性: phys=100 + magic=10 = 110
[PASS] 破击零抗性: EF_CRUSH_LABEL仍设置
[PASS] 破击null属性: 默认'能', phys=100+bonus=30=130
[PASS] 防御力0: 无减伤, 损伤=100
[PASS] 破坏力0: 零伤害
[PASS] resistTbl为null: 默认抗性=20, 损伤=80

===== 性能基准 =====
  物理路径: 50000次 = 108ms (2160 ns/call)
  魔法路径: 50000次 = 153ms (3060 ns/call)
  真伤路径: 50000次 = 117ms (2340 ns/call)
  破击路径: 50000次 = 236ms (4720 ns/call)
  混合分布: 50000次 = 147ms (2940 ns/call)

===== 汇总: run=45 pass=45 fail=0 =====
[compile] done
