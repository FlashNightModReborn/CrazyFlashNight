/* 
  events.js
  负责绑定事件，以及事件处理逻辑
*/

/** 初始化所有事件绑定 */
window.bindEventHandlers = function () {

    // 1) 导入 units.json
    const unitsInput = document.getElementById("unitsloader");
    unitsInput.addEventListener("change", handleUnitsFileChange);
  
    // 2) StageInfo 交互
    const stageInfoContainer = document.getElementById('stage-info-container');
    stageInfoContainer.addEventListener("input", (e) => {
      const target = e.target;
      switch (target.id) {
        case 'StageInfo_Name':
          window.editorData.StageInfo.Name = target.value;
          break;
        case 'StageInfo_UnlockCondition':
          window.editorData.StageInfo.UnlockCondition = parseInt(target.value) || 0;
          break;
        case 'StageInfo_Description':
          window.editorData.StageInfo.Description = target.value;
          break;
        default:
          break;
      }
    });
  
    // 3) Rewards 相关事件
    document.getElementById('btn-add-reward').addEventListener('click', () => {
      const reward = { Name: "", AcquisitionProbability: 1, QuantityMax: 1 };
      window.editorData.Rewards.push(reward);
      window.renderRewards(); // 只渲染奖励区
    });
  
    const rewardsContainer = document.getElementById('Rewards');
    rewardsContainer.addEventListener('input', (e) => {
      const target = e.target;
      const index = target.getAttribute('data-reward-index');
      const field = target.getAttribute('data-reward-field');
      if (index !== null && field) {
        const newVal = (field === 'AcquisitionProbability' || field === 'QuantityMax')
          ? parseInt(target.value) || 0
          : target.value;
        window.editorData.Rewards[index][field] = newVal;
      }
    });
    rewardsContainer.addEventListener('click', (e) => {
      const target = e.target;
      if (target.getAttribute('data-action') === 'remove-reward') {
        const index = target.getAttribute('data-reward-index');
        window.editorData.Rewards.splice(index, 1);
        window.renderRewards();
      }
    });
  
    // 4) 子关卡添加
    document.getElementById('btn-add-substage').addEventListener('click', () => {
      const newStage = {
        id: window.editorData.SubStages.length,
        BasicInformation: {
          Background: "flashswf/backgrounds/",
          Animation: { enabled: false, Path: "", Pause: 0, Load: 1 },
          PlayerPosition: { enabled: false, X: 0, Y: 0 }
        },
        SpawnPoints: [],
        Wave: {
          SubWaves: [{
            id: 0,
            WaveInformation: { Duration: 0, FinishRequirement: null },
            EnemyGroup: []
          }]
        },
        Instances: []
      };
      window.editorData.SubStages.push(newStage);
      window.renderSubStages();
    });
  
    // 子关卡的各种操作（事件委托）
    const subStagesContainer = document.getElementById('SubStages');
    subStagesContainer.addEventListener('change', handleSubStageChange);
    subStagesContainer.addEventListener('click', handleSubStageClick);
    subStagesContainer.addEventListener('input', handleSubStageInput);
  
    // 5) 生成XML
    document.getElementById('btn-generate-xml').addEventListener('click', () => {
      const xml = generateXML();
      document.getElementById('output').textContent = xml;
    });

    // 6) 复制XML
    document.getElementById('btn-copy-xml').addEventListener('click', handleCopyXML);
  };
  
  // ============ 具体处理函数 ============
  
  // 1) 读取units.json文件
  function handleUnitsFileChange() {
    const file = this.files[0];
    if (!file) return;
  
    const reader = new FileReader();
    reader.onload = function () {
      window.unitsDict = {};
      const rawUnitsArray = JSON.parse(this.result);
      rawUnitsArray.forEach((unit) => {
        window.unitsDict[unit.id] = unit;
      });
      window.renderSubStages(); // 新增此行
    };
    
    reader.readAsText(file);
  }
  
  // 2) 子关卡处理
  function handleSubStageChange(e) {
    const target = e.target;
    const stageIndex = parseInt(target.getAttribute('data-stage-index') || -1);
  
    // 2.1 Animation or PlayerPosition Checkbox
    if (target.getAttribute('data-field') === 'hasAnimation') {
      window.editorData.SubStages[stageIndex].BasicInformation.Animation.enabled = target.checked;
      window.renderSubStages(); // 重新渲染
      return;
    } 
    if (target.getAttribute('data-field') === 'hasPlayerPos') {
      window.editorData.SubStages[stageIndex].BasicInformation.PlayerPosition.enabled = target.checked;
      window.renderSubStages();
      return;
    }
  
    // 2.2 Animation.Load 下拉
    if (target.getAttribute('data-field') === 'Animation.Load') {
      window.editorData.SubStages[stageIndex].BasicInformation.Animation.Load = parseInt(target.value) || 0;
      return;
    }
  
    // 2.3 Animation.Pause
    if (target.getAttribute('data-field') === 'Animation.Pause') {
      window.editorData.SubStages[stageIndex].BasicInformation.Animation.Pause = target.checked ? 1 : 0;
      return;
    }
  }
  
  function handleSubStageClick(e) {
    const target = e.target;
    const action = target.getAttribute('data-action');
    if (!action) return;
  
    switch (action) {
      case 'remove-substage':
        {
          const stageIndex = parseInt(target.getAttribute('data-stage-index'));
          window.editorData.SubStages.splice(stageIndex, 1);
          // 重排id
          window.editorData.SubStages.forEach((s, i) => s.id = i);
          window.renderSubStages();
        }
        break;
  
      case 'add-subwave':
        {
          const stageIndex = parseInt(target.getAttribute('data-stage-index'));
          const subWaves = window.editorData.SubStages[stageIndex].Wave.SubWaves;
          subWaves.push({
            id: subWaves.length,
            WaveInformation: { Duration: 0, FinishRequirement: null },
            EnemyGroup: []
          });
          window.renderSubStages();
        }
        break;
  
      case 'remove-subwave':
        {
          const stageIndex = parseInt(target.getAttribute('data-stage-index'));
          const subIndex = parseInt(target.getAttribute('data-subwave-index'));
          window.editorData.SubStages[stageIndex].Wave.SubWaves.splice(subIndex, 1);
          window.renderSubStages();
        }
        break;
  
      case 'add-enemy':
        {
          const stageIndex = parseInt(target.getAttribute('data-stage-index'));
          const subIndex = parseInt(target.getAttribute('data-subwave-index'));
          const enemies = window.editorData.SubStages[stageIndex].Wave.SubWaves[subIndex].EnemyGroup;
          enemies.push({
            Type: 0,
            Interval: 100,
            Quantity: 1,
            Level: 1,
            Parameters: {}
          });
          window.renderSubStages();
        }
        break;
  
      // XML Param
      case 'remove-xml-param':
        {
          const stageIndex = parseInt(target.getAttribute('data-stage-index'));
          const subIndex = parseInt(target.getAttribute('data-subwave-index'));
          const enemyIndex = parseInt(target.getAttribute('data-enemy-index'));
          const key = target.getAttribute('data-key');
          delete window.editorData.SubStages[stageIndex]
            .Wave.SubWaves[subIndex]
            .EnemyGroup[enemyIndex]
            .Parameters[key];
          window.renderSubStages();
        }
        break;
  
      case 'add-xml-param':
        {
          const stageIndex = parseInt(target.getAttribute('data-stage-index'));
          const subIndex = parseInt(target.getAttribute('data-subwave-index'));
          const enemyIndex = parseInt(target.getAttribute('data-enemy-index'));
          const params = window.editorData.SubStages[stageIndex]
            .Wave.SubWaves[subIndex]
            .EnemyGroup[enemyIndex]
            .Parameters;
          const newKey = `参数${Object.keys(params).length + 1}`;
          params[newKey] = "";
          window.renderSubStages();
        }
        break;
  
      default:
        break;
    }
  }
  
  function handleSubStageInput(e) {
    const target = e.target;
    const stageIndex = parseInt(target.getAttribute('data-stage-index') || -1);
    const subwaveIndex = parseInt(target.getAttribute('data-subwave-index') || -1);
    const enemyIndex = parseInt(target.getAttribute('data-enemy-index') || -1);
  
    // 背景路径、动画路径等
    const field = target.getAttribute('data-field');
    if (field) {
      // 形如 "BasicInformation.Animation.Path" or "BasicInformation.PlayerPosition.X"
      window.setNestedField(
        window.editorData.SubStages[stageIndex],
        field,
        target.type === 'number' ? parseInt(target.value) || 0 : target.value
      );
      return;
    }
  
    // 子波次 WaveInformation
    const waveField = target.getAttribute('data-wave-field');
    if (waveField) {
      const waveInfo = window.editorData.SubStages[stageIndex]
        .Wave.SubWaves[subwaveIndex]
        .WaveInformation;
      if (waveField === 'Duration') {
        waveInfo.Duration = parseInt(target.value) || 0;
      } else if (waveField === 'FinishRequirement') {
        waveInfo.FinishRequirement = target.value ? parseInt(target.value) : null;
      }
      return;
    }
  
    // 敌人字段
    const enemyField = target.getAttribute('data-enemy-field');
    if (enemyField) {
      const enemy = window.editorData.SubStages[stageIndex]
        .Wave.SubWaves[subwaveIndex]
        .EnemyGroup[enemyIndex];
      if (enemyField === 'Type') {
        enemy.Type = parseInt(target.value) || 0;
        // 兵种变化后，需要重渲染以更新UI显示
        window.renderSubStages();
      } else if (['Interval', 'Quantity', 'Level'].includes(enemyField)) {
        enemy[enemyField] = parseInt(target.value) || 0;
      }
      return;
    }
  
    // XML参数
    const action = target.getAttribute('data-action');
    if (action === 'update-xml-param-key') {
      const oldKey = target.getAttribute('data-old-key');
      const newKey = target.value;
      const params = window.editorData.SubStages[stageIndex]
        .Wave.SubWaves[subwaveIndex]
        .EnemyGroup[enemyIndex]
        .Parameters;
      params[newKey] = params[oldKey];
      delete params[oldKey];
      window.renderSubStages();
    } else if (action === 'update-xml-param-value') {
      const paramKey = target.getAttribute('data-key');
      const val = target.value;
      const params = window.editorData.SubStages[stageIndex]
        .Wave.SubWaves[subwaveIndex]
        .EnemyGroup[enemyIndex]
        .Parameters;
      params[paramKey] = val;
    }
  }
  
  // 3) 生成总XML
  function generateXML() {
    const { StageInfo, Rewards, SubStages } = window.editorData;
    let xml = `<?xml version='1.0' encoding='utf-8'?>\n<GameStage>\n`;
  
    // === StageInfo ===
    xml += `  <StageInfo>\n`;
    xml += `    <Type>${StageInfo.Type}</Type>\n`;
    xml += `    <Name>${window.escapeXml(StageInfo.Name)}</Name>\n`;
    xml += `    <FadeTransitionFrame>${StageInfo.FadeTransitionFrame}</FadeTransitionFrame>\n`;
    xml += `    <UnlockCondition>${StageInfo.UnlockCondition}</UnlockCondition>\n`;
    xml += `    <Description>${window.escapeXml(StageInfo.Description)}</Description>\n`;
    xml += `  </StageInfo>\n`;
  
    // === Rewards ===
    xml += `  <Rewards>`;
    Rewards.forEach(reward => {
      xml += `
      <Reward>
        <Name>${window.escapeXml(reward.Name)}</Name>
        <AcquisitionProbability>${reward.AcquisitionProbability}</AcquisitionProbability>
        <QuantityMax>${reward.QuantityMax}</QuantityMax>
      </Reward>`;
    });
    xml += '\n  </Rewards>\n';
  
    // === SubStages ===
    SubStages.forEach(subStage => {
      xml += generateSubStageXML(subStage);
    });
  
    xml += `</GameStage>`;
    return xml;
  }
  
  function generateSubStageXML(stage) {
    let xml = `  <SubStage id="${stage.id}">\n`;
  
    // BasicInformation
    xml += `    <BasicInformation>\n`;
    xml += `      <Background>${stage.BasicInformation.Background}</Background>\n`;
  
    if (stage.BasicInformation.Animation.enabled) {
      xml += `      <Animation>\n`;
      xml += `        <Path>${stage.BasicInformation.Animation.Path}</Path>\n`;
      xml += `        <Pause>${stage.BasicInformation.Animation.Pause}</Pause>\n`;
      xml += `        <Load>${stage.BasicInformation.Animation.Load}</Load>\n`;
      xml += `      </Animation>\n`;
    }
    if (stage.BasicInformation.PlayerPosition.enabled) {
      xml += `      <PlayerX>${stage.BasicInformation.PlayerPosition.X}</PlayerX>\n`;
      xml += `      <PlayerY>${stage.BasicInformation.PlayerPosition.Y}</PlayerY>\n`;
    }
    xml += `    </BasicInformation>\n`;
  
    // 生成出生点XML
    if(stage.SpawnPoints.length > 0) {
      xml += `    <SpawnPoint>\n`;
      stage.SpawnPoints.forEach(point => {
          xml += `      <Point id="${point.id}">\n`;
          xml += `        <x>${point.x}</x>\n`;
          xml += `        <y>${point.y}</y>\n`;
          if(point.Bias) {
              xml += `        <BiasX>${point.BiasX}</BiasX>\n`;
              xml += `        <BiasY>${point.BiasY}</BiasY>\n`;
          }
          xml += `      </Point>\n`;
      });
      xml += `    </SpawnPoint>\n`;
  }
  
    // Wave
    xml += `    <Wave>\n`;
    stage.Wave.SubWaves.forEach(subwave => {
      xml += `      <SubWave id="${subwave.id}">\n`;
      xml += `        <WaveInformation>\n`;
      xml += `          <Duration>${subwave.WaveInformation.Duration}</Duration>\n`;
      if (subwave.WaveInformation.FinishRequirement !== null) {
        xml += `          <FinishRequirement>${subwave.WaveInformation.FinishRequirement}</FinishRequirement>\n`;
      }
      xml += `        </WaveInformation>\n`;
  
      xml += `        <EnemyGroup>\n`;
      subwave.EnemyGroup.forEach(enemy => {
        xml += `          <Enemy>\n`;
        xml += `            <Type>兵种${enemy.Type}</Type>\n`;
        xml += `            <Interval>${enemy.Interval}</Interval>\n`;
        xml += `            <Quantity>${enemy.Quantity}</Quantity>\n`;
        xml += `            <Level>${enemy.Level}</Level>\n`;
  
        const paramKeys = Object.keys(enemy.Parameters);
        if (paramKeys.length > 0) {
          xml += `            <Parameters>\n`;
          paramKeys.forEach(k => {
            xml += `              <${k}>${window.escapeXml(enemy.Parameters[k])}</${k}>\n`;
          });
          xml += `            </Parameters>\n`;
        }
  
        xml += `          </Enemy>\n`;
      });
      xml += `        </EnemyGroup>\n`;
  
      xml += `      </SubWave>\n`;
    });
    xml += `    </Wave>\n`;
  
    xml += `  </SubStage>\n`;
    return xml;
  }
    
  function handleCopyXML() {
    const output = document.getElementById('output');
    const text = output.textContent;
    if (text) {
      navigator.clipboard.writeText(text).then(() => {
        alert('XML已复制到剪贴板！');
      }).catch(err => {
        console.error('复制失败:', err);
        alert('复制失败，请手动复制。');
      });
    } else {
      alert('请先生成XML内容！');
    }
  }