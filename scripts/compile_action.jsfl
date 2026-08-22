// compile_action.jsfl - 实际编译逻辑
// 可通过 fl.runScript(path, "main") 或 eval() 调用

function normalizeDocumentURI(uri) {
	var value = String(uri || "");
	// Do not invoke a platform-path FLfile conversion for arbitrary open documents.
	// Flash CS6 can abort the whole JSFL host on some unsaved/non-ASCII XFL
	// paths, bypassing JavaScript try/catch. Pure string normalization is enough
	// to compare encoded vs unencoded document URIs.
	try { value = decodeURI(value); } catch (decodeError) {}
	return value.replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
}

// FLfile.exists() accepts the historical unescaped form
// "file:///C|/Program Files/...", but fl.openDocument() is stricter. Encode
// with pure JavaScript so path preparation cannot itself enter a fragile
// FLfile host call.
function canonicalizeDocumentURI(uri) {
	var value = String(uri || "");
	try { return encodeURI(decodeURI(value)); } catch (decodeError) {}
	try { return encodeURI(value); } catch (encodeError) {}
	return value;
}

var compileRuntimeState = {
	phase: "bootstrap",
	projectURI: "",
	targetURI: ""
};

function describeJsflError(error) {
	var parts = [];
	try {
		if (error && error.name) parts.push(String(error.name));
		if (error && error.message) parts.push(String(error.message));
		if (error && error.lineNumber) parts.push("line=" + error.lineNumber);
		if (error && error.fileName) parts.push("file=" + error.fileName);
	} catch (detailError) {}
	if (parts.length == 0) {
		try { parts.push(String(error)); } catch (stringError) { parts.push("unknown JSFL error"); }
	}
	return parts.join(" | ");
}

