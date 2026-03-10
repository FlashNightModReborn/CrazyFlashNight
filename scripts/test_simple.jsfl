// 测试1：弹窗确认脚本被执行
fl.trace("=== JSFL 开始执行 ===");

// 测试2：写文件到用户目录（无空格路径）
var testFile = "file:///C|/Users/fs/jsfl_test.txt";
FLfile.write(testFile, "jsfl works!");
fl.trace("写入测试: " + testFile);
fl.trace("文件存在: " + FLfile.exists(testFile));

fl.trace("=== JSFL 执行完毕 ===");
