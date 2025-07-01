org.flashNight.naki.DataStructures.BitArrayTest.runAll();

================================================================================
🚀 BitArray 完整测试套件启动 (高性能版)
================================================================================

🔧 初始化测试数据...
📦 创建了小型(64位)、大型(1024位)、模式(32位)、空BitArray

📋 执行基础功能测试...
✅ 构造函数创建64位数组 PASS (object is not null)
✅ 构造函数设置长度 PASS (expected=64, actual=64)
✅ 构造函数初始为空 PASS
✅ 构造函数创建0位数组 PASS (object is not null)
✅ 0位数组长度 PASS (expected=0, actual=0)
✅ 0位数组为空 PASS
✅ 构造函数创建大数组 PASS (object is not null)
✅ 大数组长度正确 PASS (expected=1000, actual=1000)
✅ 大数组初始为空 PASS
✅ 32位边界数组长度 PASS (expected=32, actual=32)
✅ 33位跨块数组长度 PASS (expected=33, actual=33)
✅ 负数长度处理 PASS (expected=0, actual=0)
✅ undefined长度处理 PASS (expected=0, actual=0)
✅ 设置位0为1 PASS (bit=1)
✅ 未设置位1为0 PASS (bit=0)
✅ 设置位5为1 PASS (bit=1)
✅ 设置位15为1 PASS (bit=1)
✅ 设置位5为0 PASS (bit=0)
✅ 翻转位0从1到0 PASS (bit=0)
✅ 翻转位0从0到1 PASS (bit=1)
✅ 翻转未设置位10从0到1 PASS (bit=1)
✅ 获取超出范围位返回0 PASS (bit=0)
✅ 获取负索引位返回0 PASS (bit=0)
✅ 小数组长度 PASS (expected=64, actual=64)
✅ 大数组长度 PASS (expected=1024, actual=1024)
✅ 空数组长度 PASS (expected=0, actual=0)
✅ 空数组isEmpty PASS
✅ 未设置位的数组isEmpty PASS
✅ 新创建数组isEmpty PASS
✅ 设置位后非isEmpty PASS
✅ 清除唯一位后isEmpty PASS
✅ 扩展前长度 PASS (expected=10, actual=10)
✅ 自动扩展后长度 PASS (expected=51, actual=51)
✅ 扩展后设置的位 PASS (bit=1)
✅ 原有位未受影响 PASS (bit=0)
✅ 翻转扩展后长度 PASS (expected=101, actual=101)
✅ 翻转扩展的位 PASS (bit=1)
✅ 负索引不扩展 PASS (expected=101, actual=101)

