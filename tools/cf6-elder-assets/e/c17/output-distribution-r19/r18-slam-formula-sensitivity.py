"""Read-only action redistribution through the unchanged canonical formula."""
from pathlib import Path
import hashlib, importlib.util, json, sys

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
sys.path.insert(0, str(R / 'tools/cf6-elder-assets'))
spec = importlib.util.spec_from_file_location('elder_balance', R / 'tools/cf6-elder-assets/balance.py')
balance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(balance)
paths = ['tools/cf6-elder-assets/build.py', 'tools/cf6-elder-assets/balance.py',
         'tools/cf6-elder-assets/balance-inputs.json', 'tools/cf6-elder-assets/ElderAI.as',
         'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts',
         'data/enemy_properties/CF6重制敌人.xml']
before = {p: hashlib.sha256((R / p).read_bytes()).hexdigest() for p in paths}
_, _, old = balance.expected('robot')
variants = []
for slam_power in [10, 8, 6, 4]:
    balance.build.FORMS['robot']['actions']['slam']['power'] = slam_power
    _, _, candidate = balance.expected('robot')
    powers = {}
    for attack_key in ['空手攻击力_min', '空手攻击力_max']:
        attack_ratio = candidate['integerPanel'][attack_key] / old['integerPanel'][attack_key]
        powers[attack_key] = {'baseAttackRatio': attack_ratio,
                             'slamRawPowerRatio': attack_ratio * slam_power / 12,
                             'beamAndHeavyRawPowerRatio': attack_ratio}
    variants.append({'slamPower': slam_power, 'flags': candidate['flags'],
                     'panel': candidate['integerPanel'], 'directRatios': powers})
assert before == {p: hashlib.sha256((R / p).read_bytes()).hexdigest() for p in paths}
result = {'status': 'read_only_formula_sensitivity; unexecuted_variants; no production files changed',
          'oldFlags': old['flags'], 'oldPanel': old['integerPanel'], 'variants': variants,
          'sourceBindings': [{'path': p, 'sha256': digest} for p, digest in before.items()],
          'boundary': 'Changing one action multiplier also regenerates base attack and attack-derived shield strength. These exact formula calculations do not predict arena outcomes or establish acceptance.'}
with (O / 'r18-slam-formula-sensitivity-unexecuted.json').open('x', encoding='utf8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(json.dumps({'status': result['status'], 'variants': variants}, ensure_ascii=False))
