/* 
  render.js
  负责将 editorData 中的数据渲染到页面
  采用模块化方式，每个子模块单独封装函数
*/

// 主渲染入口：根据 editorData 更新所有UI
window.render = function () {
  renderStageInfo();
  renderRewards();
  renderSubStages();
};

// -----------------------------
// 1) 渲染 StageInfo
// -----------------------------
function renderStageInfo() {
  const container = document.getElementById('stage-info-container');
  const { StageInfo } = window.editorData;
  container.innerHTML = `
    <h2>关卡基本信息</h2>
        <div class="help-wrapper">
                    <button class="help-btn">?</button>
                    <div class="help-tooltip">待开发</div>
                </div>
    <div class="input-group">
      <label>关卡名称: 
        <input id="StageInfo_Name" value="${StageInfo.Name}" />
      </label>
    </div>
    <div>
      <label>解锁需要主线进度: 
        <input type="number" id="StageInfo_UnlockCondition" value="${StageInfo.UnlockCondition}" />
      </label>
    </div>
    <div>
      <label>关卡描述: 
        <textarea id="StageInfo_Description" style="width:300px;height:60px">${StageInfo.Description}</textarea>
      </label>
    </div>


    <!-- 固定参数: 仅做隐藏展示 -->
    <input type="hidden" id="StageInfo_Type" value="${StageInfo.Type}">
    <input type="hidden" id="StageInfo_FadeTransitionFrame" value="${StageInfo.FadeTransitionFrame}">
  `;
}

// -----------------------------
// 2) 渲染 Rewards
// -----------------------------

        // 渲染奖励列表
        function renderRewards() {
            const container = document.getElementById('Rewards');
            container.innerHTML = editorData.Rewards.map((reward, index) => {
                const probValid = !isNaN(reward.AcquisitionProbability) && reward.AcquisitionProbability > 0;
                const qtyValid = !isNaN(reward.QuantityMax) && reward.QuantityMax > 0;

                return `<div class="array-item">
                    <label>物品名：
                        <input value="${reward.Name}" placeholder="名称"
                            oninput="editorData.Rewards[${index}].Name = this.value">
                    </label>
                    <label class="validatable-field">
                        生成概率：1/
                        <input type="text" value="${reward.AcquisitionProbability}"
                            oninput="validateNumberInput(this, ${index}, 'AcquisitionProbability')"
                            class="${probValid ? '' : 'invalid'}">
                        <span class="error-msg">${probValid ? '' : '概率填写错误'}</span>
                    </label>
                    <label class="validatable-field">
                        最大数量：
                        <input type="text" value="${reward.QuantityMax}"
                            oninput="validateNumberInput(this, ${index}, 'QuantityMax')"
                            class="${qtyValid ? '' : 'invalid'}">
                        <span class="error-msg">${qtyValid ? '' : '数量填写错误'}</span>
                    </label>
                    <button onclick="editorData.Rewards.splice(${index},1); renderRewards()">-</button>
                </div>`;
            }).join('');
        }
// 新增验证函数
        function validateNumberInput(input, index, field) {
            const value = input.value.trim();
            const numericValue = parseInt(value);
            const isValid = !isNaN(numericValue) && numericValue > 0;

            // 更新数据模型
            editorData.Rewards[index][field] = isValid ? numericValue : value;

            // 实时更新样式
            input.classList.toggle('invalid', !isValid);
            input.nextElementSibling.style.display = isValid ? 'none' : 'inline';

            // 强制重新渲染以确保状态同步
            renderRewards();
        }

// -----------------------------
// 3) 渲染 SubStages（子关卡）
// -----------------------------
function renderSubStages() {
  const container = document.getElementById('SubStages');
  const { SubStages } = window.editorData;
  
  container.innerHTML = SubStages.map((stage, stageIndex) => renderSubStage(stage, stageIndex)).join('');
}

/**
 * 渲染单个子关卡
 * @param {Object} stage - 子关卡数据
 * @param {number} stageIndex - 子关卡索引
 * @returns {string} HTML字符串
 */
function renderSubStage(stage, stageIndex) {
  return `
    <div class="substage">
      <h3>
        子关卡 ${stage.id}
        <button data-action="remove-substage" data-stage-index="${stageIndex}">删除</button>
      </h3>
      <div class="section">
        ${ renderBasicInfo(stage, stageIndex) }
        ${ renderWave(stage, stageIndex) }
      </div>
    </div>
  `;
}

/**
 * 渲染子关卡的基本信息（背景、动画、玩家出生点）
 * @param {Object} stage - 子关卡数据
 * @param {number} stageIndex - 子关卡索引
 * @returns {string} HTML字符串
 */
