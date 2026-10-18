from pathlib import Path
import json
TMP=Path(__file__).resolve().parent
config={
 'tests':[
  {'folder':'native-tests-pass6/elder-asset','pattern':r'Cf6ElderAssetTest: 792 passed, 0 failed; 42 actual timeline cases; 13 phase cases','additionalPatterns':[r'Cf6ElderCombatEffectsTest: 31 passed, 0 failed']},
  {'folder':'native-tests-pass6/headbot-asset','pattern':r'Cf6HeadbotAssetTest: 390 passed, 0 failed; 24 actual timeline cases'},
  {'folder':'native-tests-pass6/player-aim','pattern':r'Cf6PlayerAimTest: 334 passed, 0 failed; 32'},
  {'folder':'native-tests-pass5/bladebot-asset','pattern':r'Cf6BladebotAssetTest: 409 passed, 0 failed'},
  {'folder':'render-pass3/headbot','pattern':r'Cf6HeadbotRenderTest: \d+ passed, 0 failed; 2 draw points'},
  {'folder':'render-pass3/elder','pattern':r'Cf6ElderRenderTest: \d+ passed, 0 failed; 25 draw points'},
  {'folder':'render-pass4/bladebot','pattern':r'Cf6BladebotBeamRenderTest: \d+ passed, 0 failed; 32 draw points'}
 ],
 'builds':[{'folder':p} for p in ['build-pass7/headbot','build-pass7/elder','build-pass5/bladebot','build-pass6/asLoader']],
 'imageFolders':[{'source':f'final-images/{p}/images','name':p} for p in ['headbot','elder','bladebot']]+[{'source':'review-preview2','name':'review-sheets'},{'source':'handoff-preview','name':'preview'}],
 'extraReceipts':['final-headbot-static.log','final-elder-static.log','final-bladebot-static.log','render-only-harness-changes.json','old-packages-verified.json','native-graphics-delta.json','asLoader-published-markers.json','beam-pixel-probe.json','capture-change-exclusion-check.json','image-review.json','final-cleanup.json','final-testplayer-stop.log','diff-check-before-package.log'],
 'captureOnlyChangesAfterBehavior':json.loads((TMP/'render-only-harness-changes.json').read_text('utf8'))['paths'],
 'captureOnlyTemplateClasses':{'scripts/test-runners/cf6-elder-render/TestLoader-capture.as.template':'Cf6ElderRenderTest'},
 'recoveryFolders':['tmp/flash-testplayer-control/26208947b22e4c1aa411ea6e0ceee0f8','tmp/flash-testplayer-control/99fb31e6ff234a28b64f627bbd1e2fe2','tmp/flash-testplayer-control/751c981098a24805a270eec7e723bbe9','tmp/flash-testplayer-control/cff1a768b17640b4b8f72880bba6e078','tmp/flash-testplayer-control/f0af00d5a3b3487d9d5acbb0f88f486d'],
 'renderCoverage':{'headbot':{'firstSweepDrawPoints':204,'firstSweepPassed':611,'firstSweepFailed':2,'failureScope':'Full-capture bounds on beam frames 29 and 30 only','finalFramingProbeDrawPoints':2,'fullSweepAllPassClaimed':False},'elder':{'selectedDrawPoints':25,'full807PointSweep':'cancelled, not passed'},'bladebot':{'drawPoints':32,'captureContext':'Neutral beam angle; player aim and matching visible/collision transforms verified by the separate player-source suite'}},
 'changes':[
  'Headbot beam adds 18 windup frames with growing charge glow; contacts at frames 21 and 29.',
  'Headbot uses six prefab parts and Elder robot uses fifteen parts through the existing fragment animator; grounded corpse stamping, pause, unload, scene replacement and stale callbacks checked.',
  'Human Elder fires piercing rounds toward the locked player body center; Bladebot turns its beam art and collision together. Existing depth thresholds remain unchanged.',
  'Elder melee actual hits grant a short-lived low-strength high-capacity shield. Kicks declare crumble; slam declares slay and horizontal knockback, then selects a beam combo.',
  'Primer beam grants a 25 percent decaying vulnerability for 180 effective frames without altering Titanium-171.',
  'Charged heavy beam has native charge glow, threefold visual thickness, a 96 pixel contact width and threefold wave damage. It is authorized only by a live vulnerability on the same locked target; expiry or replacement cancels it.',
  'Final behavior checks total 1956 assertions. Render evidence distinguishes the cancelled 807-point Elder sweep from the completed 25 selected native frames.'
 ]}
(TMP/'accepted-inputs.json').write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n','utf8')
print('Prepared accepted input plan; freezing waits for actual capture results and visual inspection')