🔧 执行位操作算法测试...
✅ 清空前非空 PASS
✅ 清空后为空 PASS
✅ 清空后countOnes为0 PASS (expected=0, actual=0)
✅ 清空后位0为0 PASS (bit=0)
✅ 清空后位1为0 PASS (bit=0)
✅ 清空后位2为0 PASS (bit=0)
✅ 清空后位3为0 PASS (bit=0)
✅ 清空后位4为0 PASS (bit=0)
✅ 清空后位5为0 PASS (bit=0)
✅ 清空后位6为0 PASS (bit=0)
✅ 清空后位7为0 PASS (bit=0)
✅ 清空后位8为0 PASS (bit=0)
✅ 清空后位9为0 PASS (bit=0)
✅ 清空后位10为0 PASS (bit=0)
✅ 清空后位11为0 PASS (bit=0)
✅ 清空后位12为0 PASS (bit=0)
✅ 清空后位13为0 PASS (bit=0)
✅ 清空后位14为0 PASS (bit=0)
✅ 清空后位15为0 PASS (bit=0)
✅ 清空后位16为0 PASS (bit=0)
✅ 清空后位17为0 PASS (bit=0)
✅ 清空后位18为0 PASS (bit=0)
✅ 清空后位19为0 PASS (bit=0)
✅ 清空后位20为0 PASS (bit=0)
✅ 清空后位21为0 PASS (bit=0)
✅ 清空后位22为0 PASS (bit=0)
✅ 清空后位23为0 PASS (bit=0)
✅ 清空后位24为0 PASS (bit=0)
✅ 清空后位25为0 PASS (bit=0)
✅ 清空后位26为0 PASS (bit=0)
✅ 清空后位27为0 PASS (bit=0)
✅ 清空后位28为0 PASS (bit=0)
✅ 清空后位29为0 PASS (bit=0)
✅ 清空后位30为0 PASS (bit=0)
✅ 清空后位31为0 PASS (bit=0)
✅ setAll后非空 PASS
✅ setAll后countOnes等于长度 PASS (expected=32, actual=32)
✅ setAll后位0为1 PASS (bit=1)
✅ setAll后位1为1 PASS (bit=1)
✅ setAll后位2为1 PASS (bit=1)
✅ setAll后位3为1 PASS (bit=1)
✅ setAll后位4为1 PASS (bit=1)
✅ setAll后位5为1 PASS (bit=1)
✅ setAll后位6为1 PASS (bit=1)
✅ setAll后位7为1 PASS (bit=1)
✅ setAll后位8为1 PASS (bit=1)
✅ setAll后位9为1 PASS (bit=1)
✅ setAll后位10为1 PASS (bit=1)
✅ setAll后位11为1 PASS (bit=1)
✅ setAll后位12为1 PASS (bit=1)
✅ setAll后位13为1 PASS (bit=1)
✅ setAll后位14为1 PASS (bit=1)
✅ setAll后位15为1 PASS (bit=1)
✅ setAll后位16为1 PASS (bit=1)
✅ setAll后位17为1 PASS (bit=1)
✅ setAll后位18为1 PASS (bit=1)
✅ setAll后位19为1 PASS (bit=1)
✅ setAll后位20为1 PASS (bit=1)
✅ setAll后位21为1 PASS (bit=1)
✅ setAll后位22为1 PASS (bit=1)
✅ setAll后位23为1 PASS (bit=1)
✅ setAll后位24为1 PASS (bit=1)
✅ setAll后位25为1 PASS (bit=1)
✅ setAll后位26为1 PASS (bit=1)
✅ setAll后位27为1 PASS (bit=1)
✅ setAll后位28为1 PASS (bit=1)
✅ setAll后位29为1 PASS (bit=1)
✅ setAll后位30为1 PASS (bit=1)
✅ setAll后位31为1 PASS (bit=1)
✅ 大数组clear性能 PASS
✅ 大数组setAll性能 PASS
✅ 空数组countOnes PASS (expected=0, actual=0)
✅ 交替模式countOnes PASS (expected=32, actual=32)
✅ 单位countOnes PASS (expected=1, actual=1)
✅ 全1 countOnes PASS (expected=20, actual=20)
✅ 跨块countOnes PASS (expected=4, actual=4)
✅ 克隆结果不为null PASS (object is not null)
✅ 克隆长度相同 PASS (expected=32, actual=32)
✅ 克隆countOnes相同 PASS (expected=16, actual=16)
✅ 克隆位0相同 PASS (bit=1)
✅ 克隆位1相同 PASS (bit=1)
✅ 克隆位2相同 PASS (bit=1)
✅ 克隆位3相同 PASS (bit=1)
✅ 克隆位4相同 PASS (bit=0)
✅ 克隆位5相同 PASS (bit=0)
✅ 克隆位6相同 PASS (bit=0)
✅ 克隆位7相同 PASS (bit=0)
✅ 克隆位8相同 PASS (bit=1)
✅ 克隆位9相同 PASS (bit=1)
✅ 克隆位10相同 PASS (bit=0)
✅ 克隆位11相同 PASS (bit=0)
✅ 克隆位12相同 PASS (bit=1)
✅ 克隆位13相同 PASS (bit=1)
✅ 克隆位14相同 PASS (bit=0)
✅ 克隆位15相同 PASS (bit=0)
✅ 克隆位16相同 PASS (bit=1)
✅ 克隆位17相同 PASS (bit=0)
✅ 克隆位18相同 PASS (bit=1)
✅ 克隆位19相同 PASS (bit=0)
✅ 克隆位20相同 PASS (bit=1)
✅ 克隆位21相同 PASS (bit=0)
✅ 克隆位22相同 PASS (bit=1)
✅ 克隆位23相同 PASS (bit=0)
✅ 克隆位24相同 PASS (bit=0)
✅ 克隆位25相同 PASS (bit=1)
✅ 克隆位26相同 PASS (bit=0)
✅ 克隆位27相同 PASS (bit=1)
✅ 克隆位28相同 PASS (bit=0)
✅ 克隆位29相同 PASS (bit=1)
✅ 克隆位30相同 PASS (bit=0)
✅ 克隆位31相同 PASS (bit=1)
✅ 修改克隆不影响原数组 PASS (bit=1)
✅ 空数组克隆不为null PASS (object is not null)
✅ 空数组克隆长度 PASS (expected=0, actual=0)
✅ 空数组克隆为空 PASS
✅ 大数组克隆长度 PASS (expected=1024, actual=1024)
✅ 大数组克隆countOnes PASS (expected=512, actual=512)
✅ 空数组toString PASS
✅ 单位1 toString PASS ("1")
✅ 单位0 toString PASS ("0")
✅ 8位模式toString包含正确位 PASS
✅ toString结果不为null PASS (object is not null)
✅ toString长度合理 PASS
✅ getChunks返回不为null PASS (object is not null)
✅ getChunks返回数组 PASS
✅ 32位数组chunk数量 PASS (expected=1, actual=1)
✅ 64位数组chunk数量 PASS (expected=2, actual=2)
✅ 1024位数组chunk数量 PASS (expected=32, actual=32)
✅ getChunks返回副本 PASS (expected=-1437256945, actual=-1437256945)

