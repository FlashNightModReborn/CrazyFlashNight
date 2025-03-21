#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
该程序实现：
1. 读取当前目录下所有输入 XML 文件（假设均为 UTF-8 编码、包含 XML 声明），
   每个文件包含多个 <item> 节点，每个节点至少含 <id>、<type>、<use>。
2. 遍历所有文件，提取全局 <id> 池（整数）并排序，分析空闲连续区间（至少 BLOCK_SIZE 长）。
3. 根据 <type> 与 <use> 对 <item> 进行分类，若缺少则归入“未分类_缺失属性.xml”。
4. 对每个分类文件：
   - 优先从全局空闲区间中选取一个连续区间（≥ BLOCK_SIZE）作为新 ID 分配区间，
     否则从全局最大 ID 后顺延分配一段连续 BLOCK_SIZE 的新 ID。
   - 将分配的新 ID 按顺序赋予该分类下的 <item>（输出时要求按新 ID 升序排列）。
   - 在生成的 XML 文件顶部添加注释，列出“已用ID”（该文件所有 <item> 的新 ID）及“预留ID区间”
     （即当前文件最大新 ID 后连续 BLOCK_SIZE 个新 ID）。
5. 生成 id_allocation_report.txt，包含全局原始最大 ID、分类文件数量、每个分类文件的新 ID 分配区间映射表，
   以及未分类 <item> 的数量统计。
   
