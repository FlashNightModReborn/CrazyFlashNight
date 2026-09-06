"""写入边界回归：使用隔离目录，绝不以真实素材作为故障注入对象。"""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
import core


class Transactions(unittest.TestCase):
    def setUp(self):
        workspace = core.ROOT
        (workspace / "tmp").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="asset-workbench-test-", dir=workspace / "tmp")
        self.root = Path(self.temp.name).resolve()
        assert self.root.is_relative_to((workspace / "tmp").resolve())
        self.patches = [patch.object(core, "ROOT", self.root), patch.object(core, "STORE", self.root / "tmp/asset-workbench"),
                        patch.object(core, "JOBS", self.root / "tmp/asset-workbench/jobs")]
        for item in self.patches:
            item.start()
        self.job_id = "a" * 32
        self.folder = core.job_path(self.job_id)
        self.folder.mkdir(parents=True)
        self.put(core.MAP, b"<assets />")
        self.put("source.swf", b"original source")
        self.png(core.ICONS + "/old.png")
        self.png(core.ICONS + "/skill/layer.png")
        self.icons = {"物品": {"f1": "old.png"}, "技能-保留": {"f1": "skill/layer.png", "frames": [{"layers": [{"uri": "old.png"}]}]}}
        core.write_json(self.root / core.ICONS / "manifest.json", self.icons)
        core.write_json(self.root / core.DRESS / "manifest.json", {"skinKeys": {}, "items": {}})
        self.png("tmp/asset-workbench/jobs/" + self.job_id + "/preview/after/icons/new.webp", (30, 150, 75, 255))
        core.write_json(self.folder / "result.json", {"icons": {"物品": {"f1": "new.webp"}}, "skins": {}, "item": {}})
        (self.folder / "source-map.xml").write_bytes(b"<assets />")
        core.write_json(self.folder / "job.json", {"jobId": self.job_id, "state": "ready", "kind": "icons", "item": "物品"})
        core.write_json(self.folder / "baseline.json", {
            "inputs": core.snapshot({"source.swf"}),
            "files": core.snapshot({core.ICONS + "/manifest.json", core.ICONS + "/old.png", core.ICONS + "/new.webp", core.MAP}),
            "candidates": {path: core.digest(self.folder / path) for path in ("result.json", "source-map.xml", "preview/after/icons/new.webp")}})
        self.before = self.project_files()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def put(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)

    def png(self, relative, color=(100, 120, 140, 255)):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGBA", (4, 4), color).save(path)

    def project_files(self):
        return {p.relative_to(self.root).as_posix(): p.read_bytes() for base in (self.root / core.ICONS, self.root / core.DRESS)
                for p in base.rglob("*") if p.is_file()}

    def test_apply_preserves_skills_nested_shared_frames_and_undo_is_exact(self):
        self.assertEqual(core.apply(self.job_id)["state"], "applied")
        result = core.read_json(self.root / core.ICONS / "manifest.json")
        self.assertEqual(result["技能-保留"], self.icons["技能-保留"])
        self.assertTrue((self.root / core.ICONS / "old.png").is_file())
        self.assertEqual(core.apply(self.job_id)["state"], "applied")
        self.assertEqual(core.apply(self.job_id, True)["state"], "reverted")
        self.assertEqual(self.project_files(), self.before)
        self.assertEqual(core.apply(self.job_id, True)["state"], "reverted")

    def test_changed_source_blocks_apply(self):
        self.put("source.swf", b"changed source")
        with self.assertRaisesRegex(core.WorkbenchError, "来源已变化"):
            core.apply(self.job_id)
        self.assertEqual(self.project_files(), self.before)

    def test_changed_output_blocks_apply(self):
        self.put(core.ICONS + "/old.png", b"someone else's edit")
        with self.assertRaisesRegex(core.WorkbenchError, "项目产物已变化"):
            core.apply(self.job_id)

    def test_changed_candidate_blocks_apply(self):
        self.png("tmp/asset-workbench/jobs/" + self.job_id + "/preview/after/icons/new.webp", (1, 2, 3, 255))
        with self.assertRaisesRegex(core.WorkbenchError, "候选文件已变化"):
            core.apply(self.job_id)
        self.assertEqual(self.project_files(), self.before)

    def test_undo_protects_subsequent_edits(self):
        core.apply(self.job_id)
        self.put(core.ICONS + "/new.webp", b"later edit")
        with self.assertRaisesRegex(core.WorkbenchError, "不能覆盖后续修改"):
            core.apply(self.job_id, True)
        self.assertEqual((self.root / core.ICONS / "new.webp").read_bytes(), b"later edit")

    def test_write_failure_restores_complete_previous_project(self):
        original = core.atomic_bytes
        failed = False
        def write(path, data):
            nonlocal failed
            if path == self.root / core.ICONS / "manifest.json" and not failed:
                failed = True
                raise OSError("模拟磁盘写入失败")
            original(path, data)
        with patch.object(core, "atomic_bytes", write), self.assertRaisesRegex(OSError, "模拟"):
            core.apply(self.job_id)
        self.assertEqual(self.project_files(), self.before)
        self.assertEqual(core.apply(self.job_id)["state"], "applied")

    def test_recover_interrupted_apply(self):
        core.apply(self.job_id)
        transaction = core.read_json(self.folder / "transaction.json")
        transaction["state"] = "applying"
        core.write_json(self.folder / "transaction.json", transaction)
        core.update(self.job_id, state="ready")
        with core.workspace_lock():
            pass
        self.assertEqual(self.project_files(), self.before)
        self.assertEqual(core.status(self.job_id)["state"], "ready")

    def test_recover_completed_write_before_status_update(self):
        core.apply(self.job_id)
        core.update(self.job_id, state="ready")
        self.assertEqual(core.apply(self.job_id)["state"], "applied")
        core.apply(self.job_id, True)
        self.assertEqual(self.project_files(), self.before)

    def test_recover_interrupted_undo(self):
        core.apply(self.job_id)
        transaction = core.read_json(self.folder / "transaction.json")
        transaction["state"] = "undoing"
        core.write_json(self.folder / "transaction.json", transaction)
        with core.workspace_lock():
            pass
        self.assertEqual(core.status(self.job_id)["state"], "reverted")
        self.assertEqual(self.project_files(), self.before)

    def test_existing_job_is_idempotent_and_rejects_rebinding(self):
        self.assertEqual(core.start("物品", "icons", self.job_id)["state"], "ready")
        with self.assertRaisesRegex(core.WorkbenchError, "不同的素材"):
            core.start("别的物品", "icons", self.job_id)

    def test_writer_lock_excludes_concurrent_apply(self):
        with core.workspace_lock():
            with self.assertRaisesRegex(core.WorkbenchError, "另一个素材任务"):
                core.apply(self.job_id)

    def test_path_escape_and_foreign_commands_are_rejected(self):
        for path in ("../source.swf", "C:/outside.png", "a\\b.png", "/outside.png"):
            with self.assertRaises(core.WorkbenchError):
                core.safe_path(self.root, path)
        with self.assertRaises(core.WorkbenchError):
            core.api({"op": "shell", "command": "anything"})

    def test_origin_validation_distinguishes_export_summary_and_frame(self):
        entry = {"export": {"uri": "old.png", "format": "png"},
                 "frames": [{"uri": "old.png", "width": 4, "height": 4, "originX": 1, "originY": 2}]}
        core.validate_images(entry, self.root / core.ICONS, True)
        invalid = copy.deepcopy(entry)
        invalid["frames"][0]["originX"] = float("nan")
        with self.assertRaisesRegex(core.WorkbenchError, "注册点"):
            core.validate_images(invalid, self.root / core.ICONS, True)


if __name__ == "__main__":
    unittest.main()
