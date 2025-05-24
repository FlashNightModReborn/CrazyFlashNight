/* 
  utils.js
  存放一些辅助函数
*/

// XML转义
window.escapeXml = function (unsafe) {
    return unsafe?.toString()
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;");
  };
  
  // 深度设置嵌套字段（比如 "BasicInformation.Animation.Path"）
  window.setNestedField = function (obj, fieldPath, value) {
    const fields = fieldPath.split(".");
    let current = obj;
    for (let i = 0; i < fields.length - 1; i++) {
      const f = fields[i];
      if (!current[f]) {
        current[f] = {};
      }
      current = current[f];
    }
    const lastField = fields[fields.length - 1];
    current[lastField] = value;
  };
  
  // 由兵种ID获取展示文字
  window.getUnitDisplayText = function (type) {
    const data = window.unitsDict[type];
    if (!data) return "未找到units数据";
    let str = `[${data.name}] [${data.spritename}]`;
    if (data.is_hostile === false) str += " [友军]";
    return str;
  };
  