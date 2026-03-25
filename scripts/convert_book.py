"""
gomoku_book_raw.json + book_patches.txt -> GobangBook.as (数值键, UTF-8 BOM)

用法:
  python scripts/convert_book.py                    # 从 JSON 生成
  python scripts/convert_book.py --patches-only     # 只看 patches 文件
  python scripts/convert_book.py --dry-run          # 不写文件，只统计

数值键编码: flat = x*15+y, key = flat_0 + flat_1*225 + flat_2*225^2 + ...
最大 9 手: 225^9 < 2^53, Number 精度安全

补丁文件格式 (book_patches.txt):
  7,7;8,8;7,8 -> 7,9   # 注释
  7,7;8,8;7,6 -> 7,8
"""
import json, sys, os, re
from pathlib import Path

BOARD_SIZE = 15
BASE = BOARD_SIZE * BOARD_SIZE  # 225
MAX_MOVES = 9

SCRIPT_DIR = Path(__file__).parent
JSON_PATH = SCRIPT_DIR / "gomoku_book_raw.json"
PATCHES_PATH = SCRIPT_DIR / "book_patches.txt"
OUTPUT_PATH = (SCRIPT_DIR / "类定义" / "org" / "flashNight" / "hana" / "Gobang" / "GobangBook.as")

# ===== 坐标工具 =====

def parse_coord_alpha(s):
    """gomoku.json 格式: 'h8' -> (row=7, col=7)"""
    col = ord(s[0]) - ord('a')
    row = BOARD_SIZE - int(s[1:])
    return (row, col)

def near_center(row, col, radius=4):
    return abs(row - 7) <= radius and abs(col - 7) <= radius

def encode_key(moves):
    """[(x0,y0), (x1,y1), ...] -> 数值键"""
    key = 0
    mul = 1
    for (x, y) in moves:
        key += (x * BOARD_SIZE + y) * mul
        mul *= BASE
    return key

