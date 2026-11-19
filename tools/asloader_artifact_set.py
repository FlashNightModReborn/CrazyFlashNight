"""Publish and recover the three fixed asLoader paths as one controlled set."""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile


MODULES = {"resident": "asLoader.swf", "shared": "asLoaderShared.swf", "boot": "asLoaderLogic.swf"}
STATE_DIR = Path("tmp/asloader-artifact-set")
HASH = re.compile(r"[a-f0-9]{64}")


def fail(message):
    raise ValueError(message)


def checked_path(path):
    # Do not follow junctions into another tree when restoring backed-up bytes.
    try:
        info = path.lstat()
    except FileNotFoundError:
        return path
    if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
        fail(f"Unexpected reparse point: {path}")
    return path


def validated_hash(value):
    if not isinstance(value, str) or not HASH.fullmatch(value.lower()):
        fail("Invalid SHA-256 in artifact-set evidence")
    return value.lower()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_hash(path):
    checked_path(path)
    if not path.exists():
        return None
    if not path.is_file():
        fail(f"Not a regular file: {path}")
    return sha(path.read_bytes())


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def read_json(path):
    return json.loads(checked_path(path).read_text("utf-8-sig"))


def sync_directory(directory):
    if os.name != "nt":
        fd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def atomic_write(path, data):
    checked_path(path)
    fd, tmp = tempfile.mkstemp(prefix=".asloader-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes
            move = ctypes.WinDLL("kernel32", use_last_error=True).MoveFileExW
            move.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD]
            if not move(tmp, str(path), 0x1 | 0x8):  # REPLACE_EXISTING | WRITE_THROUGH
                raise ctypes.WinError(ctypes.get_last_error())
        else:
            os.replace(tmp, path)
            sync_directory(path.parent)
    finally:
        Path(tmp).unlink(missing_ok=True)


@contextlib.contextmanager
def lock(root, writer=False):
    directory = checked_path(checked_path(root / "tmp") / "asloader-artifact-set")
    directory.mkdir(parents=True, exist_ok=True)
    path = checked_path(directory / "guard.lock")
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        create = kernel.CreateFileW
        create.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID,
                           wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        create.restype = wintypes.HANDLE
        handle = create(str(path), 0x80000000, 0 if writer else 1, None, 4, 0x80, None)
        if handle == wintypes.HANDLE(-1).value:
            raise OSError("The asLoader artifact set is busy or inaccessible: " + str(ctypes.WinError(ctypes.get_last_error())))
        try:
            yield directory
        finally:
            kernel.CloseHandle(wintypes.HANDLE(handle))
    else:
        import fcntl
        with path.open("a+b") as stream:
            fcntl.flock(stream, (fcntl.LOCK_EX if writer else fcntl.LOCK_SH) | fcntl.LOCK_NB)
            yield directory


def paths(root):
    scripts = checked_path(root / "scripts")
    return {name: checked_path(scripts / file) for name, file in MODULES.items()}


def hashes(root):
    return {n: file_hash(p) for n, p in paths(root).items()}


def receipt_hashes(receipt):
    modules = receipt["modules"]
    if not isinstance(modules, dict) or set(modules) != set(MODULES):
        fail("Set receipt must contain exactly resident, shared, boot")
    return {name: validated_hash(modules[name]["sha256"]) for name in MODULES}


def store(directory, group, data):
    folder = checked_path(directory / group)
    folder.mkdir(exist_ok=True)
    digest = sha(data)
    address = checked_path(folder / digest)
    if not address.exists():
        atomic_write(address, data)
    elif file_hash(address) != digest:
        fail(f"Damaged immutable {group}: {digest}")
    return digest


def load(directory, group, digest):
    address = checked_path(checked_path(directory / group) / validated_hash(digest))
    data = address.read_bytes()
    if sha(data) != digest:
        fail(f"Damaged immutable {group}: {digest}")
    return data


