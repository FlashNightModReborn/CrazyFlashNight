import re
import sys

def categorize_enemy(name):
    """Categorize enemy based on name patterns"""
    if "终结者" in name or "T800" in name:
        return "T800/Terminator"
    elif "异形" in name:
        return "AVP_Alien"
    elif "铁血" in name:
        return "AVP_Predator"
    elif "boss" in name or "BOSS" in name or "将军" in name:
        return "Boss"
    elif "狂野玫瑰" in name:
        return "Wild_Rose_Faction"
    elif "黑铁会" in name:
        return "Black_Iron_Society"
    elif "盗贼" in name:
        return "Thief_Faction"
    elif "军阀" in name:
        return "Warlord_Faction"
    elif "日本" in name or "小日本" in name:
        return "Japanese_Faction"
    elif "僵尸" in name:
        return "Zombie"
    elif "摇滚公园" in name:
        return "Rock_Park"
    else:
        return "Other"

try:
    with open('D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\data\enemy_properties\原版敌人 2011-2012.xml', 'r', encoding='utf-8') as f:
        content = f.read()

    # Find all enemy sections with their magic resistance
    enemy_pattern = r'<敌人-([^>]+)>(.*?)</敌人-[^>]+>'
    enemies = re.findall(enemy_pattern, content, re.DOTALL)
    
    results = {}
    
    for name, section in enemies:
        category = categorize_enemy(name)
        
        if category not in results:
            results[category] = []
        
        # Check magic resistance
        magic_resistance_match = re.search(r'<魔法抗性>(.*?)</魔法抗性>', section, re.DOTALL)
        
        if not magic_resistance_match:
            status = "MISSING"
            resistances = []
        elif magic_resistance_match.group(1).strip() == 'null':
            status = "NULL"
            resistances = []
        else:
            # Extract individual resistances
            resistance_matches = re.findall(r'<([^>]+)>([^<]+)</[^>]+>', magic_resistance_match.group(1))
            resistances = [(r[0], r[1]) for r in resistance_matches]
            
            if len(resistances) == 0:
                status = "NULL"
            elif len(resistances) <= 2:
                status = "MINIMAL"
            else:
                status = "CONFIGURED"
        
        results[category].append({
            'name': name,
            'status': status,
            'resistances': resistances
        })
    
    # Print results organized by category
    for category in sorted(results.keys()):
        print(f"\n=== {category.replace('_', ' ').upper()} ===")
        for enemy in results[category]:
            if enemy['status'] in ['NULL', 'MISSING', 'MINIMAL']:
                print(f"  {enemy['name']}: {enemy['status']}", end="")
                if enemy['resistances']:
                    resistance_str = ', '.join([f"{r[0]}:{r[1]}" for r in enemy['resistances']])
                    print(f" - {resistance_str}")
                else:
                    print()
            
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
