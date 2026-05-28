// compile_action.jsfl - 实际编译逻辑
// 可通过 fl.runScript(path, "main") 或 eval() 调用

function main() {
	var cfgPath = fl.configURI + "Commands/flash_project_path.cfg";
	var projectURI = FLfile.read(cfgPath);
	projectURI = projectURI.replace(/[\r\n]+$/, "");
	var doneMarker = projectURI + "/scripts/publish_done.marker";
	var errorMarker = projectURI + "/scripts/publish_error.marker";
	var outputLog = projectURI + "/scripts/compile_output.txt";
	var compilerErrorsLog = projectURI + "/scripts/compiler_errors.txt";

	fl.outputPanel.clear();

	fl.trace("[compile] docs: " + fl.documents.length);

	var doc = fl.getDocumentDOM();
	fl.trace("[compile] doc: " + (doc ? doc.name : "null"));

	if (!doc) {
		FLfile.write(errorMarker, "no document open");
		fl.trace("[compile] ERROR: no document");
		fl.outputPanel.save(outputLog);
	} else {
		// 从磁盘重新加载 XFL：外部 (Agent / 编辑器) 编辑过的 .xml 帧脚本 / symbol 改动
		// 必须经 close + reopen 才会被 Flash CS6 重新解析；否则 testMovie 用的是
		// 打开 FLA 时的旧 in-memory 表达，外部编辑全部不可见，最直观症状是
		// "明明改了源文件，编译错误还指向旧行号 / 旧符号"。
		var docUri = doc.pathURI;
		fl.trace("[compile] reload from disk: " + docUri);
		fl.closeDocument(doc, false);  // false = 不提示保存（外部源是 SOT，丢弃 in-memory 改动）
		doc = fl.openDocument(docUri);
		fl.trace("[compile] reloaded doc: " + (doc ? doc.name : "null"));

		if (!doc) {
			FLfile.write(errorMarker, "reload failed: " + docUri);
			fl.trace("[compile] ERROR: reload failed");
			fl.outputPanel.save(outputLog);
			return;
		}

		fl.trace("[compile] testMovie: " + doc.name);
		doc.testMovie();
		fl.trace("[compile] done");
		fl.outputPanel.save(outputLog);
		// 捕获 Compiler Errors 面板内容
		if (fl.compilerErrors) {
			fl.compilerErrors.save(compilerErrorsLog);
		}
		FLfile.write(doneMarker, "ok");
	}
}

// 直接执行时（eval 调用）也能工作
main();
