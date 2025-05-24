/* 
  dataStore.js
  存放编辑器的核心数据 
  以及加载到的units字典 (unitsDict)
*/

// 用于记录当前编辑器的所有关卡配置
window.editorData = {
    StageInfo: {
      Type: "无限过图",
      Name: "摇滚公园",
      FadeTransitionFrame: "wuxianguotu_1",
      UnlockCondition: 27,
      Description: "盗贼组织“狂野玫瑰”的大本营..."
    },
    Rewards: [],
    SubStages: []
  };
  
  // 用于记录从 units.json 解析出的信息
  // 结构示例：unitsDict[id] = { id, name, spritename, is_hostile }
  window.unitsDict = {};
  