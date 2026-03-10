// test_trace.jsfl - 动态加载器 v2（用 eval 替代 fl.runScript）
fl.trace("=== loader start ===");
var cfgPath = fl.configURI + "Commands/flash_project_path.cfg";
var projectURI = FLfile.read(cfgPath);
if (projectURI) {
	projectURI = projectURI.replace(/[\r\n]+$/, "");
	var scriptPath = projectURI + "/scripts/compile_action.jsfl";
	fl.trace("script: " + scriptPath);
	if (FLfile.exists(scriptPath)) {
		var code = FLfile.read(scriptPath);
		fl.trace("code length: " + code.length);
		eval(code);
	} else {
		fl.trace("[ERROR] not found: " + scriptPath);
		FLfile.write(projectURI + "/scripts/publish_error.marker", "not found: " + scriptPath);
	}
} else {
	fl.trace("[ERROR] no config");
}