🧠 执行逻辑运算测试...
✅ AND操作结果不为null PASS (object is not null)
✅ AND操作结果长度 PASS (expected=8, actual=8)
✅ AND位0 PASS (bit=0)
✅ AND位1 PASS (bit=0)
✅ AND位2 PASS (bit=0)
✅ AND位3 PASS (bit=0)
✅ AND位4 PASS (bit=0)
✅ AND位5 PASS (bit=0)
✅ AND位6 PASS (bit=1)
✅ AND位7 PASS (bit=1)
✅ 与自身AND PASS
✅ 与全0 AND结果为空 PASS
✅ OR操作结果不为null PASS (object is not null)
✅ OR操作结果长度 PASS (expected=8, actual=8)
✅ OR位0 PASS (bit=0)
✅ OR位1 PASS (bit=0)
✅ OR位2 PASS (bit=1)
✅ OR位3 PASS (bit=1)
✅ OR位4 PASS (bit=1)
✅ OR位5 PASS (bit=1)
✅ OR位6 PASS (bit=1)
✅ OR位7 PASS (bit=1)
✅ 与自身OR PASS
✅ 与全0 OR PASS
✅ XOR操作结果不为null PASS (object is not null)
✅ XOR操作结果长度 PASS (expected=8, actual=8)
✅ XOR位0 PASS (bit=0)
✅ XOR位1 PASS (bit=0)
✅ XOR位2 PASS (bit=1)
✅ XOR位3 PASS (bit=1)
✅ XOR位4 PASS (bit=1)
✅ XOR位5 PASS (bit=1)
✅ XOR位6 PASS (bit=0)
✅ XOR位7 PASS (bit=0)
✅ 与自身XOR结果为空 PASS
✅ XOR交换律 PASS
✅ NOT操作结果不为null PASS (object is not null)
✅ NOT操作结果长度 PASS (expected=8, actual=8)
✅ NOT位0 PASS (bit=1)
✅ NOT位1 PASS (bit=0)
✅ NOT位2 PASS (bit=1)
✅ NOT位3 PASS (bit=0)
✅ NOT位4 PASS (bit=1)
✅ NOT位5 PASS (bit=0)
✅ NOT位6 PASS (bit=1)
✅ NOT位7 PASS (bit=0)
✅ 双重NOT PASS
✅ 空数组NOT PASS
✅ 不同长度AND结果长度 PASS (expected=12, actual=12)
✅ 不同长度OR结果长度 PASS (expected=12, actual=12)
✅ 超出部分保持long数组值 PASS (bit=1)
✅ null运算不崩溃 PASS

