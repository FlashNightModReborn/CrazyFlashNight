// compile_action.jsfl - 实际编译逻辑
// 可通过 fl.runScript(path, "main") 或 eval() 调用

function normalizeDocumentURI(uri) {
	var value = String(uri || "");
	try { value = FLfile.uriToPlatformPath(value); } catch (e1) {}
	try { value = decodeURI(value); } catch (e2) {}
	return value.replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
}

function containsOnly32KCompilerErrors(text) {
	var lines = String(text || "").split(/\r?\n/);
	var errorCount = -1;
	var warningCount = -1;
	var diagnosticCount = 0;
	var sawSummary = false;
	for (var i = 0; i < lines.length; i++) {
		var line = lines[i];
		if (/^\s*$/.test(line)) continue;
		var summary = /^\s*(\d+)\s+[^,\r\n]+,\s*(\d+)\s+[^,\r\n]+\s*$/.exec(line);
		if (summary) {
			if (sawSummary) return false;
			errorCount = parseInt(summary[1], 10);
			warningCount = parseInt(summary[2], 10);
			sawSummary = true;
		} else {
			// Conservative contract: one exported line per error, every line itself
			// names the 32K branch diagnostic, and no text follows the summary.
			if (sawSummary || line.indexOf("32K") < 0) return false;
			diagnosticCount++;
		}
	}
	// 多行/上下文格式无法证明一一对应时不重试；人工检查首轮完整诊断。
	return sawSummary && errorCount > 0 && warningCount == 0 &&
		diagnosticCount == errorCount;
}

function main() {
	var cfgPath = fl.configURI + "Commands/flash_project_path.cfg";
	var projectURI = FLfile.read(cfgPath);
	projectURI = projectURI.replace(/[\r\n]+$/, "");
	var doneMarker = projectURI + "/scripts/publish_done.marker";
	var errorMarker = projectURI + "/scripts/publish_error.marker";
	var outputLog = projectURI + "/scripts/compile_output.txt";
	var compilerErrorsLog = projectURI + "/scripts/compiler_errors.txt";

	fl.outputPanel.clear();
	// Compiler Errors 是独立面板；只清 Output Panel 会让上一个目标的错误污染本轮结果。
	// 先清面板并删除旧导出，确保保存的只能是本次 testMovie/publish 产生的诊断。
	try {
		if (fl.compilerErrors && fl.compilerErrors.clear) fl.compilerErrors.clear();
	} catch (clearCompilerErrorsError) {
		fl.trace("[compile] WARN: compilerErrors.clear failed: " + clearCompilerErrorsError);
	}
	if (FLfile.exists(compilerErrorsLog)) FLfile.remove(compilerErrorsLog);

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

	// mode 与 target 属于同一轮一次性指令；必须在任何 target/doc early return 前一并消费，
	// 否则一次坏目标会把 publish 模式泄漏给后续手工触发。
	var modeCfg = projectURI + "/scripts/compile_mode.cfg";
	var compileMode = "test";
	if (FLfile.exists(modeCfg)) {
		var _m = FLfile.read(modeCfg);
		FLfile.remove(modeCfg);
		if (_m) compileMode = _m.replace(/^[\s﻿]+/, "").replace(/[\s]+$/, "");
	}

	var doc;
	if (targetURI) {
		fl.trace("[compile] target cfg: " + targetURI);
		if (!FLfile.exists(targetURI)) {
			fl.trace("[compile] ERROR: target not found: " + targetURI);
			fl.outputPanel.save(outputLog);
			FLfile.write(errorMarker, "target not found: " + targetURI);
			return;
		}
		// 目标若已打开 → 先关（false=不存盘，丢弃 in-memory，强制从盘重读外部编辑），再开 = 与活动文档路径同款 reload。
		// pathURI 对中文路径可能返回 percent-encoded URI，而 cfg 可能是直写 Unicode；必须归一为平台路径比较，
		// 否则 openDocument 会复用带 * 的旧文档，publish 虽刷新 SWF 时间戳却仍编进旧 symbol bytecode。
		var targetKey = normalizeDocumentURI(targetURI);
		for (var i = fl.documents.length - 1; i >= 0; i--) {
			if (normalizeDocumentURI(fl.documents[i].pathURI) == targetKey) {
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
		fl.trace("[compile] ERROR: no document");
		fl.outputPanel.save(outputLog);
		FLfile.write(errorMarker, "no document (target=" + targetURI + ")");
		return;
	}

	// 默认 testMovie（TestLoader/显式测试目标需运行产 trace / 刷新 SWF）。
	// compile_mode.cfg == "publish" 时只编译产出 SWF，不拉起全量游戏窗口。
	if (compileMode == "publish") {
		fl.trace("[compile] publish (no testMovie): " + doc.name);
		doc.publish();
	} else {
		fl.trace("[compile] testMovie: " + doc.name);
		doc.testMovie();
	}
	// 靠近 AS2 单分支 32K 上限的旧大类在切换 XFL 后，CS6 冷 ASO 首编可能失败，
	// 同目标热编则稳定通过。只对这一条可识别诊断重试一次；语法/链接等其他错误绝不重试，
	// 第二次仍失败也会原样保存并由 PowerShell fail-closed。
	if (fl.compilerErrors) fl.compilerErrors.save(compilerErrorsLog);
	var firstCompilerErrors = FLfile.exists(compilerErrorsLog) ? FLfile.read(compilerErrorsLog) : "";
	if (containsOnly32KCompilerErrors(firstCompilerErrors)) {
		fl.trace("[compile] cold ASO 32K branch detected; retry same target once");
		fl.trace("[compile] first 32K compiler diagnostics (preserved before retry):\n" + firstCompilerErrors);
		try {
			if (fl.compilerErrors && fl.compilerErrors.clear) fl.compilerErrors.clear();
		} catch (retryClearError) {
			fl.trace("[compile] WARN: retry compilerErrors.clear failed: " + retryClearError);
		}
		if (FLfile.exists(compilerErrorsLog)) FLfile.remove(compilerErrorsLog);
		if (compileMode == "publish") doc.publish();
		else doc.testMovie();
		if (fl.compilerErrors) fl.compilerErrors.save(compilerErrorsLog);
	}
	fl.trace("[compile] done");
	fl.outputPanel.save(outputLog);
	FLfile.write(doneMarker, "ok");
}

// 直接执行时（eval 调用）也能工作
main();
