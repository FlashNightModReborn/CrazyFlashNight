"""Fingerprint the AS2 compiler, its resolved built-in classpath and CS6 control files."""
import hashlib
import json
import os
import stat
from pathlib import Path


def file_hash(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def identity(parts):
    encoded = json.dumps(parts, sort_keys=True, separators=(',', ':'), ensure_ascii=True)
    return hashlib.sha256(encoded.encode('ascii')).hexdigest()


def inspect(repo, executable, loader):
    import winreg
    executable, loader = Path(executable).resolve(strict=True), Path(loader).resolve(strict=True)
    configuration = loader.parent.parent
    cfg = loader.parent / 'flash_project_path.cfg'
    expected_uri = 'file:///' + repo.as_posix().replace(':', '|', 1)
    if (executable.name.lower() != 'flash.exe' or loader.name != 'cf7_compile_loader.jsfl'
            or cfg.read_text(encoding='utf-8-sig').strip().casefold() != expected_uri.casefold()):
        raise ValueError('Flash executable or Commands path does not bind the current checkout')
    key = r'Software\Adobe\Flash 12\ActionsInspector'
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key, 0, winreg.KEY_READ | winreg.KEY_WOW64_32KEY) as cfg_key:
        package_paths = winreg.QueryValueEx(cfg_key, 'Package Paths')[0]
    paths = [p.strip().replace('\\', '/').lower() for p in package_paths.split(';') if p.strip()]
    if paths != ['.', '$(localdata)/classes']:
        raise ValueError('Unsupported external AS2 Package Paths: ' + package_paths)
    install = executable.parent
    installed_classes = install / 'Common/First Run/Classes'
    local_classes = configuration / 'Classes'
    if not (local_classes / 'toplevel.as').is_file() or not (installed_classes / 'toplevel.as').is_file():
        raise ValueError('Cannot identify the installed ActionScript 2.0 SDK')
    files = {str(p): file_hash(p) for p in (executable, loader, cfg)}
    for p in sorted(install.glob('*.dll')):
        files[str(p)] = file_hash(p)
    for folder in (local_classes, installed_classes, configuration / 'Include',
                   install / 'Common/First Run/Include', install / 'Common/Configuration/ActionScript',
                   install / 'Common/Configuration/Players', install / configuration.parent.name / 'Configuration/Players'):
        if not folder.exists():
            files[str(folder)] = None
            continue
        if folder.resolve() != folder:
            raise ValueError('Redirected SDK directory: ' + str(folder))
        def fail_walk(error):
            raise error
        for directory, dirs, names in os.walk(folder, onerror=fail_walk):
            directory = Path(directory)
            dirs[:] = sorted(d for d in dirs if d.casefold() != 'aso')
            for name in dirs:
                child = directory / name
                if child.lstat().st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
                    raise ValueError('Redirected SDK directory: ' + str(child))
            for name in sorted(names):
                path = directory / name
                if path.suffix.lower() not in ('.as', '.asi', '.xml', '.swc', '.dll', '.jsfl'):
                    continue
                if path.resolve() != path:
                    raise ValueError('Redirected SDK input: ' + str(path))
                if folder == local_classes and not (installed_classes / path.relative_to(folder)).is_file():
                    raise ValueError('Unmanaged class in the global AS2 classpath: ' + str(path))
                files[str(path)] = file_hash(path)
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers') as flags:
            compatibility = winreg.QueryValueEx(flags, str(executable))[0]
    except FileNotFoundError:
        compatibility = ''
    for rel in ('scripts/compile_test.ps1','scripts/compile_action.jsfl','scripts/publish-asloader-modules.ps1',
                'tools/publish_asloader_incremental.py','tools/asloader_toolchain.py'):
        files[rel] = file_hash(repo / rel)
    description = {'schema': 1, 'flash': str(executable), 'commands': str(loader),
                   'globalPackagePaths': package_paths, 'compatibility': compatibility,
                   'components': files}
    return identity(description), description