🔍 执行边界条件测试...
✅ 空数组isLeaf PASS
✅ 空数组长度 PASS (expected=0, actual=0)
✅ 空数组countOnes PASS (expected=0, actual=0)
✅ 空数组clear后仍为空 PASS
✅ 空数组setAll后仍为空 PASS
✅ 空数组克隆为空 PASS
✅ 空数组AND空数组 PASS
✅ 空数组OR非空数组长度 PASS (expected=5, actual=5)
✅ 空数组OR非空数组保持原值 PASS (bit=1)
✅ 单位数组长度 PASS (expected=1, actual=1)
✅ 单位数组初始为空 PASS
✅ 单位数组初始位为0 PASS (bit=0)
✅ 设置后单位数组非空 PASS
✅ 设置后countOnes为1 PASS (expected=1, actual=1)
✅ 翻转后单位数组为空 PASS
✅ setAll后countOnes为1 PASS (expected=1, actual=1)
✅ 单位数组NOT后为空 PASS
✅ 第一块最后位 PASS (bit=1)
✅ 第二块第一位 PASS (bit=1)
✅ 数组第一位 PASS (bit=1)
✅ 数组最后位 PASS (bit=1)
✅ 超出边界访问返回0 PASS (bit=0)
✅ 负索引访问返回0 PASS (bit=0)
✅ 边界设置自动扩容 PASS (expected=101, actual=101)
✅ 边界扩容设置成功 PASS (bit=1)
✅ 极大索引扩容 PASS (expected=10001, actual=10001)
✅ 极大索引设置成功 PASS
✅ 非1值设置为1 PASS (bit=1)
✅ 负值设置为1 PASS (bit=1)
✅ 小数值设置 PASS (bit=1)
✅ NaN值设置 PASS (bit=0)
✅ undefined值设置 PASS (bit=0)

⚡ 执行优化的性能基准测试...
📊 基础位操作性能: 5000次操作耗时 53ms
✅ 基础位操作性能达标 PASS
📊 逻辑运算性能: 500次操作耗时 80ms
✅ 逻辑运算性能达标 PASS
📊 大数组操作性能: 50次操作(10000位)耗时 270ms
✅ 大数组操作性能达标 PASS
📊 内存密集操作性能: 20次操作耗时 101ms
✅ 内存密集操作性能合理 PASS

💾 执行数据完整性测试...
✅ 多次countOnes一致性 PASS (expected=16, actual=16)
✅ 多次getLength一致性 PASS (expected=32, actual=32)
✅ 多次isEmpty一致性 PASS
✅ 多次countOnes一致性 PASS (expected=16, actual=16)
✅ 多次getLength一致性 PASS (expected=32, actual=32)
✅ 多次isEmpty一致性 PASS
✅ 多次countOnes一致性 PASS (expected=16, actual=16)
✅ 多次getLength一致性 PASS (expected=32, actual=32)
✅ 多次isEmpty一致性 PASS
✅ 多次countOnes一致性 PASS (expected=16, actual=16)
✅ 多次getLength一致性 PASS (expected=32, actual=32)
✅ 多次isEmpty一致性 PASS
✅ 多次countOnes一致性 PASS (expected=16, actual=16)
✅ 多次getLength一致性 PASS (expected=32, actual=32)
✅ 多次isEmpty一致性 PASS
✅ 重复设置不改变countOnes PASS (expected=16, actual=16)
✅ 重复设置不改变位值 PASS (bit=0)
✅ 双重翻转恢复countOnes PASS (expected=16, actual=16)
✅ chunk数量正确 PASS (expected=3, actual=3)
✅ 修改后chunk1未变 PASS (expected=32768, actual=32768)
✅ 修改后chunk2未变 PASS (expected=32768, actual=32768)
✅ 修改后chunk0已变 PASS
✅ 扩容后原位2保持 PASS (bit=1)
✅ 扩容后原位7保持 PASS (bit=1)
✅ 扩容后countOnes增加1 PASS (expected=3, actual=3)
✅ 扩容中间位10为0 PASS (bit=0)
✅ 扩容中间位11为0 PASS (bit=0)
✅ 扩容中间位12为0 PASS (bit=0)
✅ 扩容中间位13为0 PASS (bit=0)
✅ 扩容中间位14为0 PASS (bit=0)
✅ 扩容中间位15为0 PASS (bit=0)
✅ 扩容中间位16为0 PASS (bit=0)
✅ 扩容中间位17为0 PASS (bit=0)
✅ 扩容中间位18为0 PASS (bit=0)
✅ 扩容中间位19为0 PASS (bit=0)
✅ 扩容中间位20为0 PASS (bit=0)
✅ 扩容中间位21为0 PASS (bit=0)
✅ 扩容中间位22为0 PASS (bit=0)
✅ 扩容中间位23为0 PASS (bit=0)
✅ 扩容中间位24为0 PASS (bit=0)
✅ 扩容中间位25为0 PASS (bit=0)
✅ 扩容中间位26为0 PASS (bit=0)
✅ 扩容中间位27为0 PASS (bit=0)
✅ 扩容中间位28为0 PASS (bit=0)
✅ 扩容中间位29为0 PASS (bit=0)
✅ 扩容中间位30为0 PASS (bit=0)
✅ 扩容中间位31为0 PASS (bit=0)
✅ 扩容中间位32为0 PASS (bit=0)
✅ 扩容中间位33为0 PASS (bit=0)
✅ 扩容中间位34为0 PASS (bit=0)
✅ 扩容中间位35为0 PASS (bit=0)
✅ 扩容中间位36为0 PASS (bit=0)
✅ 扩容中间位37为0 PASS (bit=0)
✅ 扩容中间位38为0 PASS (bit=0)
✅ 扩容中间位39为0 PASS (bit=0)
✅ 扩容中间位40为0 PASS (bit=0)
✅ 扩容中间位41为0 PASS (bit=0)
✅ 扩容中间位42为0 PASS (bit=0)
✅ 扩容中间位43为0 PASS (bit=0)
✅ 扩容中间位44为0 PASS (bit=0)
✅ 扩容中间位45为0 PASS (bit=0)
✅ 扩容中间位46为0 PASS (bit=0)
✅ 扩容中间位47为0 PASS (bit=0)
✅ 扩容中间位48为0 PASS (bit=0)
✅ 扩容中间位49为0 PASS (bit=0)
✅ AND操作后原数组未变 PASS
✅ OR操作后原数组未变 PASS
✅ XOR操作后原数组未变 PASS
✅ NOT操作后原数组未变 PASS
✅ Clone操作后原数组未变 PASS
✅ 修改操作结果后原数组未变 PASS

