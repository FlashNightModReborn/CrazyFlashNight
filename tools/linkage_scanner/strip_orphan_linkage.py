# encoding: utf-8
"""Strip linkageExportForAS attributes from orphan XMLs inside a .fla zip.

Usage:
  python tools/linkage_scanner/strip_orphan_linkage.py
"""
import os, sys, zipfile, shutil, re

sys.stdout.reconfigure(encoding='utf-8')

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(HERE))
FLA_PATH = os.path.join(PROJECT_ROOT, 'flashswf', 'arts', 'new', '变体武器.fla')
BACKUP_PATH = FLA_PATH + '.bak'

# Orphan XMLs to strip linkage from (verified not referenced by DOMDocument.xml)
TARGETS = {
    'LIBRARY/1.枪械相关/长枪/图标-Sniper.xml':    '图标-Sniper',
    'LIBRARY/1.枪械相关/长枪/枪-长枪-Sniper.xml': '枪-长枪-Sniper',
    'LIBRARY/1.枪械相关/长枪/图标-AUG.xml':       '图标-AUG',
    'LIBRARY/1.枪械相关/长枪/枪-长枪-AUG.xml':    '枪-长枪-AUG',
}


def strip_linkage(content: str, lid: str) -> str:
    """Remove linkageExportForAS='true' linkageIdentifier='X' from first line."""
    # Match ' linkageExportForAS="true" linkageIdentifier="<lid>"' (leading space)
    pat = r' linkageExportForAS="true" linkageIdentifier="' + re.escape(lid) + r'"'
    new_content, n = re.subn(pat, '', content, count=1)
    return new_content, n


def main():
    if not os.path.exists(FLA_PATH):
        print(f"ERROR: {FLA_PATH} not found")
        sys.exit(1)

    # Backup
    if not os.path.exists(BACKUP_PATH):
        shutil.copy2(FLA_PATH, BACKUP_PATH)
        print(f"Backup created: {BACKUP_PATH}")
    else:
        print(f"Backup already exists, not overwriting: {BACKUP_PATH}")

    # Read original zip; write new zip with patched entries
    out_path = FLA_PATH + '.new'
    patched_count = 0

    with zipfile.ZipFile(FLA_PATH, 'r') as zin:
        # Capture original member list and preserve order
        with zipfile.ZipFile(out_path, 'w') as zout:
            # First, write mimetype with STORED (no compression), if it exists first
            names = zin.namelist()
            first = names[0] if names else None

            for name in names:
                info = zin.getinfo(name)
                data = zin.read(name)

                # If target XML, patch linkage
                norm_name = name.replace('\\', '/')
                if norm_name in TARGETS:
                    lid = TARGETS[norm_name]
                    text = data.decode('utf-8')
                    new_text, n = strip_linkage(text, lid)
                    if n > 0:
                        data = new_text.encode('utf-8')
                        patched_count += 1
                        print(f"  PATCHED: {norm_name}  (linkage='{lid}' removed)")
                    else:
                        print(f"  SKIP   : {norm_name}  (linkage='{lid}' not found in header)")

                # Preserve compression method per original entry
                new_info = zipfile.ZipInfo(filename=name, date_time=info.date_time)
                new_info.compress_type = info.compress_type
                new_info.external_attr = info.external_attr
                new_info.create_system = info.create_system
                zout.writestr(new_info, data)

    print(f"\nPatched {patched_count}/{len(TARGETS)} target XMLs")

    if patched_count > 0:
        # Atomic replace
        os.replace(out_path, FLA_PATH)
        print(f"Updated: {FLA_PATH}")
    else:
        os.remove(out_path)
        print("No changes, .new discarded")


if __name__ == '__main__':
    main()
