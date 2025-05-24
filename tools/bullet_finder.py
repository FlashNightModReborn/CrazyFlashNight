import os
import xml.etree.ElementTree as ET


def scan_bullets_in_xml_files(directory):
    # List to hold all unique bullet types
    bullet_types = set()

    # Traverse the directory and find XML files
    for root_dir, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.xml'):
                full_file_path = os.path.join(root_dir, file)
                try:
                    # Parse the XML file
                    tree = ET.parse(full_file_path)
                    xml_root = tree.getroot()

                    # Find all <bullet> tags and collect the text
                    for bullet_tag in xml_root.findall(".//bullet"):
                        bullet_types.add(bullet_tag.text)
                except ET.ParseError as e:
                    print(f"Error parsing {full_file_path}: {e}")

    # Save the unique bullet types to an XML file
    save_bullets_to_xml(bullet_types, directory)
    return bullet_types


def save_bullets_to_xml(bullet_types, directory):
    root = ET.Element("bullets")
    for bullet in bullet_types:
        bullet_element = ET.SubElement(root, "bullet")
        bullet_element.text = bullet

    tree = ET.ElementTree(root)
    output_file_path = os.path.join(directory, "unique_bullets.xml")
    tree.write(output_file_path, encoding="utf-8", xml_declaration=True)

    print(f"Unique bullet types saved to {output_file_path}")


directory_path = r'D:\SteamLibrary\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\data\items'
bullet_types = scan_bullets_in_xml_files(directory_path)