function writeFatalCompileError(error) {
	var projectURI = compileRuntimeState.projectURI;
	if (!projectURI) {
		try {
			projectURI = FLfile.read(fl.configURI + "Commands/flash_project_path.cfg");
			if (projectURI) projectURI = projectURI.replace(/[\r\n]+$/, "");
		} catch (configError) {}
	}

	var message = "[compile] FATAL phase=" + compileRuntimeState.phase +
		" target=" + compileRuntimeState.targetURI +
		" error=" + describeJsflError(error);
	try { fl.trace(message); } catch (traceError) {}

	if (projectURI) {
		// Write the terminal marker before auxiliary Output Panel export so a
		// second failure cannot degrade into a PowerShell timeout.
		try { FLfile.write(projectURI + "/scripts/publish_error.marker", message); } catch (markerError) {}
		try { fl.outputPanel.save(projectURI + "/scripts/compile_output.txt"); } catch (saveError) {}
	}
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
	compileRuntimeState.phase = "read_project_config";
	var cfgPath = fl.configURI + "Commands/flash_project_path.cfg";
	var projectURI = FLfile.read(cfgPath);
	projectURI = projectURI.replace(/[\r\n]+$/, "");
	compileRuntimeState.projectURI = projectURI;
	var doneMarker = projectURI + "/scripts/publish_done.marker";
	var errorMarker = projectURI + "/scripts/publish_error.marker";
	var reopenMarker = projectURI + "/scripts/compile_reopen.marker";
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
	var quitCfg = projectURI + "/scripts/compile_quit_after_publish.cfg";
	var compileMode = "test";
	if (FLfile.exists(modeCfg)) {
		var _m = FLfile.read(modeCfg);
		FLfile.remove(modeCfg);
		if (_m) compileMode = _m.replace(/^[\s﻿]+/, "").replace(/[\s]+$/, "");
	}
	var quitAfterPublish = false;
	if (FLfile.exists(quitCfg)) {
		var _q = FLfile.read(quitCfg);
		FLfile.remove(quitCfg);
		_q = _q ? _q.replace(/^[\s﻿]+/, "").replace(/[\s]+$/, "") : "";
		if (_q != "quit" || compileMode != "publish") {
			fl.trace("[compile] ERROR: invalid quit-after-publish request");
			fl.outputPanel.save(outputLog);
			FLfile.write(errorMarker, "invalid quit-after-publish request");
			return;
		}
		quitAfterPublish = true;
	}

	var doc;
	if (targetURI) {
		compileRuntimeState.targetURI = targetURI;
		fl.trace("[compile] target cfg: " + targetURI);
		if (!FLfile.exists(targetURI)) {
			fl.trace("[compile] ERROR: target not found: " + targetURI);
			fl.outputPanel.save(outputLog);
			FLfile.write(errorMarker, "target not found: " + targetURI);
			return;
		}
		// 目标若已打开 → 先关（false=不存盘，丢弃 in-memory，强制从盘重读外部编辑），再开 = 与活动文档路径同款 reload。
		// pathURI 对中文路径可能返回 percent-encoded URI，而 cfg 可能是直写 Unicode；必须以纯字符串 URI 归一化比较，
		// 否则 openDocument 会复用带 * 的旧文档，publish 虽刷新 SWF 时间戳却仍编进旧 symbol bytecode。
		var targetKey = normalizeDocumentURI(targetURI);
		compileRuntimeState.phase = "close_opened_target";
		var closedOpenedTarget = false;
		for (var i = fl.documents.length - 1; i >= 0; i--) {
			if (normalizeDocumentURI(fl.documents[i].pathURI) == targetKey) {
				fl.trace("[compile] close opened target: " + targetURI);
				fl.closeDocument(fl.documents[i], false);
				closedOpenedTarget = true;
			}
		}
		if (closedOpenedTarget) {
			// Flash CS6 can abort the whole JSFL host call when the same XFL is
			// closed and immediately reopened in one stack. Ask compile_test.ps1
			// to trigger a second task invocation after this call has returned.
			compileRuntimeState.phase = "request_second_phase_reopen";
			fl.trace("[compile] target closed; request second-phase reopen");
			try { fl.outputPanel.save(outputLog); } catch (reopenOutputError) {}
			FLfile.write(reopenMarker, targetURI + "\n" + compileMode);
			return;
		}
		compileRuntimeState.phase = "open_target_from_disk";
		var targetOpenURI = canonicalizeDocumentURI(targetURI);
		fl.trace("[compile] open target from disk: " + targetOpenURI);
		// openDocument can abort the JSFL host without throwing a catchable
		// exception. Persist the exact URI immediately before crossing that
		// boundary so failure diagnosis never depends on the live Output panel.
		try { fl.outputPanel.save(outputLog); } catch (preOpenOutputError) {}
		doc = fl.openDocument(targetOpenURI);
	} else {
		doc = fl.getDocumentDOM();
		fl.trace("[compile] active doc: " + (doc ? doc.name : "null"));
		if (doc) {
			// 从磁盘重新加载 XFL：外部 (Agent / 编辑器) 编辑过的 .xml 帧脚本 / symbol 改动
			// 必须经 close + reopen 才会被 Flash CS6 重新解析；否则 testMovie 用的是
			// 打开 FLA 时的旧 in-memory 表达，外部编辑全部不可见，最直观症状是
			// "明明改了源文件，编译错误还指向旧行号 / 旧符号"。
			var docUri = doc.pathURI;
			compileRuntimeState.targetURI = docUri;
			fl.trace("[compile] reload from disk: " + docUri);
			compileRuntimeState.phase = "close_active_target";
			fl.closeDocument(doc, false);  // false = 不提示保存（外部源是 SOT，丢弃 in-memory 改动）
			compileRuntimeState.phase = "request_second_phase_reopen";
			fl.trace("[compile] active target closed; request second-phase reopen");
			try { fl.outputPanel.save(outputLog); } catch (activeReopenOutputError) {}
			FLfile.write(reopenMarker, docUri + "\n" + compileMode);
			return;
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
		compileRuntimeState.phase = "publish_document";
		fl.trace("[compile] publish (no testMovie): " + doc.name);
		doc.publish();
	} else {
		compileRuntimeState.phase = "test_movie";
		fl.trace("[compile] testMovie: " + doc.name);
		doc.testMovie();
	}
	// 靠近 AS2 单分支 32K 上限的旧大类在部分 ASO 状态下首轮可能失败，
	// 同目标再次编译则稳定通过。只对这一条可识别诊断重试一次；语法/链接等其他错误绝不重试，
	// 第二次仍失败也会原样保存并由 PowerShell fail-closed。
	if (fl.compilerErrors) fl.compilerErrors.save(compilerErrorsLog);
	var firstCompilerErrors = FLfile.exists(compilerErrorsLog) ? FLfile.read(compilerErrorsLog) : "";
	if (containsOnly32KCompilerErrors(firstCompilerErrors)) {
		fl.trace("[compile] ASO 32K branch detected; retry same target once");
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
	// Flash CS6 是 32 位进程；连续批量发布大型 XFL 时，保留每个已发布文档会让
	// 地址空间持续上涨并最终撞墙。publish-only 已经把磁盘 XML 视为 source of
	// truth，因此在诊断落盘后关闭当前目标，不保存 IDE 内存态。testMovie 目标仍
	// 保持打开，方便读取 trace 和继续调试。
	if (compileMode == "publish") {
		compileRuntimeState.phase = "close_published_target";
		fl.trace("[compile] close published target: " + doc.name);
		fl.closeDocument(doc, false);
	}
	if (quitAfterPublish) {
		fl.trace("[compile] quit Flash after completed publish");
	}
	fl.trace("[compile] done");
	fl.outputPanel.save(outputLog);
	FLfile.write(doneMarker, "ok");
	compileRuntimeState.phase = "complete";
	if (quitAfterPublish) {
		fl.quit(false);
	}
}

// 直接执行时（eval 调用）也能工作
try {
	main();
} catch (fatalCompileError) {
	writeFatalCompileError(fatalCompileError);
}
