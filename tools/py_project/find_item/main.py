import os
import xml.etree.ElementTree as ET

def find_items_in_xml(directory, search_string):
    results = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.xml'):
                path = os.path.join(root, file)
                try:
                    tree = ET.parse(path)
                    root_element = tree.getroot()
                    for item in root_element.findall('.//item'):
                        item_string = ET.tostring(item, encoding='unicode')
                        if search_string in item_string:
                            results.append({
                                'file_path': path,
                                'item': item_string
                            })
                            # 一旦找到匹配，跳出当前item的搜索
                            break
                except ET.ParseError:
                    print(f"Parse error in file {path}")
    return results

# 使用方法示例
directory = 'C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\data\items'  # 替换为你的文件夹路径
search_string = '破旧的军刀'  # 替换为你想搜索的字符串
matched_items = find_items_in_xml(directory, search_string)

for match in matched_items:
    print(f"Found in {match['file_path']}:")
    print(match['item'])
