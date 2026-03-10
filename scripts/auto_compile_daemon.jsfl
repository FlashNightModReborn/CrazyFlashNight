// auto_compile_daemon.jsfl - 编译守护进程
// 在 Flash 中通过菜单「命令 → auto_compile_daemon」启动一次
// 之后 Agent 只需写入 trigger 文件即可触发编译，无需再操作 Flash UI
//
// 工作原理：注册 idle 事件，每秒检查 trigger 文件是否存在
// 检测到时自动执行编译并写入完成标记

// ---- 读取项目路径配置 ----
var cfgPath = fl.configURI + "Commands/flash_project_path.cfg";
var projectURI = FLfile.read(cfgPath);

if (!projectURI || projectURI.length < 5) {
	fl.trace("[ERROR] 无法读取项目路径配置: " + cfgPath);
	fl.trace("请运行 scripts/setup_compile_env.bat 完成环境配置");
} else {
	projectURI = projectURI.replace(/[\r\n]+$/, "");

	var triggerFile = projectURI + "/scripts/compile_trigger";
	var doneMarker = projectURI + "/scripts/publish_done.marker";
	var errorMarker = projectURI + "/scripts/publish_error.marker";
	var xflDir = projectURI + "/scripts/TestLoader";

	// 避免重复注册
	if (typeof fl._autoCompileActive === "undefined" || !fl._autoCompileActive) {
		fl._autoCompileActive = true;
		fl._autoCompileProject = projectURI;
		fl._autoCompileTick = 0;

		fl.addEventListener("idle", function() {
			// 每 ~30 次 idle 检查一次（idle 大约每帧触发，~30fps → ~1秒）
			fl._autoCompileTick++;
			if (fl._autoCompileTick < 30) return;
			fl._autoCompileTick = 0;

			var proj = fl._autoCompileProject;
			var trigger = proj + "/scripts/compile_trigger";
			var done = proj + "/scripts/publish_done.marker";
			var err = proj + "/scripts/publish_error.marker";
			var xfl = proj + "/scripts/TestLoader";

			// 检查 trigger 文件
			if (!FLfile.exists(trigger)) return;

			// 读取 trigger 内容（可包含额外参数）
			var triggerContent = FLfile.read(trigger);
			FLfile.remove(trigger);

			fl.trace("[auto_compile] 检测到编译触发");

			// 查找或打开 TestLoader
			var doc = null;
			var docs = fl.documents;
			for (var i = 0; i < docs.length; i++) {
				if (docs[i].pathURI && docs[i].pathURI.indexOf("TestLoader") >= 0) {
					doc = docs[i];
					break;
				}
			}

			if (!doc) {
				fl.trace("[auto_compile] 正在打开 TestLoader...");
				fl.openDocument(xfl);
				doc = fl.getDocumentDOM();
			}

			if (!doc) {
				FLfile.write(err, "无法打开 TestLoader: " + xfl);
				fl.trace("[auto_compile] ERROR: 无法打开 TestLoader");
				return;
			}

			// 执行发布
			fl.outputPanel.clear();
			doc.publish();

			FLfile.write(done, "done");
			fl.trace("[auto_compile] 发布完成 ✓");
		});

		fl.trace("=== 自动编译守护已启动 ===");
		fl.trace("项目: " + projectURI);
		fl.trace("Agent 写入 scripts/compile_trigger 文件即可触发编译");
		fl.trace("要停止守护，关闭并重新打开 Flash");
	} else {
		fl.trace("[INFO] 自动编译守护已在运行中");
	}
}