def active(directory):
    index = checked_path(directory / "active.json")
    if not index.exists():
        return None, None
    data = index.read_bytes()
    digest = validated_hash(json.loads(data)["receiptSha256"])
    return json.loads(load(directory, "receipts", digest)), sha(data)


def check_no_pending(directory):
    if checked_path(directory / "pending.json").exists():
        fail("Pending asLoader set transaction requires recovery")


def git_set(root, installed):
    if not (root / ".git").exists():
        return None
    if os.name == "nt":
        helper = Path(__file__).with_name("asloader-git-set.ps1")
        cmd = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
               "-File", str(helper), "-ProjectRoot", str(root)]
        result = subprocess.run(cmd, capture_output=True)
        if result.returncode == 0 and result.stdout.strip():
            proof = json.loads(result.stdout)
            if proof["installed"] == installed:
                return proof["tree"]
        return None
    def git(*args):
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(root), *args],
                                       stderr=subprocess.DEVNULL).strip()
    try:
        if Path(os.fsdecode(git("rev-parse", "--show-toplevel"))).resolve() != root:
            return None
        index_lock = Path(os.fsdecode(git("rev-parse", "--path-format=absolute", "--git-path", "index.lock")))
        tree = git("rev-parse", "--verify", "HEAD^{tree}").decode("ascii")
        if index_lock.exists() or not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", tree):
            return None
        for name, base in MODULES.items():
            rel = "scripts/" + base
            row = git("ls-tree", tree, "--", rel).decode("ascii")
            match = re.fullmatch(r"100(?:644|755) blob ([0-9a-f]+)\t" + re.escape(rel), row)
            if not match:
                return None
            data = checked_path(root / rel).read_bytes()
            digest = hashlib.new("sha1" if len(tree) == 40 else "sha256")
            digest.update(f"blob {len(data)}\0".encode("ascii"))
            digest.update(data)
            if digest.hexdigest() != match[1] or sha(data) != installed[name]:
                return None
        return tree if not index_lock.exists() and tree == git("rev-parse", "--verify", "HEAD^{tree}").decode("ascii") else None
    except (OSError, subprocess.SubprocessError, UnicodeError):
        return None


def checkout_tree(root):
    def git(*args):
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(root), "rev-parse", *args],
                                       stderr=subprocess.DEVNULL).strip()
    top = Path(os.fsdecode(git("--show-toplevel"))).resolve()
    lock_path = Path(os.fsdecode(git("--path-format=absolute", "--git-path", "index.lock")))
    if top != root or lock_path.exists():
        fail("Git checkout changed during asLoader transaction; preserving both versions")
    tree = git("--verify", "HEAD^{tree}").decode("ascii")
    if lock_path.exists() or not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", tree):
        fail("Git checkout changed during asLoader transaction; preserving both versions")
    return tree


def check_checkout(root, tree):
    if tree is not None and checkout_tree(root) != tree:
        fail("Git checkout changed during asLoader transaction; preserving both versions")


def initial_state(root, installed):
    result = {"active": None, "indexSha256": None, "installed": installed}
    if (root / ".git").exists():
        # A never-managed install may contain unpublished local builds or missing
        # targets. Capture exactly what will be backed up. This is not a receipt.
        result["legacyGitTree"] = checkout_tree(root)
    return result


def status(root, directory, diagnostic=False):
    check_no_pending(directory)
    receipt, index_sha = active(directory)
    installed = hashes(root)
    if receipt is None and checked_path(directory / "last-good.json").exists():
        fail("Managed asLoader set lost its active index")
    if receipt is None:
        return initial_state(root, installed)
    result = {"active": receipt, "indexSha256": index_sha, "installed": installed}
    if receipt:
        trusted = receipt_hashes(receipt)
        wrong = [name for name in MODULES if installed[name] != trusted[name]]
        if wrong:
            tree = git_set(root, installed)
            if tree:
                # Preserve the observed index for compare-and-swap, but never
                # transfer a previous compile's proof onto a checkout's bytes.
                return dict(result, active=None, gitTree=tree)
            reason = "Installed asLoader bytes differ from the active receipt; preserving external changes"
            if diagnostic:
                return dict(result, state="INVALID", reason=reason, differing=wrong)
            fail(reason)
    return result


