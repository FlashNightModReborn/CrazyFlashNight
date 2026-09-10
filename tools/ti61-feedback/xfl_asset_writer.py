"""缓冲血剑自有 XFL 变更；单文件原子替换，提交异常时恢复已改文件。"""
from pathlib import Path
import os
import tempfile


class AssetWriter:
    OWNED_PREFIX = Path('LIBRARY/Codex/Ti61-血剑战技')

    def __init__(self, root, owned_prefix):
        self.root = Path(root).resolve(strict=True)
        prefix = Path(owned_prefix)
        if prefix != self.OWNED_PREFIX:
            raise ValueError('owned_prefix 必须为 LIBRARY/Codex/Ti61-血剑战技')
        self._changes = {}

    def _path(self, path, retiring=False):
        path = Path(path)
        candidate = path if path.is_absolute() else self.root / path
        # 禁止通过现有符号链接或 junction 写到另一份目录/资产。
        for item in (candidate, *candidate.parents):
            if item == self.root:
                break
            if item.is_symlink() or getattr(item, 'is_junction', lambda: False)():
                raise ValueError('写入路径不得包含链接: ' + str(item))
        resolved = candidate.resolve()
        relative = resolved.relative_to(self.root)
        is_dom = relative == Path('DOMDocument.xml')
        is_owned = relative.is_relative_to(self.OWNED_PREFIX) and relative.suffix == '.xml'
        if not (is_dom or is_owned) or (retiring and not is_owned):
            raise ValueError('路径不属于允许的 XFL 写入范围: ' + str(relative))
        if resolved.exists() and not resolved.is_file():
            raise ValueError('目标不是普通文件: ' + str(resolved))
        return resolved

    def add(self, path, data):
        if not isinstance(data, bytes):
            raise TypeError('data 必须为 bytes')
        self._changes[self._path(path)] = data

    def retire(self, path):
        """仅登记调用方明确指定的自有 XML 文件，不接受目录或通配符。"""
        self._changes[self._path(path, retiring=True)] = None

    def commit(self):
        """异常恢复是本进程内的保证；不是跨文件原子可见或断电恢复协议。"""
        created_dirs, temporary, staged, backups, changed = [], set(), {}, {}, []

        def ensure_parent(parent):
            missing = []
            while not parent.exists():
                missing.append(parent)
                parent = parent.parent
            for directory in reversed(missing):
                directory.mkdir()
                created_dirs.append(directory)

        def stage(path, data):
            fd, name = tempfile.mkstemp(prefix='.ti61-', suffix='.tmp', dir=path.parent)
            staged_path = Path(name)
            temporary.add(staged_path)
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            return staged_path

        try:
            # 再检查路径，并在触碰任何目标之前准备全部新字节与旧字节。
            for path, data in self._changes.items():
                self._path(path, retiring=data is None)
                old = path.read_bytes() if path.exists() else None
                if old == data:
                    continue
                ensure_parent(path.parent)
                backups[path] = stage(path, old) if old is not None else None
                staged[path] = stage(path, data) if data is not None else None
            for path, source in staged.items():
                if source is None:
                    path.unlink()
                else:
                    os.replace(source, path)
                changed.append(path)
        except BaseException as error:
            rollback_errors = []
            for path in reversed(changed):
                try:
                    if backups[path] is None:
                        path.unlink()
                    else:
                        os.replace(backups[path], path)
                except OSError as rollback_error:
                    rollback_errors.append(str(path) + ': ' + str(rollback_error))
            if rollback_errors:
                # 若介质/权限持续失败，不假称恢复成功；保留可用备份供修复。
                for backup in backups.values():
                    if backup is not None and backup.exists():
                        temporary.discard(backup)
                raise RuntimeError('恢复失败；保留 .ti61-*.tmp 备份: ' + '; '.join(rollback_errors)) from error
            raise
        finally:
            for path in temporary:
                path.unlink(missing_ok=True)
            for directory in reversed(created_dirs):
                try:
                    directory.rmdir()
                except OSError:
                    pass  # 成功发布的新文件或外部新增文件仍在目录内。
        self._changes.clear()
