# -*- coding: utf-8 -*-
"""
Process information_dictionary.xml:
1. Extract Text content from each Information node
2. Save as separate txt files in data/intelligence/
3. Replace <Text> with <TextRef> pointing to the txt file
4. Save modified XML as information_dictionary_new.xml

This version uses regex-based approach to preserve original XML formatting.
"""

import os
import re
import xml.etree.ElementTree as ET

def sanitize_filename(name):
    """
    Remove or replace characters that are not allowed in filenames.
    """
    # Characters not allowed in Windows filenames: \ / : * ? " < > |
    invalid_chars = r'[\\/:*?"<>|]'
    sanitized = re.sub(invalid_chars, '_', name)
    # Also replace spaces and other potentially problematic characters
    sanitized = sanitized.replace(' ', '_')
    # Remove leading/trailing dots and spaces
    sanitized = sanitized.strip('. ')
    return sanitized

def main():
    # Paths
    base_dir = r'c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources'
    xml_path = os.path.join(base_dir, 'data', 'dictionaries', 'information_dictionary.xml')
    output_xml_path = os.path.join(base_dir, 'data', 'dictionaries', 'information_dictionary_new.xml')
    intelligence_dir = os.path.join(base_dir, 'data', 'intelligence')

    # Create intelligence directory if it doesn't exist
    os.makedirs(intelligence_dir, exist_ok=True)
    print(f"Created/verified directory: {intelligence_dir}")

    # Read original XML content
    with open(xml_path, 'r', encoding='utf-8') as f:
        xml_content = f.read()

    # Parse XML to extract structure information
    tree = ET.parse(xml_path)
    root = tree.getroot()

    files_created = 0
    replacements = []

    # Iterate through each Item
    for item in root.findall('Item'):
        # Get the Name of the item
        name_elem = item.find('Name')
        if name_elem is None or name_elem.text is None:
            print(f"Warning: Item without Name found, skipping")
            continue

        item_name = name_elem.text.strip()
        sanitized_item_name = sanitize_filename(item_name)

        # Iterate through each Information in this Item
        for info in item.findall('Information'):
            # Get the Value
            value_elem = info.find('Value')
            if value_elem is None or value_elem.text is None:
                print(f"Warning: Information without Value in '{item_name}', skipping")
                continue

            value = value_elem.text.strip()

            # Get the Text element
            text_elem = info.find('Text')
            if text_elem is None:
                # No Text element, skip
                continue

            text_content = text_elem.text if text_elem.text else ''

            # Create the filename
            txt_filename = f"{sanitized_item_name}_{value}.txt"
            txt_relative_path = f"data/intelligence/{txt_filename}"
            txt_full_path = os.path.join(intelligence_dir, txt_filename)

            # Write the text content to file (UTF-8 without BOM)
            with open(txt_full_path, 'w', encoding='utf-8') as f:
                f.write(text_content)

            files_created += 1
            print(f"Created: {txt_filename}")

            # Store replacement info
            replacements.append({
                'text_content': text_content,
                'txt_relative_path': txt_relative_path
            })

    # Now do regex-based replacement on the original XML content
    # Match <Text>...</Text> and replace with <TextRef>path</TextRef>
    modified_content = xml_content

    for repl in replacements:
        text_content = repl['text_content']
        txt_path = repl['txt_relative_path']

        # Escape special regex characters in text content
        escaped_text = re.escape(text_content)

        # Create pattern to match <Text>content</Text>
        pattern = r'<Text>' + escaped_text + r'</Text>'
        replacement = f'<TextRef>{txt_path}</TextRef>'

        # Replace only the first occurrence (each replacement is unique)
        modified_content = re.sub(pattern, replacement, modified_content, count=1)

    # Write the modified XML
    with open(output_xml_path, 'w', encoding='utf-8') as f:
        f.write(modified_content)

    print(f"\n=== Summary ===")
    print(f"Total text files created: {files_created}")
    print(f"Output XML saved to: {output_xml_path}")
    print(f"Text files saved to: {intelligence_dir}")

if __name__ == '__main__':
    main()
