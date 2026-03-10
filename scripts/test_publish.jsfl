// test_publish.jsfl - 自动打开 TestLoader FLA 并发布（测试 trace）
// 用法：Flash CS6 命令行执行或双击运行

// 获取 JSFL 所在目录（file:/// URI 格式）
var jsflURI = fl.scriptURI;
var scriptsDir = jsflURI.substring(0, jsflURI.lastIndexOf("/"));

// TestLoader FLA 路径（XFL 格式）
var xflDir = scriptsDir + "/TestLoader";

// 标记文件：发布完成后写入，供外部脚本检测
var doneMarker = scriptsDir + "/publish_done.marker";

// 检查是否已经打开
var alreadyOpen = false;
var docs = fl.documents;
for (var i = 0; i < docs.length; i++) {
	if (docs[i].pathURI && docs[i].pathURI.indexOf("TestLoader") >= 0) {
		fl.setDocumentActive(docs[i]);
		alreadyOpen = true;
		break;
	}
}

if (!alreadyOpen) {
	fl.openDocument(xflDir);
}

// 发布
fl.getDocumentDOM().publish();

// 写入完成标记
FLfile.write(doneMarker, "done");
fl.trace("--- 发布完成 ---");
