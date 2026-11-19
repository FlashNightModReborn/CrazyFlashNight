"""Real filesystem and process interruption tests of the asLoader set publisher."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import shutil

import asloader_artifact_set as sets


def files(root, generation):
    (root / "scripts").mkdir(parents=True, exist_ok=True)
    for module, path in sets.paths(root).items():
        path.write_bytes((generation + module).encode())
    return {"id": generation, "modules": {name: {"sha256": digest} for name, digest in sets.hashes(root).items()}}


def install_git_ref(root, generation):
    def git(*args, data=None):
        return subprocess.check_output(["git", "-C", str(root), *args], input=data).strip()
    row = files(root, generation)
    if not (root / ".git").is_dir():
        git("init", "-q")
        git("config", "core.autocrlf", "false")
    git("add", "--", "scripts")
    tree = git("write-tree")
    # Disposable object fixtures only; do not create commits in the project.
    commit = (b"tree " + tree + b"\nauthor Fixture <fixture@invalid> 1 +0000\n"
              b"committer Fixture <fixture@invalid> 1 +0000\n\nfixture\n")
    oid = git("hash-object", "-t", "commit", "-w", "--stdin", data=commit)
    git("update-ref", "HEAD", oid.decode())
    return row


def current(root):
    with sets.lock(root) as state:
        return sets.status(root, state)


def kill_during(root, candidate, step, recovery=False):
    # os._exit tears down this disposable child without giving the publisher
    # any opportunity to run finally blocks or unwind the transaction.
    script = """
import os, sys
from pathlib import Path
import asloader_artifact_set as a
root, candidate = map(Path, sys.argv[1:3])
def stop(point):
    if point == sys.argv[3]: os._exit(73)
if sys.argv[4] == 'recover':
    a.recover(root, stop)
else:
    with a.lock(root) as state: expected = a.status(root, state)
    a.commit(root, candidate, a.read_json(candidate/'evidence.json'), expected, stop)
