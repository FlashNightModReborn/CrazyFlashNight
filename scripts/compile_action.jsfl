// compile_action.jsfl - 实际编译逻辑
// 可通过 fl.runScript(path, "main") 或 eval() 调用

function main() {
	var cfgPath = fl.configURI + "Commands/flash_project_path.cfg";
	var projectURI = FLfile.read(cfgPath);
	projectURI = projectURI.replace(/[\r\n]+$/, "");
	var doneMarker = projectURI + "/scripts/publish_done.marker";
	var errorMarker = projectURI + "/scripts/publish_error.marker";

	fl.trace("[compile] docs: " + fl.documents.length);

	var doc = fl.getDocumentDOM();
	fl.trace("[compile] doc: " + (doc ? doc.name : "null"));

	if (!doc) {
		FLfile.write(errorMarker, "no document open");
		fl.trace("[compile] ERROR: no document");
	} else {
		fl.trace("[compile] testMovie: " + doc.name);
		doc.testMovie();
		fl.trace("[compile] done");
		FLfile.write(doneMarker, "ok");
	}
}

// 直接执行时（eval 调用）也能工作
main();