function renderBasicInfo(stage, stageIndex) {
  return `
    <!-- 背景路径 -->
    <label>背景路径:
      <input 
        value="${stage.BasicInformation.Background || ''}"
        data-stage-index="${stageIndex}" 
        data-field="BasicInformation.Background"
      >
    </label>

    <!-- 动画可选参数 -->
    <label>
      <input 
        type="checkbox" 
        data-stage-index="${stageIndex}" 
        data-field="hasAnimation" 
        ${ stage.BasicInformation.Animation.enabled ? 'checked' : '' }
      >
      包含动画
    </label>
    <div class="nested" style="display:${ stage.BasicInformation.Animation.enabled ? 'block' : 'none' }">
      <label>动画路径:
        <input 
          value="${stage.BasicInformation.Animation.Path}"
          data-stage-index="${stageIndex}" 
          data-field="Animation.Path"
        >
      </label>
      <label>暂停游戏:
        <input 
          type="checkbox"
          ${ stage.BasicInformation.Animation.Pause ? 'checked' : '' }
          data-stage-index="${stageIndex}"
          data-field="Animation.Pause"
        >
      </label>
      <label>加载时机:
        <select 
          data-stage-index="${stageIndex}"
          data-field="Animation.Load"
        >
          <option value="1" ${ stage.BasicInformation.Animation.Load === 1 ? 'selected' : '' }>进图时</option>
          <option value="0" ${ stage.BasicInformation.Animation.Load === 0 ? 'selected' : '' }>结束时</option>
        </select>
      </label>
    </div>

    <!-- 玩家出生点可选参数 -->
    <label>
      <input 
        type="checkbox" 
        data-stage-index="${stageIndex}"
        data-field="hasPlayerPos"
        ${ stage.BasicInformation.PlayerPosition.enabled ? 'checked' : '' }
      >
      设置玩家出生点
    </label>
    <div class="nested" style="display:${ stage.BasicInformation.PlayerPosition.enabled ? 'block' : 'none' }">
      <label>X坐标:
        <input 
          type="number" 
          value="${stage.BasicInformation.PlayerPosition.X}" 
          data-stage-index="${stageIndex}"
          data-field="PlayerPosition.X"
        >
      </label>
      <label>Y坐标:
        <input 
          type="number" 
          value="${stage.BasicInformation.PlayerPosition.Y}"
          data-stage-index="${stageIndex}"
          data-field="PlayerPosition.Y"
        >
      </label>
    </div>
  `;
}

/**
 * 渲染子关卡的波次信息（包括所有子波次）
 * @param {Object} stage - 子关卡数据
 * @param {number} stageIndex - 子关卡索引
 * @returns {string} HTML字符串
 */
function renderWave(stage, stageIndex) {
  let html = `
    <h4>敌人波次 
      <button data-action="add-subwave" data-stage-index="${stageIndex}">+子波次</button>
    </h4>
  `;
  html += stage.Wave.SubWaves.map((subwave, subIndex) => renderSubWave(subwave, stageIndex, subIndex)).join('');
  return html;
}

/**
 * 渲染单个子波次，包括波次信息和敌人列表
 * @param {Object} subwave - 子波次数据
 * @param {number} stageIndex - 所属子关卡索引
 * @param {number} subIndex - 子波次索引
 * @returns {string} HTML字符串
 */
function renderSubWave(subwave, stageIndex, subIndex) {
  return `
    <div class="subwave section">
      <h5>子波次 ${subIndex}
        <button data-action="remove-subwave" data-stage-index="${stageIndex}" data-subwave-index="${subIndex}">×</button>
      </h5>
      <div class="wave-info">
        <label>自动通过波次所需时间:
          <input 
            type="number" 
            value="${subwave.WaveInformation.Duration}"
            placeholder="未使用时填写0"
            data-stage-index="${stageIndex}"
            data-subwave-index="${subIndex}"
            data-wave-field="Duration"
          >
        </label>
        <label>通过波次所需剩余敌人数:
          <input 
            type="number"
            value="${subwave.WaveInformation.FinishRequirement || ''}"
            placeholder="未使用时留空"
            data-stage-index="${stageIndex}"
            data-subwave-index="${subIndex}"
            data-wave-field="FinishRequirement"
          >
        </label>
      </div>
      ${ renderEnemyGroup(subwave.EnemyGroup, stageIndex, subIndex) }
    </div>
  `;
}

/**
 * 渲染敌人组（多个敌人）
 * @param {Array} enemyGroup - 敌人列表
 * @param {number} stageIndex - 所属子关卡索引
 * @param {number} subIndex - 所属子波次索引
 * @returns {string} HTML字符串
 */
