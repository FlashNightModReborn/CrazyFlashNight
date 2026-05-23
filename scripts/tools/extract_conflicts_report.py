import os, re, glob
from html import unescape as html_unescape

THINGS_DIR = 'flashswf/arts/things'
LIBRARY_DIR = os.path.join(THINGS_DIR, 'LIBRARY')

SYMBOL_RE = re.compile(
    r'<DOMSymbolItem\b[^>]*?\bname="([^"]+)"[^>]*?'
    r'linkageExportForAS="true"[^>]*?'
    r'linkageIdentifier="([^"]+)"'
)

conflicts = []

for xml_file in glob.glob(os.path.join(LIBRARY_DIR, '**', '*.xml'), recursive=True):
    with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read(2000)
    m = SYMBOL_RE.search(content)
    if m:
        old_name_raw = m.group(1)
        old_name = html_unescape(old_name_raw)
        lid = html_unescape(m.group(2))
        if 'Symbol' in old_name and old_name != lid:
            folder = old_name.rsplit('/', 1)[0] if '/' in old_name else ''
            new_name = (folder + '/' + lid) if folder else lid
            new_file = os.path.join(LIBRARY_DIR, new_name.replace('/', os.sep) + '.xml')
            if os.path.exists(new_file) and new_file != xml_file:
                with open(new_file, 'r', encoding='utf-8', errors='replace') as f:
                    target_content = f.read(2000)
                tm = SYMBOL_RE.search(target_content)
                if tm:
                    target_sym = html_unescape(tm.group(1))
                    target_lid = html_unescape(tm.group(2))
                    conflicts.append({
                        'old_file': os.path.relpath(xml_file, LIBRARY_DIR).replace('\\', '/'),
                        'old_name': old_name,
                        'old_linkage': lid,
                        'target_file': os.path.relpath(new_file, LIBRARY_DIR).replace('\\', '/'),
                        'target_name': target_sym,
                        'target_linkage': target_lid
                    })

report_path = 'scripts/tools/things_conflict_report.md'
with open(report_path, 'w', encoding='utf-8') as f:
    f.write('# things.xfl A类符号重命名冲突报告\n\n')
    f.write(f'共发现 **{len(conflicts)}** 个冲突。这些冲突需要手动在 Flash CS6 中处理。\n\n')
    f.write('## 冲突详情\n\n')
    for i, c in enumerate(conflicts, 1):
        f.write(f'### {i}. {c["old_name"]}\n\n')
        f.write(f'- **旧 A 类文件**: `{c["old_file"]}`, `{c["old_linkage"]}`\n')
        f.write(f'- **目标文件已存在**: `{c["target_file"]}`, `{c["target_linkage"]}`\n')
        f.write(f'- **问题**: 两个符号的 linkageIdentifier 似乎被历史性地交换了（copy-paste 错误）。\n')
        f.write(f'- **建议**: 在 Flash CS6 中打开 `things.fla`，检查这两个符号的内容和 linkageIdentifier，手动修正。\n\n')

print(f'Report written to {report_path}')
