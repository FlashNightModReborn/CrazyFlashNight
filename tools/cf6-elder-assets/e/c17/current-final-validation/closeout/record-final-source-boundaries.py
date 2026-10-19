from pathlib import Path
import datetime, hashlib, json

O = Path.cwd() / 'tmp/cf6-combat-calibration-20261017'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
individual = load(O / 'preliminary-staged-source-with-host-verification.json')
batch = load(O / 'preliminary-staged-source-with-host-batch-verification.json')
keys = ['path', 'expectedSha256', 'workingSha256', 'checkoutSha256', 'matches']
assert [{k: r[k] for k in keys} for r in individual['files']] == [{k: r[k] for k in keys} for r in batch['files']]
final = load(O / 'staged-current-input-verification-final-v2.json')
assert final['ok'] and final['strictCheckoutFiles'] == 1578
differences = final['hostCheckoutLineEndingDifferences']
assert len(differences) == 127
assert all(row['sourceRole'] == 'additional_frozen_host_source' and not row['matches'] and row['accepted']
           and row['canonicalLfSha256'] == row['gitBlobCanonicalLfSha256'] == row['checkoutCanonicalLfSha256'] for row in differences)
prior = load(O / 'prior-sealed-evidence-final.json')
assert prior['integrityRecords'] == 25 and prior['indexedPackages'] == 24 and prior['summaryOnlyRecords'] == 1
report = {'ok': True, 'recordedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'strictGameplayAs2AndOriginalInputs': 1578, 'allFrozenSourceFiles': len(final['files']),
          'hostExistingLineEndingDifferences': 127,
          'hostRawBlobAlsoMatchesTestedBytes': sum(row['gitBlobMatchesTestedBytes'] for row in differences),
          'hostMixedLineEndingsRequireFrozenOriginalForExactReplay': sum(not row['gitBlobMatchesTestedBytes'] for row in differences),
          'productionFilesChangedForHostFormatPolicy': 0,
          'batchAndIndividualActualGitFiltersCompared': len(individual['files']),
          'batchAndIndividualResultsIdentical': True,
          'sourceChecks': {name: sha(O / name) for name in ['preliminary-staged-source-with-host-verification.json',
              'preliminary-staged-source-with-host-batch-verification.json',
              'staged-current-input-verification-final.json', 'staged-current-input-verification-final-v2.json']},
          'verifierCorrections': [
              'The original ignored TestLoader scratch file is a restoration binding, not committed test source.',
              'Git filtered-batch headers report unfiltered blob size; NUL framing preserves actual converted bytes. Binary and custom-encoded files use individual calls.',
              'One prior integrity-named record is a summary receipt with zero file entries, not a package file index; its original hash is still verified.'
          ],
          'boundary': 'The original strict Host checkout mismatch reports remain preserved. Exact Host-source replay uses the frozen archive. Existing checkout EOL differences are disclosed rather than represented as raw-byte equality, and no unrelated C# format rules or files were changed.'}
with (O / 'final-source-boundary-assessment.json').open('x', encoding='utf8') as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print(json.dumps({'ok': True, 'strictInputs': 1578, 'frozenSourceFiles': len(final['files']),
                  'explicitHostEolDifferences': 127, 'unchangedPriorIndexedPackages': 24}))