def read_status(root, diagnostic=False):
    root = root.resolve()
    directory = checked_path(checked_path(root / "tmp") / "asloader-artifact-set")
    admission(root)
    # A first writer creates this directory before touching any target bytes.
    # If it appears during the read, repeat the observation under the OS lock.
    if not directory.exists():
        installed = hashes(root)
        if not directory.exists():
            return initial_state(root, installed)
    with lock(root) as directory:
        admission(root)
        return status(root, directory, diagnostic)


def admission(root):
    for marker in ("compile_state_uncertain.marker", "testhost_ownership.marker", "testplayer_control.cfg",
                   "testloader_scratch_inflight.marker"):
        if (root / "scripts" / marker).exists():
            fail(f"Unresolved Flash state: {marker}")


def no_consumers(root):
    # Isolated output-only roots have neither a game entry nor a Guardian.
    ports = root / "launcher_ports.json"
    if not (ports.exists() or (root / "CRAZYFLASHER7MercenaryEmpire.swf").exists()
            or (root / "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe").exists()):
        return
    if os.name == "nt":
        probe = Path(__file__).with_name("assert-asloader-consumers-idle.ps1")
        subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                        "-File", str(probe), "-ProjectRoot", str(root)], check=True, stdout=sys.stderr)
    elif ports.exists():
        pid = int(read_json(ports)["pid"])
        if pid <= 0:
            fail("Invalid Guardian process identity")
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        fail(f"Guardian {pid} can still consume this asLoader set")


@contextlib.contextmanager
def recovery_compile_lock(root):
    if os.name != "nt" or not (root / "scripts/compile_test.ps1").is_file():
        yield
        return
    # Explicit/legacy CS6 calls may target the same final SWFs. A live owner
    # does not necessarily have an uncertain marker; hold both actual mutexes
    # while recovering a development checkout. Output-only fixtures have none.
    import ctypes
    from ctypes import wintypes
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    create = kernel.CreateMutexW
    create.argtypes = [wintypes.LPVOID, wintypes.BOOL, wintypes.LPCWSTR]
    create.restype = wintypes.HANDLE
    repo_id = sha(str(root).rstrip("\\").upper().encode("utf-8"))[:24].upper()
    with contextlib.ExitStack() as held:
        for name in ("Local\\CF7_FlashCompile_" + repo_id, "Local\\CF7_FlashCompile_MachineGlobal"):
            handle = create(None, False, name)
            if not handle:
                raise ctypes.WinError(ctypes.get_last_error())
            handle = wintypes.HANDLE(handle)
            held.callback(kernel.CloseHandle, handle)
            wait = kernel.WaitForSingleObject(handle, 0)
            if wait not in (0, 0x80):
                fail("Active or unobservable CS6 owner blocks asLoader recovery")
            held.callback(kernel.ReleaseMutex, handle)
            if wait == 0x80:
                marker = root / "scripts/compile_state_uncertain.marker"
                try:
                    with marker.open("x", encoding="utf-8") as out:
                        out.write("Abandoned CS6 compile mutex observed during asLoader recovery: " + name)
                except FileExistsError:
                    pass
                fail("Unknown previous CS6 owner; preserving the journal")
        yield


def assert_expected(now, expected):
    if (now["indexSha256"] != expected["indexSha256"] or now["installed"] != expected["installed"]
            or now.get("gitTree") != expected.get("gitTree") or now.get("legacyGitTree") != expected.get("legacyGitTree")):
        fail("Active index or installed files changed since planning")


