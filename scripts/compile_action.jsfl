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

	// 编译目标解析：compile_target.cfg（compile_test.ps1 -Target 写入的 file:/// URI）优先；
	//   空/缺 → 回退活动文档 fl.getDocumentDOM()（向后兼容）。这让 test/publish 目标可由参数切换，不靠手动切活动文档。
	var targetCfg = projectURI + "/scripts/compile_target.cfg";
	var targetURI = "";
	if (FLfile.exists(targetCfg)) {
		var _t = FLfile.read(targetCfg);
		// compile_target.cfg 是一次性指令：读到就消费删除，避免后续手工/JSFL 触发继承旧目标而误编。
		FLfile.remove(targetCfg);
		if (_t) targetURI = _t.replace(/^[\s﻿]+/, "").replace(/[\s]+$/, "");  // 剥 BOM/空白
	}

	var doc;
	if (targetURI) {
		fl.trace("[compile] target cfg: " + targetURI);
		if (!FLfile.exists(targetURI)) {
			FLfile.write(errorMarker, "target not found: " + targetURI);
			fl.trace("[compile] ERROR: target not found: " + targetURI);
			fl.outputPanel.save(outputLog);
			return;
		}
		// 目标若已打开 → 先关（false=不存盘，丢弃 in-memory，强制从盘重读外部编辑），再开 = 与活动文档路径同款 reload。
		for (var i = fl.documents.length - 1; i >= 0; i--) {
			if (fl.documents[i].pathURI == targetURI) {
				fl.trace("[compile] close opened target: " + targetURI);
				fl.closeDocument(fl.documents[i], false);
			}
		}
		fl.trace("[compile] open target from disk: " + targetURI);
		doc = fl.openDocument(targetURI);
	} else {
		doc = fl.getDocumentDOM();
		fl.trace("[compile] active doc: " + (doc ? doc.name : "null"));
		if (doc) {
			// 从磁盘重新加载 XFL：外部 (Agent / 编辑器) 编辑过的 .xml 帧脚本 / symbol 改动
			// 必须经 close + reopen 才会被 Flash CS6 重新解析；否则 testMovie 用的是
			// 打开 FLA 时的旧 in-memory 表达，外部编辑全部不可见，最直观症状是
			// "明明改了源文件，编译错误还指向旧行号 / 旧符号"。
			var docUri = doc.pathURI;
			fl.trace("[compile] reload from disk: " + docUri);
			fl.closeDocument(doc, false);  // false = 不提示保存（外部源是 SOT，丢弃 in-memory 改动）
			doc = fl.openDocument(docUri);
			fl.trace("[compile] reloaded doc: " + (doc ? doc.name : "null"));
		}
	}

	if (!doc) {
		FLfile.write(errorMarker, "no document (target=" + targetURI + ")");
		fl.trace("[compile] ERROR: no document");
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

// 直接执行时（eval 调用）也能工作
main();
