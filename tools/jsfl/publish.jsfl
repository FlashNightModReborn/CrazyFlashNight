// tools/jsfl/publish.jsfl
// 极简：发布当前激活的文档，完成后退出 CS6
(function () {
  var doc = fl.getDocumentDOM();
  if (!doc) {
    // 若命令行同时传了 XFL/FLA，通常此时已经被打开为当前文档；
    // 如果还没有，尝试打开命令行第一个参数（可选）
    if (fl.arguments && fl.arguments.length > 0) {
      try { fl.openDocument(fl.arguments[0]); } catch (e) {}
      doc = fl.getDocumentDOM();
    }
  }
  if (!doc) {
    fl.trace("[publish.jsfl] 没有打开的文档，发布终止。");
    fl.quit(false);
    return;
  }
  try {
    doc.publish();                // 使用文档自带的 Publish Settings
    fl.trace("[publish.jsfl] 发布完成。");
  } catch (e) {
    fl.trace("[publish.jsfl] 发布失败：" + e);
  }
  fl.quit(false);                 // 退出 IDE，确保命令“跑一次就完结”
})();