def unlink_durable(path):
    checked_path(path).unlink()
    sync_directory(path.parent)


def finish_commit(directory, journal):
    # This recovery copy is local to the development tree. Only the previous
    # and current sets need blob storage; immutable receipts remain available.
    previous = {"indexSha256": journal["oldIndexSha256"], "installed": journal["old"],
                "gitTree": journal.get("oldGitTree"), "legacyGitTree": journal.get("legacyGitTree")}
    atomic_write(directory / "last-good.json", json_bytes(previous))


def trim_blobs(directory, journal):
    keep = set(journal["old"].values()) | set(journal["new"].values())
    try:
        for blob in checked_path(directory / "blobs").iterdir():
            if blob.name not in keep and HASH.fullmatch(blob.name) and file_hash(blob) == blob.name:
                blob.unlink()
    except (OSError, ValueError) as exc:
        # Non-critical cleanup follows the commit and cannot invalidate it.
        print("Retaining older asLoader recovery bytes: " + str(exc), file=sys.stderr)


def commit(root, candidate, receipt, expected, checkpoint=lambda step: None):
    with lock(root, writer=True) as directory:
        admission(root)
        before = status(root, directory)
        assert_expected(before, expected)
        old = before["installed"]
        new = receipt_hashes(receipt)
        old_tree = before.get("gitTree")
        checkout = old_tree or before.get("legacyGitTree")
        source = paths(candidate)
        for name in MODULES:
            if file_hash(source[name]) != new[name]:
                fail(f"Candidate and receipt differ: {name}")
        prior_index = before["indexSha256"]
        if receipt == before["active"]:
            return before
        receipt_sha = store(directory, "receipts", json_bytes(receipt))
        index_data = json_bytes({"receiptSha256": receipt_sha})
        if new == old and before["active"] is not None:
            atomic_write(directory / "active.json", index_data)
            return status(root, directory)

        no_consumers(root)
        targets = paths(root)
        for name in MODULES:
            if old[name] and store(directory, "blobs", targets[name].read_bytes()) != old[name]:
                fail(f"Installed bytes changed before backup: {name}")
            if store(directory, "blobs", source[name].read_bytes()) != new[name]:
                fail(f"Candidate bytes changed before installation: {name}")
        checked_path(root / "scripts").mkdir(exist_ok=True)
        check_checkout(root, checkout)
        journal = {"version": 1, "old": old, "new": new, "oldGitTree": old_tree, "legacyGitTree": before.get("legacyGitTree"),
                   "oldIndexSha256": prior_index,
                   "newIndexSha256": sha(index_data), "newReceiptSha256": receipt_sha}
        atomic_write(directory / "pending.json", json_bytes({"transaction": journal, "sha256": sha(json_bytes(journal))}))
        checkpoint("journal")
        for name, target in targets.items():
            check_checkout(root, checkout)
            if file_hash(target) != old[name]:
                fail(f"Unrecognized bytes appeared during installation: {name}")
            if old[name] != new[name]:
                atomic_write(target, load(directory, "blobs", new[name]))
            checkpoint(name)
        check_checkout(root, checkout)
        if hashes(root) != new or active(directory)[1] != prior_index:
            fail("Set changed before index commit")
        atomic_write(directory / "active.json", index_data)
        checkpoint("index")
        finish_commit(directory, journal)
        unlink_durable(directory / "pending.json")
        trim_blobs(directory, journal)
        return status(root, directory)