程序中 BLOCK_SIZE 默认设置为 128，可根据需要调整为 512。
"""

import os
import glob
import re
from xml.dom import minidom

# 默认预分配块大小，若需要可将其修改为 512
BLOCK_SIZE = 128

def get_text_from_element(element):
    """获取元素内所有文本（包括 CDATA）"""
    text = ""
    for node in element.childNodes:
        if node.nodeType in (node.TEXT_NODE, node.CDATA_SECTION_NODE):
            text += node.data
    return text.strip()

def find_item_elements(doc):
    """返回 XML 文档中所有 <item> 节点"""
    return doc.getElementsByTagName("item")

def classify_items(items):
    """
    根据 <type> 与 <use> 对 items 分类，
    返回字典：键为 (type, use)，值为对应 <item> 列表，
    同时统计缺少 type 或 use 的未分类项数量。
    """
    classification = {}
    unclassified_count = 0
    for item in items:
        type_elems = item.getElementsByTagName("type")
        use_elems = item.getElementsByTagName("use")
        type_text = get_text_from_element(type_elems[0]) if type_elems else ""
        use_text = get_text_from_element(use_elems[0]) if use_elems else ""
        if not type_text or not use_text:
            key = ("未分类", "缺失属性")
            unclassified_count += 1
        else:
            key = (type_text, use_text)
        classification.setdefault(key, []).append(item)
    return classification, unclassified_count

def allocate_id_block(free_intervals, global_max_allocated):
    """
    尝试从 free_intervals 中分配一段连续 BLOCK_SIZE 的新 ID 区间。
    如果找到满足条件的空闲区间，则取该区间的起始部分；
    否则从 global_max_allocated 后顺延分配一段连续 BLOCK_SIZE 的新 ID 区间。
    返回分配的区间 (start, end) 以及更新后的 global_max_allocated。
    """
    for i, (start, end) in enumerate(free_intervals):
        if end - start + 1 >= BLOCK_SIZE:
            allocated_block = (start, start + BLOCK_SIZE - 1)
            # 更新该空闲区间：移除已分配部分
            new_start = start + BLOCK_SIZE
            if new_start <= end:
                free_intervals[i] = (new_start, end)
            else:
                free_intervals.pop(i)
            return allocated_block, global_max_allocated
    # 若无合适空闲区间，从 global_max_allocated 后顺延分配
    new_start = global_max_allocated + 1
    allocated_block = (new_start, new_start + BLOCK_SIZE - 1)
    global_max_allocated = allocated_block[1]
    return allocated_block, global_max_allocated

def generate_xml_file(file_name, items, used_ids, reserved_interval, encoding="utf-8"):
    """
    根据传入的 items（DOM 节点列表）生成 XML 文件。
    文件包括 XML 声明、顶部注释（列出已用ID及预留区间）以及根节点 <root> 包含所有 <item>。
    """
    # 创建新的 DOM 文档
    impl = minidom.getDOMImplementation()
    new_doc = impl.createDocument(None, "root", None)
    root = new_doc.documentElement

    # 生成注释内容
    used_ids_sorted = sorted(used_ids)
    used_ids_str = ", ".join(str(x) for x in used_ids_sorted)
    reserved_str = f"{reserved_interval[0]}-{reserved_interval[1]}"
    comment_text = f"\n已用ID：[{used_ids_str}]\n预留ID区间：{reserved_str}\n"
    comment_node = new_doc.createComment(comment_text)
    new_doc.insertBefore(comment_node, root)

    # 按新 ID 升序排列后导入 <item> 节点
    for item in items:
        imported_item = new_doc.importNode(item, True)
        root.appendChild(imported_item)
    
    # 输出为格式化 XML 字符串（包含 XML 声明），注意写入二进制并指定编码
    xml_str = new_doc.toprettyxml(encoding=encoding)
    with open(file_name, "wb") as f:
        f.write(xml_str)

def main():
    # 若需要可将 BLOCK_SIZE 修改为 512，此处默认使用 BLOCK_SIZE 变量（128 或 512）
    BLOCK_SIZE_input = BLOCK_SIZE

    # 获取当前目录下所有 *.xml 文件（排除生成的报告文件）
    xml_files = glob.glob("*.xml")
    xml_files = [f for f in xml_files if f not in ["id_allocation_report.txt"]]

    all_items = []      # 存储所有 <item> 节点
    global_ids = []     # 存储所有原始 id（整数）
    
    # 逐个解析输入 XML 文件
    for file in xml_files:
        try:
            doc = minidom.parse(file)
            items = find_item_elements(doc)
            all_items.extend(items)
            # 提取每个 <item> 的 <id>（假设存在且为整数）
            for item in items:
                id_elems = item.getElementsByTagName("id")
                if id_elems:
                    id_text = get_text_from_element(id_elems[0])
                    try:
                        orig_id = int(id_text)
                        global_ids.append(orig_id)
                    except Exception as e:
                        print(f"转换 ID 时出错：{id_text}，错误：{e}")
        except Exception as e:
            print(f"解析文件 {file} 出错：{e}")

    if not global_ids:
        print("没有在输入 XML 中找到任何 ID。")
        return

    # 排序并计算全局原始最大 ID
    global_ids = sorted(set(global_ids))
    original_global_max = max(global_ids)

    # 根据全局 ID 分析空闲连续区间（只考虑相邻节点之间的空档）
    free_intervals = []
    for i in range(len(global_ids) - 1):
        current_id = global_ids[i]
        next_id = global_ids[i + 1]
        if next_id - current_id > 1:
            gap_start = current_id + 1
            gap_end = next_id - 1
            if gap_end - gap_start + 1 >= BLOCK_SIZE_input:
                free_intervals.append((gap_start, gap_end))
    free_intervals.sort(key=lambda x: x[0])
    
    # 用于后续顺延分配的全局新 ID起始值
    global_max_allocated = original_global_max

    # 根据 <type> 和 <use> 对所有 <item> 进行分类
    classification, unclassified_count = classify_items(all_items)

    # 用于报告：记录每个分类文件分配的区间及分配的具体新 ID
    allocation_report = {}

    # 遍历每个分类，分配新 ID 并生成对应 XML 文件
    for key, items in classification.items():
        type_str, use_str = key
        # 生成文件名：若缺少属性则命名为 "未分类_缺失属性.xml"，否则用 type_use.xml，并将特殊字符替换为下划线
        if type_str == "未分类" and use_str == "缺失属性":
            file_name = "未分类_缺失属性.xml"
        else:
            safe_type = re.sub(r"[^\w\u4e00-\u9fff]+", "_", type_str)
            safe_use = re.sub(r"[^\w\u4e00-\u9fff]+", "_", use_str)
            file_name = f"{safe_type}_{safe_use}.xml"
        
        # 为该分类分配一段连续 BLOCK_SIZE 的新 ID 区间
        allocated_block, global_max_allocated = allocate_id_block(free_intervals, global_max_allocated)
        block_start, block_end = allocated_block

        # 对该分类中的 <item> 按原始 ID 升序排序（保证赋予的新 ID也是升序的）
        def get_orig_id(item):
            id_elems = item.getElementsByTagName("id")
            try:
                return int(get_text_from_element(id_elems[0])) if id_elems else 0
            except:
                return 0
        items_sorted = sorted(items, key=get_orig_id)
        
        used_ids = []
        # 为分类内每个 <item> 分配新 ID（从 allocated_block 的起始处连续赋值）
        for idx, item in enumerate(items_sorted):
            new_id = block_start + idx
            used_ids.append(new_id)
            # 更新 <id> 节点文本
            id_elems = item.getElementsByTagName("id")
            if id_elems:
                # 清空旧内容
                while id_elems[0].firstChild:
                    id_elems[0].removeChild(id_elems[0].firstChild)
                new_text = item.ownerDocument.createTextNode(str(new_id))
                id_elems[0].appendChild(new_text)
        
        # 计算预留 ID 区间：从当前分类最大新 ID 后连续 BLOCK_SIZE 个 ID
        if used_ids:
            max_used = max(used_ids)
        else:
            max_used = block_start - 1
        reserved_interval = (max_used + 1, max_used + BLOCK_SIZE_input)
        
        # 生成 XML 文件，文件中包含 XML 声明、顶部注释及根节点 <root> 包含所有 <item>
        generate_xml_file(file_name, items_sorted, used_ids, reserved_interval)
        
        # 将本分类文件的分配信息记录到报告中
        allocation_report[file_name] = {
            "allocated_block": f"{block_start}-{block_end}",
            "used_ids": used_ids,
            "reserved_interval": f"{reserved_interval[0]}-{reserved_interval[1]}"
        }
    
    # 生成最终报告文件 id_allocation_report.txt
    report_lines = []
    report_lines.append(f"全局原始最大 ID: {original_global_max}")
    report_lines.append(f"分类文件数量: {len(classification)}")
    report_lines.append("每个分类文件对应的 ID 分配区间映射表:")
    for file_name, info in allocation_report.items():
        report_lines.append(f"{file_name}: 分配区间 {info['allocated_block']}, 已用ID {info['used_ids']}, 预留区间 {info['reserved_interval']}")
    report_lines.append(f"未分类 <item> 的数量统计: {unclassified_count}")
    
    with open("id_allocation_report.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines))
    
    print("处理完成，生成的文件包括：")
    for file_name in allocation_report.keys():
        print("  ", file_name)
    print("  id_allocation_report.txt")

if __name__ == "__main__":
    main()