def decode_key(key, length):
    """数值键 -> [(x0,y0), ...]"""
    moves = []
    for _ in range(length):
        flat = key % BASE
        moves.append((flat // BOARD_SIZE, flat % BOARD_SIZE))
        key //= BASE
    return moves

def parse_string_key(s):
    """'7,7;8,8;7,8' -> [(7,7),(8,8),(7,8)]"""
    if not s:
        return []
    parts = s.split(";")
    result = []
    for p in parts:
        x, y = p.split(",")
        result.append((int(x), int(y)))
    return result

# ===== 8 折对称 =====

def transform(x, y, t):
    """8-fold symmetry transform on 15x15 board"""
    if t == 0: return (x, y)
    if t == 1: return (y, 14 - x)
    if t == 2: return (14 - x, 14 - y)
    if t == 3: return (14 - y, x)
    if t == 4: return (x, 14 - y)
    if t == 5: return (14 - x, y)
    if t == 6: return (y, x)
    return (14 - y, 14 - x)  # t=7

INV = [0, 3, 2, 1, 4, 5, 6, 7]

def canonical_key(moves):
    """取 8 种对称变换中最小的数值键作为正规形式"""
    min_key = None
    min_t = 0
    for t in range(8):
        transformed = [transform(x, y, t) for (x, y) in moves]
        k = encode_key(transformed)
        if min_key is None or k < min_key:
            min_key = k
            min_t = t
    return min_key, min_t

# ===== JSON 提取 =====

def get_max_leaf(tree):
    if isinstance(tree, (int, float)):
        return tree
    if not isinstance(tree, dict):
        return -999999
    return max((get_max_leaf(v) for v in tree.values()), default=-999999)

def extract_entries(tree, path=None, entries=None, max_depth=5):
    if path is None: path = []
    if entries is None: entries = {}
    if not isinstance(tree, dict) or len(path) >= max_depth:
        return entries

    best_move = None
    best_score = -999999
    for move_str, subtree in tree.items():
        row, col = parse_coord_alpha(move_str)
        if not near_center(row, col):
            continue
        score = subtree if isinstance(subtree, (int, float)) else get_max_leaf(subtree)
        if score > best_score:
            best_score = score
            best_move = (row, col, move_str)

    if best_move is None:
        return entries

    # 用正规化数值键
    key_moves = list(path)
    nk, _ = canonical_key(key_moves) if key_moves else (encode_key([]), 0)
    resp_moves = key_moves + [(best_move[0], best_move[1])]
    entries[nk] = (best_move[0], best_move[1], len(key_moves))

    # 递归展开对手应手
    subtree = tree[best_move[2]]
    if isinstance(subtree, dict):
        new_path = path + [(best_move[0], best_move[1])]
        for opp_str, opp_sub in subtree.items():
            opp_row, opp_col = parse_coord_alpha(opp_str)
            if not near_center(opp_row, opp_col):
                continue
            if isinstance(opp_sub, dict):
                extract_entries(opp_sub, new_path + [(opp_row, opp_col)], entries, max_depth)
    return entries

# ===== 补丁文件 =====

def load_patches():
    """读取 book_patches.txt, 返回 {数值键: (rx, ry, depth)}"""
    patches = {}
    if not PATCHES_PATH.exists():
        return patches
    for line in PATCHES_PATH.read_text(encoding="utf-8").splitlines():
        line = line.split("#")[0].strip()
        if not line or "->" not in line:
            continue
        left, right = line.split("->")
        moves = parse_string_key(left.strip())
        rx, ry = [int(v) for v in right.strip().split(",")]
        # 正规化: 找到使 key 最小的变换, 同时变换 response
        min_key = None
        min_rx, min_ry = rx, ry
        for t in range(8):
            transformed = [transform(x, y, t) for (x, y) in moves]
            k = encode_key(transformed)
            if min_key is None or k < min_key:
                min_key = k
                trx, try_ = transform(rx, ry, t)
                min_rx, min_ry = trx, try_
        patches[min_key] = (min_rx, min_ry, len(moves))
    return patches

# ===== 从旧格式 book_entries.txt 读取 =====

def load_old_entries():
    """解析 book_entries.txt 中的 a("key", x, y) 调用"""
    entries = {}
    path = SCRIPT_DIR / "book_entries.txt"
    if not path.exists():
        return entries
    pattern = re.compile(r'a\("([^"]*)",\s*(\d+),\s*(\d+)\)')
    for line in path.read_text(encoding="utf-8").splitlines():
        m = pattern.search(line)
        if not m:
            continue
        str_key = m.group(1)
        rx, ry = int(m.group(2)), int(m.group(3))
        moves = parse_string_key(str_key)
        nk = encode_key(moves)
        entries[nk] = (rx, ry, len(moves))
    return entries

# ===== AS2 代码生成 =====

AS2_HEADER = r'''/**
 * 开局库 — 8 折对称数值键查表
 * 由 convert_book.py 自动生成，请勿手动编辑
 * 数值键: flat=x*15+y, key=flat_0 + flat_1*225 + flat_2*225^2 + ...
 * 运行时成本: O(8) 纯算术/次查询（无字符串操作）
 */
class org.flashNight.hana.Gobang.GobangBook {
    private static var _book:Object = null;
    private static var _size:Number = 0;

    // ===== 对称变换 =====
    // 15x15 棋盘 8 折对称 (x,y) -> (x',y')
    // t=0: identity, t=1: 90 CW, t=2: 180, t=3: 270 CW
    // t=4: flipH, t=5: flipV, t=6: transpose, t=7: anti-transpose
    private static function tfx(x:Number, y:Number, t:Number):Number {
        if (t === 0) return x;
        if (t === 1) return y;
        if (t === 2) return 14 - x;
        if (t === 3) return 14 - y;
        if (t === 4) return x;
        if (t === 5) return 14 - x;
        if (t === 6) return y;
        return 14 - y; // t=7
    }
    private static function tfy(x:Number, y:Number, t:Number):Number {
        if (t === 0) return y;
        if (t === 1) return 14 - x;
        if (t === 2) return 14 - y;
        if (t === 3) return x;
        if (t === 4) return 14 - y;
        if (t === 5) return y;
        if (t === 6) return x;
        return 14 - x; // t=7
    }
    // 逆变换索引: inv[t] 使得 tf(tf(p, t), inv[t]) = p
    private static var INV:Array = [0, 3, 2, 1, 4, 5, 6, 7];

    // ===== 初始化 =====
    private static function _init():Void {
        if (_book !== null) return;
        _book = {};
        _book.__proto__ = null;
        _loadEntries();
    }

    public static function getSize():Number {
        _init();
        return _size;
    }

    // ===== 数值键编码 =====
    // flat = x*15 + y, key = sum(flat_i * 225^i)
    private static function _encodeKey(history:Array, histLen:Number, t:Number):Number {
        var key:Number = 0;
        var mul:Number = 1;
        for (var i:Number = 0; i < histLen; i++) {
            var h:Object = history[i];
            key += (tfx(h.i, h.j, t) * 15 + tfy(h.i, h.j, t)) * mul;
            mul *= 225;
        }
        return key;
    }

    // ===== 查询 =====
    public static function lookup(history:Array, histLen:Number):Object {
        _init();
        if (histLen > 9 || _size === 0) return null;

        for (var t:Number = 0; t < 8; t++) {
            var key:Number = _encodeKey(history, histLen, t);
            var entry:Array = _book[key];
            if (entry !== undefined) {
                var inv:Number = INV[t];
                return {x: tfx(entry[0], entry[1], inv), y: tfy(entry[0], entry[1], inv)};
            }
        }
        return null;
    }

    // ===== 自动生成数据 =====
'''

AS2_FOOTER = r'''}
'''

def generate_as2(entries, stats_comment):
    """生成完整 AS2 源码"""
    lines = [AS2_HEADER]
    lines.append("    private static function _loadEntries():Void {")
    lines.append("        var b:Object = _book;")

    # 按 (depth, key) 排序, 使输出稳定
    sorted_items = sorted(entries.items(), key=lambda kv: (kv[1][2], kv[0]))

    for nk, (rx, ry, depth) in sorted_items:
        # 解码键用于注释
        moves = decode_key(nk, depth)
        comment_parts = []
        for (mx, my) in moves:
            comment_parts.append(f"{mx},{my}")
        key_str = ";".join(comment_parts) if comment_parts else "(root)"
        lines.append(f'        b[{nk}] = [{rx}, {ry}]; // {key_str}')

    lines.append(f"        _size = {len(entries)};")
    lines.append("    }")
    lines.append(stats_comment)
    lines.append(AS2_FOOTER)
    return "\n".join(lines)


def main():
    dry_run = "--dry-run" in sys.argv
    patches_only = "--patches-only" in sys.argv

    # 1. 加载主数据
    if patches_only:
        entries = {}
    elif JSON_PATH.exists():
        with open(JSON_PATH, encoding="utf-8") as f:
            data = json.load(f)
        entries = extract_entries(data, max_depth=5)
        print(f"[INFO] JSON: {len(entries)} entries extracted", file=sys.stderr)
    else:
        # 回退到旧格式
        entries = load_old_entries()
        print(f"[INFO] book_entries.txt fallback: {len(entries)} entries", file=sys.stderr)

    # 2. 合并补丁
    patches = load_patches()
    if patches:
        for k, v in patches.items():
            entries[k] = v
        print(f"[INFO] Patches: {len(patches)} entries merged", file=sys.stderr)

    # 3. 统计
    depth_counts = {}
    for nk, (rx, ry, depth) in entries.items():
        depth_counts[depth] = depth_counts.get(depth, 0) + 1
    stats_lines = [f"\n    // Total: {len(entries)} entries"]
    for d in sorted(depth_counts):
        stats_lines.append(f"    //   depth {d}: {depth_counts[d]}")
    stats_comment = "\n".join(stats_lines)

    print(f"[INFO] Total: {len(entries)} entries", file=sys.stderr)
    for d in sorted(depth_counts):
        print(f"[INFO]   depth {d}: {depth_counts[d]}", file=sys.stderr)

    if dry_run:
        print("[DRY-RUN] Would write to:", OUTPUT_PATH, file=sys.stderr)
        return

    # 4. 生成 AS2
    source = generate_as2(entries, stats_comment)

    # 5. 写入 UTF-8 BOM
    with open(OUTPUT_PATH, "wb") as f:
        f.write(b'\xef\xbb\xbf')
        f.write(source.encode("utf-8"))

    print(f"[OK] Written: {OUTPUT_PATH} ({len(entries)} entries)", file=sys.stderr)

    # 6. 验证: 解码所有键确保往返一致
    errors = 0
    for nk, (rx, ry, depth) in entries.items():
        moves = decode_key(nk, depth)
        roundtrip = encode_key(moves)
        if roundtrip != nk:
            print(f"[ERROR] Key roundtrip mismatch: {nk} != {roundtrip}", file=sys.stderr)
            errors += 1
    if errors:
        print(f"[ERROR] {errors} roundtrip errors!", file=sys.stderr)
        sys.exit(1)
    print(f"[OK] All {len(entries)} keys roundtrip verified", file=sys.stderr)


if __name__ == "__main__":
    main()