"""
    result = subprocess.run([sys.executable, "-B", "-c", script, str(root), str(candidate), step,
                             "recover" if recovery else "commit"], cwd=Path(sets.__file__).parent)
    if result.returncode != 73:
        raise AssertionError(f"Child did not exit at {step}: exit {result.returncode}")


class ArtifactSetTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name, "game")
        self.candidate = Path(temp.name, "candidate")
        self.old = files(self.root, "old")
        self.candidate.mkdir()
        files(self.candidate, "old")
        sets.commit(self.root, self.candidate, self.old, current(self.root))
        self.new = files(self.candidate, "new")
        (self.candidate / "evidence.json").write_text(json.dumps(self.new))

    def test_new_and_metadata_only(self):
        start = current(self.root)
        new = sets.commit(self.root, self.candidate, self.new, start)
        self.assertEqual(new["active"], self.new)
        stamps = [p.stat().st_mtime_ns for p in sets.paths(self.root).values()]
        changed = dict(self.new, validation="revalidated")
        updated = sets.commit(self.root, self.candidate, changed, new)
        self.assertNotEqual(updated["indexSha256"], new["indexSha256"])
        self.assertEqual(stamps, [p.stat().st_mtime_ns for p in sets.paths(self.root).values()])
        self.assertEqual(updated, sets.commit(self.root, self.candidate, changed, updated))
        with self.assertRaisesRegex(ValueError, "since planning"):
            sets.commit(self.root, self.candidate, self.new, start)

    def test_crash_at_every_install_checkpoint(self):
        for step in ("journal", "resident", "shared", "boot", "index"):
            with self.subTest(step=step):
                kill_during(self.root, self.candidate, step)
                with self.assertRaisesRegex(ValueError, "recovery"):
                    current(self.root)
                recovered = sets.recover(self.root)
                self.assertEqual(recovered["active"], self.new if step == "index" else self.old)

    def test_crash_during_recovery_is_recoverable(self):
        for step in ("restore-resident", "restore-shared", "restore-boot"):
            kill_during(self.root, self.candidate, "boot")
            kill_during(self.root, self.candidate, step, recovery=True)
            self.assertEqual(sets.recover(self.root)["active"], self.old)

    def test_third_party_bytes_preserved_without_any_rollback(self):
        kill_during(self.root, self.candidate, "shared")
        target = sets.paths(self.root)["boot"]
        target.write_bytes(b"third party")
        before = sets.hashes(self.root)
        with self.assertRaisesRegex(ValueError, "Unknown bytes"):
            sets.recover(self.root)
        self.assertEqual(sets.hashes(self.root), before)

    def test_stale_or_damaged_evidence(self):
        expected = current(self.root)
        sets.paths(self.candidate)["shared"].write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "Candidate and receipt"):
            sets.commit(self.root, self.candidate, self.new, expected)
        self.assertEqual(current(self.root), expected)
        sets.paths(self.root)["shared"].write_bytes(b"externally modified")
        with self.assertRaisesRegex(ValueError, "external changes"):
            current(self.root)

    def test_readers_and_writers_do_not_overlap(self):
        expected = current(self.root)
        with sets.lock(self.root):
            with self.assertRaises(OSError):
                sets.commit(self.root, self.candidate, self.new, expected)
        with sets.lock(self.root, writer=True):
            with self.assertRaises(OSError):
                current(self.root)

    def test_unknown_compile_blocks_recovery(self):
        kill_during(self.root, self.candidate, "resident")
        (self.root / "scripts/compile_state_uncertain.marker").touch()
        before = sets.hashes(self.root)
        with self.assertRaisesRegex(ValueError, "Unresolved Flash"):
            sets.recover(self.root)
        self.assertEqual(sets.hashes(self.root), before)

    def test_fresh_root_with_no_prior_artifacts(self):
        fresh = self.root.parent / "empty"
        fresh.mkdir()
        kill_during(fresh, self.candidate, "boot")
        rollback = sets.recover(fresh)
        self.assertIsNone(rollback["active"])
        self.assertEqual(rollback["installed"], dict.fromkeys(sets.MODULES))

    def test_plan_only_is_read_only_and_diagnoses_external_drift(self):
        initial = self.root.parent / "initial"
        files(initial, "preexisting")
        self.assertIsNone(sets.read_status(initial)["active"])
        self.assertFalse((initial / "tmp").exists())
        target = sets.paths(self.root)["boot"]
        target.unlink()
        diagnostic = sets.read_status(self.root, diagnostic=True)
        self.assertEqual((diagnostic["state"], diagnostic["differing"]), ("INVALID", ["boot"]))
        with self.assertRaisesRegex(ValueError, "external changes"):
            sets.commit(self.root, self.candidate, self.new, diagnostic)
        self.assertFalse(target.exists())

    def test_preexisting_guardian_without_player_rejects_install(self):
        # The PID is this test's owned process. There is no Player PID at all.
        expected = current(self.root)
        (self.root / "launcher_ports.json").write_text(json.dumps({"pid": os.getpid()}))
        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
            sets.commit(self.root, self.candidate, self.new, expected)
        self.assertEqual(current(self.root), expected)

    def test_initial_git_install_backs_up_exact_legacy_or_missing_bytes(self):
        for missing in (True, False):
            with self.subTest(missing=missing):
                root = self.root.parent / ("missing" if missing else "legacy")
                install_git_ref(root, "tracked")
                shared = sets.paths(root)["shared"]
                if missing:
                    shared.unlink()
                else:
                    shared.write_bytes(b"existing local independent compile")
                initial = sets.read_status(root)
                self.assertIsNone(initial["active"])
                self.assertIsNone(initial["indexSha256"])
                self.assertIn("legacyGitTree", initial)
                self.assertNotIn("gitTree", initial)
                self.assertFalse((root / "tmp").exists())
                kill_during(root, self.candidate, "shared")
                self.assertEqual(sets.recover(root), initial)
                self.assertEqual(sets.file_hash(shared), initial["installed"]["shared"])
                complete = sets.commit(root, self.candidate, self.new, initial)
                self.assertEqual(complete["active"], self.new)
                backup = sets.read_json(root / sets.STATE_DIR / "last-good.json")
                self.assertEqual(backup["installed"], initial["installed"])
                self.assertEqual(backup["legacyGitTree"], initial["legacyGitTree"])
                if not missing:
                    self.assertEqual(sets.load(root / sets.STATE_DIR, "blobs", initial["installed"]["shared"]),
                                     b"existing local independent compile")
                shared.write_bytes(b"change after first successful install")
                with self.assertRaisesRegex(ValueError, "external changes"):
                    current(root)

    def test_initial_git_capture_rejects_racing_edits_and_checkout(self):
        root = self.root.parent / "other-edit"
        install_git_ref(root, "tracked")
        target = sets.paths(root)["shared"]
        target.unlink()
        initial = sets.read_status(root)
        target.write_bytes(b"edit made during compilation")
        with self.assertRaisesRegex(ValueError, "since planning"):
            sets.commit(root, self.candidate, self.new, initial)
        self.assertEqual(target.read_bytes(), b"edit made during compilation")
        target.unlink()
        (root / ".git/index.lock").touch()
        with self.assertRaisesRegex(ValueError, "checkout changed"):
            sets.commit(root, self.candidate, self.new, initial)
        (root / ".git/index.lock").unlink()
        # Even if the three bytes return to their original values, a changed
        # checkout invalidates the capture from before the new HEAD tree.
        original = {name: file.read_bytes() for name, file in sets.paths(root).items() if file.exists()}
        install_git_ref(root, "next")
        for name, file in sets.paths(root).items():
            if name in original: file.write_bytes(original[name])
            else: file.unlink()
        with self.assertRaisesRegex(ValueError, "since planning"):
            sets.commit(root, self.candidate, self.new, initial)
        self.assertEqual(sets.hashes(root), initial["installed"])

    def test_git_checkout_is_readable_but_requires_fresh_compile_proof(self):
        install_git_ref(self.root, "old")
        old_index = current(self.root)["indexSha256"]
        pulled = install_git_ref(self.root, "pulled")
        observed = current(self.root)
        self.assertIsNone(observed["active"])
        self.assertEqual(observed["indexSha256"], old_index)
        self.assertEqual(observed["installed"], sets.receipt_hashes(pulled))
        self.assertEqual(observed["gitTree"], subprocess.check_output(["git", "-C", str(self.root), "rev-parse", "HEAD^{tree}"], text=True).strip())
        (self.root / ".git/index.lock").touch()
        with self.assertRaisesRegex(ValueError, "external changes"):
            current(self.root)
        (self.root / ".git/index.lock").unlink()
        kill_during(self.root, self.candidate, "shared")
        before = sets.hashes(self.root)
        (self.root / ".git/index.lock").touch()
        with self.assertRaisesRegex(ValueError, "checkout changed"):
            sets.recover(self.root)
        self.assertEqual(sets.hashes(self.root), before)
        (self.root / ".git/index.lock").unlink()
        self.assertEqual(sets.recover(self.root), observed)
        if os.name == "nt":
            pack_script = Path(sets.__file__).parent / "cf7-packer/scripts/snapshot-asloader.ps1"
            dest = self.root.parent / "pack"
            dest.mkdir()
            subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(pack_script),
                            "-ProjectRoot", str(self.root), "-Destination", str(dest),
                            "-Modules", ",".join(sets.MODULES)], check=True)
            self.assertEqual(observed["installed"], {n: sets.file_hash(dest / p) for n, p in sets.MODULES.items()})
            (self.root / "tools").mkdir()
            shutil.copyfile(Path(sets.__file__).with_name("asloader-git-set.ps1"), self.root / "tools/asloader-git-set.ps1")
            self.check_launch_guard()
        self.assertEqual(sets.commit(self.root, self.candidate, self.new, observed)["active"], self.new)
        sets.paths(self.root)["shared"].write_bytes(b"modified by someone else")
        with self.assertRaisesRegex(ValueError, "external changes"):
            current(self.root)

    @unittest.skipUnless(os.name == "nt", "Windows FileShare")
    def test_launch_guard_interoperates_with_publisher(self):
        self.check_launch_guard()

    @unittest.skipUnless(os.name == "nt", "Windows compiler mutex")
    def test_recovery_cannot_race_an_existing_repository_compile(self):
        kill_during(self.root, self.candidate, "resident")
        before = sets.hashes(self.root)
        (self.root / "scripts/compile_test.ps1").touch()
        repo_id = sets.sha(str(self.root).upper().encode())[:24].upper()
        env = dict(os.environ, ASLOADER_TEST_MUTEX="Local\\CF7_FlashCompile_" + repo_id)
        cmd = """