function renderEnemyGroup(enemyGroup, stageIndex, subIndex) {
  let html = `
    <div class="enemy-group">
      <h6>敌人列表 
        <button data-action="add-enemy" data-stage-index="${stageIndex}" data-subwave-index="${subIndex}">+</button>
      </h6>
  `;
  html += enemyGroup.map((enemy, enemyIndex) =>
    renderEnemy(enemy, stageIndex, subIndex, enemyIndex)
  ).join('');
  html += `</div>`;
  return html;
}

/**
 * 渲染单个敌人条目，包括必要参数和XML参数编辑器
 * @param {Object} enemy - 敌人数据
 * @param {number} stageIndex - 所属子关卡索引
 * @param {number} subIndex - 所属子波次索引
 * @param {number} enemyIndex - 敌人索引
 * @returns {string} HTML字符串
 */
function renderEnemy(enemy, stageIndex, subIndex, enemyIndex) {
  // 新增：获取units数据并生成下拉选项
  const units = Object.values(window.unitsDict);
  const optionsHTML = units.length > 0 
    ? units.map(unit => `
        <option value="${unit.id}" ${unit.id === enemy.Type ? 'selected' : ''}>
          ${unit.name} (ID: ${unit.id})${!unit.is_hostile ? ' [友军]' : ''}
        </option>
      `).join('')
    : '<option value="">请先导入units.json</option>';

  return `
    <div class="enemy section">
      <div class="required-fields">
        <!-- 修改点：将input替换为select -->
        <label>类型:
          <select 
            data-stage-index="${stageIndex}"
            data-subwave-index="${subIndex}"
            data-enemy-index="${enemyIndex}"
            data-enemy-field="Type"
            onchange="this.dispatchEvent(new Event('input'))" // 触发input事件以更新数据
          >
            ${optionsHTML}
          </select>
        </label>
        
        <!-- 原有显示单元信息的span -->
        <span class="unit-info">${window.getUnitDisplayText(enemy.Type)}</span>

        <label>间隔:
          <input 
            type="number" 
            value="${enemy.Interval}"
            data-stage-index="${stageIndex}"
            data-subwave-index="${subIndex}"
            data-enemy-index="${enemyIndex}"
            data-enemy-field="Interval"
          >
        </label>
        <label>数量:
          <input 
            type="number" 
            value="${enemy.Quantity}"
            data-stage-index="${stageIndex}"
            data-subwave-index="${subIndex}"
            data-enemy-index="${enemyIndex}"
            data-enemy-field="Quantity"
          >
        </label>
        <label>等级:
          <input 
            type="number" 
            value="${enemy.Level}"
            data-stage-index="${stageIndex}"
            data-subwave-index="${subIndex}"
            data-enemy-index="${enemyIndex}"
            data-enemy-field="Level"
          >
        </label>
      </div>
      <div class="xml-params-editor">
        <h6>参数配置 
          <button data-action="add-xml-param"
                  data-stage-index="${stageIndex}" 
                  data-subwave-index="${subIndex}" 
                  data-enemy-index="${enemyIndex}">
            +参数
          </button>
        </h6>
        <div class="xml-params-list">
          ${ renderXMLParams(enemy.Parameters, stageIndex, subIndex, enemyIndex) }
        </div>
      </div>
    </div>
  `;
}

/**
 * 渲染 XML 参数编辑器（多行参数配置）
 * @param {Object} params - 参数对象
 * @param {number} stageIndex - 所属子关卡索引
 * @param {number} subIndex - 所属子波次索引
 * @param {number} enemyIndex - 所属敌人索引
 * @returns {string} HTML字符串
 */
function renderXMLParams(params, stageIndex, subIndex, enemyIndex) {
  return Object.entries(params).map(([key, value]) => `
    <div class="xml-param">
      <input 
        type="text" 
        value="${key}" 
        data-action="update-xml-param-key"
        data-stage-index="${stageIndex}" 
        data-subwave-index="${subIndex}" 
        data-enemy-index="${enemyIndex}"
        data-old-key="${key}"
      >
      <textarea 
        data-action="update-xml-param-value"
        data-stage-index="${stageIndex}" 
        data-subwave-index="${subIndex}" 
        data-enemy-index="${enemyIndex}"
        data-key="${key}"
      >${value}</textarea>
      <button data-action="remove-xml-param"
              data-stage-index="${stageIndex}" 
              data-subwave-index="${subIndex}" 
              data-enemy-index="${enemyIndex}"
              data-key="${key}">×</button>
    </div>
  `).join('');
}
