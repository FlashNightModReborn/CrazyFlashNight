"""
gomoku.json -> GobangBook.as addEntry 调用
只保留中心区域（Chebyshev 半径 ≤ 4）内的走法序列
"""
import json, sys

def parse_coord(s):
    col = ord(s[0]) - ord('a')
    row = 15 - int(s[1:])
    return (row, col)

def near_center(row, col, radius=4):
    return abs(row - 7) <= radius and abs(col - 7) <= radius

def get_max_leaf(tree):
    if isinstance(tree, (int, float)):
        return tree
    if not isinstance(tree, dict):
        return -999999
    return max((get_max_leaf(v) for v in tree.values()), default=-999999)

def extract_entries(tree, path=None, entries=None, max_depth=7):
    if path is None: path = []
    if entries is None: entries = {}
    if not isinstance(tree, dict) or len(path) >= max_depth:
        return entries

    # 找最佳走法
    best_move = None
    best_score = -999999
    for move_str, subtree in tree.items():
        row, col = parse_coord(move_str)
        if not near_center(row, col):
            continue  # 跳过偏离中心的走法
        score = subtree if isinstance(subtree, (int, float)) else get_max_leaf(subtree)
        if score > best_score:
            best_score = score
            best_move = (row, col, move_str)

    if best_move is None:
        return entries

    key = ";".join(f"{r},{c}" for r, c in path)
    entries[key] = (best_move[0], best_move[1], best_score)

    # 递归展开对手应手（只保留中心区域内的）
    subtree = tree[best_move[2]]
    if isinstance(subtree, dict):
        new_path = path + [(best_move[0], best_move[1])]
        for opp_str, opp_sub in subtree.items():
            opp_row, opp_col = parse_coord(opp_str)
            if not near_center(opp_row, opp_col):
                continue
            if isinstance(opp_sub, dict):
                extract_entries(opp_sub, new_path + [(opp_row, opp_col)], entries, max_depth)
    return entries

def main():
    with open("scripts/gomoku_book_raw.json") as f:
        data = json.load(f)

    entries = extract_entries(data, max_depth=5)
    sorted_entries = sorted(entries.items(), key=lambda x: (len(x[0]), x[0]))

    # 输出 AS2
    for key, (row, col, score) in sorted_entries:
        print(f'        a("{key}", {row}, {col});')

    # 统计
    depth_counts = {}
    for key, _ in sorted_entries:
        d = key.count(";") + 1 if key else 0
        depth_counts[d] = depth_counts.get(d, 0) + 1
    print(f"\n// Total: {len(sorted_entries)} entries", file=sys.stderr)
    for d in sorted(depth_counts):
        print(f"//   depth {d}: {depth_counts[d]}", file=sys.stderr)

if __name__ == "__main__":
    main()