def recover(root, checkpoint=lambda step: None):
    with recovery_compile_lock(root), lock(root, writer=True) as directory:
        admission(root)
        pending = checked_path(directory / "pending.json")
        if not pending.exists():
            return status(root, directory)
        no_consumers(root)
        envelope = read_json(pending)
        journal = envelope["transaction"]
        if sha(json_bytes(journal)) != envelope["sha256"]:
            fail("Damaged artifact set journal")
        old, new = journal["old"], journal["new"]
        if journal["version"] != 1 or set(old) != set(MODULES) or set(new) != set(MODULES):
            fail("Unknown transaction journal")
        receipt_sha = validated_hash(journal["newReceiptSha256"])
        if (sha(json_bytes({"receiptSha256": receipt_sha})) != journal["newIndexSha256"]
                or receipt_hashes(json.loads(load(directory, "receipts", receipt_sha))) != new):
            fail("Journal and new receipt disagree")
        installed = hashes(root)
        for name in MODULES:
            if old[name] is not None:
                load(directory, "blobs", validated_hash(old[name]))
            if installed[name] not in (old[name], new[name]):
                fail(f"Unknown bytes during recovery: {name}")
        current, index_sha = active(directory)
        old_tree = journal.get("oldGitTree")
        checkout = old_tree or journal.get("legacyGitTree")
        if journal.get("legacyGitTree") and (old_tree or journal["oldIndexSha256"] is not None):
            fail("Invalid initial-capture journal")
        check_checkout(root, checkout)
        committed = index_sha == journal["newIndexSha256"] and installed == new
        if committed:
            finish_commit(directory, journal)
        elif index_sha == journal["oldIndexSha256"] and (current is None or old_tree or receipt_hashes(current) == old):
            for name, target in paths(root).items():
                check_checkout(root, checkout)
                if installed[name] != old[name]:
                    if file_hash(target) != new[name]:
                        fail(f"External modification during rollback: {name}")
                    if old[name] is None:
                        unlink_durable(target)
                    else:
                        atomic_write(target, load(directory, "blobs", old[name]))
                checkpoint("restore-" + name)
            if hashes(root) != old:
                fail("Rollback did not restore the full previous set")
            if old_tree and git_set(root, old) != old_tree:
                fail("Restored set no longer matches the verified Git checkout")
        else:
            fail("Active index does not identify the old or fully installed new set")
        unlink_durable(pending)
        if committed:
            trim_blobs(directory, journal)
        return status(root, directory)


def copy_for_reader(root, destination, names):
    state = checked_path(checked_path(root / "tmp") / "asloader-artifact-set")
    sources = paths(root)
    if not state.exists():
        data = {name: sources[name].read_bytes() for name in names}
        if not state.exists():
            for name, content in data.items():
                with (destination / MODULES[name]).open("xb") as out:
                    out.write(content)
            return
    with lock(root) as directory:
        current = status(root, directory)
        for name in names:
            if name not in MODULES:
                fail(f"Unknown module: {name}")
            data = sources[name].read_bytes()
            if sha(data) != current["installed"][name]:
                fail(f"Source changed while snapshotting {name}")
            with (destination / MODULES[name]).open("xb") as out:
                out.write(data)
        if "gitTree" in current and git_set(root, current["installed"]) != current["gitTree"]:
            fail("Git checkout changed while snapshotting asLoader modules")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("get", "commit", "recover", "copy"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--root", type=Path, required=True)
        if name == "get":
            cmd.add_argument("--diagnostic", action="store_true")
        elif name == "commit":
            for option in ("candidate", "receipt", "expected"):
                cmd.add_argument("--" + option, type=Path, required=True)
        elif name == "copy":
            cmd.add_argument("--destination", type=Path, required=True)
            cmd.add_argument("--modules", nargs="+", choices=MODULES, required=True)
    args = parser.parse_args()
    root = args.root.resolve(strict=args.command != "get")
    if args.command == "commit":
        result = commit(root, args.candidate.resolve(strict=True), read_json(args.receipt), read_json(args.expected))
    elif args.command == "recover":
        result = recover(root)
    elif args.command == "copy":
        copy_for_reader(root, args.destination.resolve(strict=True), args.modules)
        result = {"copied": args.modules}
    else:
        result = read_status(root, diagnostic=args.diagnostic)
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        sys.exit("asLoader artifact set: " + str(exc))
