// test_publish.jsfl - 诊断版
var cfgPath = fl.configURI + "Commands/flash_project_path.cfg";
var projectURI = FLfile.read(cfgPath);
projectURI = projectURI.replace(/[\r\n]+$/, "");
var doneMarker = projectURI + "/scripts/publish_done.marker";
var stepMarker = projectURI + "/scripts/publish_step.marker";

fl.trace("[step1] 配置读取OK");
FLfile.write(stepMarker, "step1_config_ok");

fl.trace("[step2] 文档数: " + fl.documents.length);
FLfile.write(stepMarker, "step2_docs_" + fl.documents.length);

var doc = fl.getDocumentDOM();
fl.trace("[step3] 当前文档: " + (doc ? doc.name : "null"));
FLfile.write(stepMarker, "step3_doc_" + (doc ? doc.name : "null"));

if (doc) {
	fl.trace("[step4] 准备发布...");
	FLfile.write(stepMarker, "step4_before_publish");

	doc.publish();

	fl.trace("[step5] 发布完成");
	FLfile.write(doneMarker, "publish_ok");
	FLfile.write(stepMarker, "step5_done");
} else {
	FLfile.write(stepMarker, "step3_no_doc");
}