💪 执行优化的压力测试...
✅ 大量位操作压力测试通过 PASS
🧠 大量位操作测试: 10000次操作耗时 39ms
✅ 并发逻辑运算压力测试通过 PASS
⚡ 并发逻辑运算测试: 100次迭代耗时 432ms
✅ 扩展到100位 PASS (expected=100, actual=100)
✅ 扩展到500位 PASS (expected=500, actual=500)
✅ 扩展到1000位 PASS (expected=1000, actual=1000)
✅ 扩展到2000位 PASS (expected=2000, actual=2000)
✅ 极端扩展测试完成 PASS
✅ 极端扩展时间合理 PASS
🔥 极端扩展测试: 扩展到2000位，耗时 0ms
  内存管理进度: 10/50 周期，耗时 106ms
  内存管理进度: 20/50 周期，耗时 196ms
  内存管理进度: 30/50 周期，耗时 292ms
  内存管理进度: 40/50 周期，耗时 387ms
✅ 内存管理压力测试通过 PASS
🧠 内存管理测试: 50个周期，每周期20个数组，耗时 474ms

🧮 执行算法精度验证...
✅ 已知模式位0 PASS (bit=1)
✅ 已知模式位1 PASS (bit=0)
✅ 已知模式位2 PASS (bit=1)
✅ 已知模式位3 PASS (bit=0)
✅ 已知模式位4 PASS (bit=1)
✅ 已知模式位5 PASS (bit=1)
✅ 已知模式位6 PASS (bit=0)
✅ 已知模式位7 PASS (bit=0)
✅ 已知模式位8 PASS (bit=1)
✅ 已知模式位9 PASS (bit=1)
✅ 已知模式位10 PASS (bit=0)
✅ 已知模式位11 PASS (bit=0)
✅ 已知模式位12 PASS (bit=1)
✅ 已知模式位13 PASS (bit=0)
✅ 已知模式位14 PASS (bit=1)
✅ 已知模式位15 PASS (bit=0)
✅ 已知模式countOnes精度 PASS (expected=8, actual=8)
✅ 翻转后countOnes精度 PASS (expected=8, actual=8)
✅ 翻转位0精度 PASS (bit=0)
✅ 翻转位1精度 PASS (bit=1)

