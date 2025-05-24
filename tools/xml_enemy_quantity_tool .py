import xml.etree.ElementTree as ET
import os


def rename_tag_in_file(xml_file, old_tag_name, new_tag_name):
    # 读取XML文件
    tree = ET.parse(xml_file)
    root = tree.getroot()

    # 遍历所有old_tag_name标签并更改其名称
    for elem in root.iter(old_tag_name):
        elem.tag = new_tag_name

    # 保存更改，包括UTF-8编码声明
    tree.write(xml_file, encoding='utf-8', xml_declaration=True)


def decrease_enemy_quantity_in_file(xml_file):
    # 读取XML文件
    tree = ET.parse(xml_file)
    root = tree.getroot()

    # 遍历每个Enemy标签
    for enemy in root.findall(".//Enemy"):
        quantity = enemy.find('Quantity')
        if quantity is not None and quantity.text.isdigit():
            quantity_value = int(quantity.text)
            # 当Quantity大于1时，减1
            if quantity_value > 1:
                quantity.text = str(quantity_value - 1)

    # 保存更改
    tree.write(xml_file, encoding='utf-8', xml_declaration=True)


def process_xml_files(directory):
    # 遍历目录下的所有文件和子目录
    for foldername, subfolders, filenames in os.walk(directory):
        for filename in filenames:
            # 检查文件是否为XML文件
            if filename.endswith('.xml'):
                # 获取文件的完整路径
                file_path = os.path.join(foldername, filename)
                # 修改该XML文件中的标签
                rename_tag_in_file(file_path, 'QuantityMin', 'AcquisitionProbability')
                # 减少Enemy标签的Quantity值
                decrease_enemy_quantity_in_file(file_path)
                print(f"Processed file: {file_path}")


# 使用示例
process_xml_files("C:/Users/lsy20/Downloads/data/stages")