$m = [Threading.Mutex]::new($true, $env:ASLOADER_TEST_MUTEX)
try { [Console]::WriteLine('held'); [void][Console]::ReadLine() }
finally { $m.ReleaseMutex(); $m.Dispose() }
"""
        with subprocess.Popen(["powershell.exe", "-NoProfile", "-Command", cmd], env=env,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as child:
            try:
                self.assertEqual(child.stdout.readline().strip(), "held")
                with self.assertRaisesRegex(ValueError, "CS6 owner"):
                    sets.recover(self.root)
            finally:
                child.communicate("\n", timeout=15)
        self.assertEqual(sets.hashes(self.root), before)

    def check_launch_guard(self):
        # Load only the verified helper function from the actual launch script.
        # This never starts a game, enumerates processes, or touches real slots.
        start = Path(sets.__file__).resolve().parents[1] / "automation/start.ps1"
        code = """
$ErrorActionPreference='Stop'
$ast=[Management.Automation.Language.Parser]::ParseFile($env:ASLOADER_TEST_START,[ref]$null,[ref]$null)
foreach ($function in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Enter-AsLoaderReadGuard','Get-Cf7Sha256')},$true)) {
    . ([ScriptBlock]::Create($function.Extent.Text))
}
$lock=Enter-AsLoaderReadGuard $env:ASLOADER_TEST_ROOT
try { [Console]::Out.WriteLine('ready'); [void][Console]::ReadLine() } finally { $lock.Dispose() }
"""
        env = dict(os.environ, ASLOADER_TEST_START=str(start), ASLOADER_TEST_ROOT=str(self.root))
        with subprocess.Popen(["powershell.exe", "-NoProfile", "-Command", code], env=env,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as child:
            try:
                self.assertEqual(child.stdout.readline().strip(), "ready")
                with self.assertRaises(OSError):
                    sets.commit(self.root, self.candidate, self.new, current(self.root))
            finally:
                child.communicate("\n", timeout=15)


if __name__ == "__main__":
    unittest.main()