🧮 执行算法精度验证...
✅ AND位0精度 PASS (bit=0)
✅ OR位0精度 PASS (bit=1)
✅ XOR位0精度 PASS (bit=1)
✅ NOT位0精度 PASS (bit=0)
✅ AND位1精度 PASS (bit=0)
✅ OR位1精度 PASS (bit=0)
✅ XOR位1精度 PASS (bit=0)
✅ NOT位1精度 PASS (bit=1)
✅ AND位2精度 PASS (bit=0)
✅ OR位2精度 PASS (bit=1)
✅ XOR位2精度 PASS (bit=1)
✅ NOT位2精度 PASS (bit=1)
✅ AND位3精度 PASS (bit=0)
✅ OR位3精度 PASS (bit=1)
✅ XOR位3精度 PASS (bit=1)
✅ NOT位3精度 PASS (bit=0)
✅ AND位4精度 PASS (bit=0)
✅ OR位4精度 PASS (bit=1)
✅ XOR位4精度 PASS (bit=1)
✅ NOT位4精度 PASS (bit=1)
✅ AND位5精度 PASS (bit=0)
✅ OR位5精度 PASS (bit=1)
✅ XOR位5精度 PASS (bit=1)
✅ NOT位5精度 PASS (bit=1)
✅ AND位6精度 PASS (bit=0)
✅ OR位6精度 PASS (bit=1)
✅ XOR位6精度 PASS (bit=1)
✅ NOT位6精度 PASS (bit=0)
✅ AND位7精度 PASS (bit=1)
✅ OR位7精度 PASS (bit=1)
✅ XOR位7精度 PASS (bit=0)
✅ NOT位7精度 PASS (bit=0)
✅ 单位全0 countOnes精度 PASS (expected=0, actual=0)
✅ 单位全1 countOnes精度 PASS (expected=1, actual=1)
✅ 32位一半 countOnes精度 PASS (expected=16, actual=16)
✅ 32位全1 countOnes精度 PASS (expected=32, actual=32)
✅ 64位单个1 countOnes精度 PASS (expected=1, actual=1)
✅ 100位一半 countOnes精度 PASS (expected=50, actual=50)
✅ 跨块countOnes精度 PASS (expected=4, actual=4)
✅ toString结果不为null PASS (object is not null)
✅ toString包含1 PASS
✅ toString包含0 PASS
✅ 全0 toString结果合理 PASS
✅ 全1 toString包含1 PASS
✅ toString位0一致性 PASS
✅ toString位1一致性 PASS
✅ toString位2一致性 PASS
✅ toString位3一致性 PASS

================================================================================
📊 BitArray 测试结果汇总 (高性能版)
================================================================================
总测试数: 403
通过: 403 ✅
失败: 0 ❌
成功率: 100%
总耗时: 1465ms

⚡ 性能基准报告:
  Basic Bit Operations: 0.011ms/次 (5000次测试)
  Logical Operations: 0.16ms/次 (500次测试)
  Large Array Operations: 5.4ms/次 (50次测试)
  Memory Intensive Operations: 5.05ms/次 (20次测试)

🎯 测试覆盖范围:
  📋 基础功能: 构造函数, getBit/setBit/flipBit, 长度管理, 自动扩容
  🔧 位操作: clear/setAll, countOnes, clone, toString, getChunks
  🧠 逻辑运算: AND/OR/XOR/NOT, 交换律, 结合律验证
  🔍 边界条件: 空数组, 单位数组, 边界索引, 极值处理
  ⚡ 性能基准: 位操作速度, 逻辑运算, 大数组处理, 内存密集操作
  💾 数据完整性: 位状态一致性, 块数据完整性, 扩容数据保持
  💪 压力测试: 大量位操作, 并发逻辑运算, 极端扩容, 内存管理
  🧮 算法精度: 位操作精度, 逻辑运算精度, countOnes精度, 字符串转换

🚀 BitArray 核心特性:
  ✨ 高效的32位块存储机制
  ✨ 优化的位运算算法实现
  ✨ 自动扩容和内存管理
  ✨ 完整的逻辑运算支持
  ✨ 汉明重量快速计算

🎉 所有测试通过！BitArray 组件质量优秀！
================================================================================
