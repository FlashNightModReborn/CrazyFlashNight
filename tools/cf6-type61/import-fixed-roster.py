"""Import the reviewed fixed158 design without importing executable proposal code."""
from pathlib import Path
import argparse
import copy
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROSTER = 'outputs/cf6-158-v2/D4_roster_158_v2.json'
CONTRACTS = 'outputs/cf6-158-v2/D4_major_tactic_contracts_v2.json'
ADMISSION = 'outputs/cf6-158-v2/D4_enemy_admission_manifest_v2.json'
TEXT = 'outputs/cf6-158-v2/D2_xml_text_patchset.json'
PAIR = 'audit_v2/seats/G1111_pair_contract.json'
AMMO = 'outputs/cf6-158-v2/D4_ammo_access_contract_v2.json'


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def project(package):
    inputs = {name: json.loads((package / name).read_text('utf-8-sig'))
              for name in (ROSTER, CONTRACTS, ADMISSION, TEXT, PAIR, AMMO)}
    roster = inputs[ROSTER]
    if len(roster['roster']) != 158 or len(inputs[CONTRACTS]['contracts']) != 22:
        raise ValueError('Expected the complete reviewed 158-person / 22-instructor design')
    review = dict(head=roster['headSha'], rosterCanonicalSha256=roster['rosterCanonicalSha256'],
                  inputs=[dict(path=name, sha256=hashlib.sha256((package / name).read_bytes()).hexdigest())
                          for name in inputs])
    keep = ('unitIdentity displayName role roleClass mapId sourceSeat sourceJsonPointer sourceQuantity '
            'sourceInstanceOrdinal unitType unitId level startingPhase startingOrientation proposedSpawn '
            'relocation difficultyScale primary secondary1 secondary2 subweapon throwable smokeAbility '
            'aiBlueprint counterplay lootProfile lootRules nominalFireBudget phaseGate effectBudget').split()
    rows = []
    for original in roster['roster']:
        row = {key: copy.deepcopy(original[key]) for key in keep if key in original}
        for slot in ('primary', 'secondary1', 'secondary2'):
            if row[slot] is not None:
                row[slot] = {key: row[slot][key] for key in ('name', 'enhancement', 'tier', 'mods', 'serialized', 'instanceValueOverrides')
                             if key in row[slot]}
        row['proposedSpawn'] = {key: value for key, value in row['proposedSpawn'].items()
                                if key not in ('coordinateEvidence', 'positionValidation')}
        row['aiBlueprint'] = {key: row['aiBlueprint'][key] for key in ('role', 'strategy', 'existingScalarOverrides', 'proposedExtensions')}
        rows.append(row)
    source = dict(schema='cf6-fixed-roster.source.v1', review=review,
                  scope=dict(bookId='cf6-sting', routeId='type61'), roster=rows,
                  admission={key: inputs[ADMISSION][key] for key in ('scope', 'allowedTierNames', 'weapons', 'mods')})
    contracts = copy.deepcopy(inputs[CONTRACTS])
    contracts['schema'] = 'cf6-soldier-action-contracts.source.v1'
    contracts['review'] = review
    for row in contracts['contracts']:
        row.pop('equipmentInvariant', None)
        row.pop('status', None)
    return {
        HERE / 'fixed-roster.source.json': encoded(source),
        HERE / 'soldier-action-contracts.source.json': encoded(contracts),
        HERE / 'soldier-g1111-pair.source.json': encoded(inputs[PAIR]),
        HERE / 'soldier-description-proposals.source.json': encoded(inputs[TEXT]),
        HERE / 'soldier-ammo-contract.source.json': encoded(inputs[AMMO]),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for path, content in project(args.package).items():
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                raise ValueError('Imported design drift: ' + path.name)
        else:
            path.write_bytes(content)
    print(json.dumps(dict(imported=158, contracts=22, sourceOnly=True, check=args.check)))
