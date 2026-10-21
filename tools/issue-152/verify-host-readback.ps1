param()
$ErrorActionPreference = 'Stop'
chcp.com 65001 > $null
$resourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$bundle = Join-Path $resourceRoot 'tmp/issue-152-acceptance'
$manifest = Get-Content -LiteralPath (Join-Path $bundle 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = Join-Path $resourceRoot ($manifest.candidate + '/runtime')
Add-Type -Path (Join-Path $runtime 'Newtonsoft.Json.dll')
Add-Type -Path (Join-Path $runtime 'CRAZYFLASHER7MercenaryEmpire.Core.dll')
$archive = [CF7Launcher.Tasks.ArchiveTask]::new($resourceRoot)
$resolver = [CF7Launcher.Save.SolResolver]::new(
    [CF7Launcher.Save.SolFileLocator]::new(), $archive,
    [CF7Launcher.Save.NativeSolParser]::new(), $null)
$listMethod = $archive.GetType().GetMethod('HandleList', [Reflection.BindingFlags]'Instance,NonPublic')
$list = $listMethod.Invoke($archive, $null) | ConvertFrom-Json
$definition = [CF7Launcher.Data.MapDefinition]::Load($resourceRoot)
$policy = [CF7Launcher.Data.NpcShopAccessPolicy]::Load($resourceRoot, $definition)
$entries = @()
foreach ($entry in $manifest.slots) {
    $listed = @($list.slots | Where-Object { $_.slot -ceq $entry.slot })
    if ($listed.Count -ne 1 -or $listed[0].corrupt -or $listed[0].displayName -cne $entry.name) {
        throw ('Launcher 档案发现失败：' + $entry.slot)
    }
    $resolved = $resolver.Resolve($entry.slot, (Join-Path $resourceRoot 'CRAZYFLASHER7MercenaryEmpire.swf'))
    if ($resolved.WireDecision -cne 'snapshot' -or $resolved.Source -cne 'json_shadow') {
        throw ('加载器未选择新克隆 JSON：' + $entry.slot + ' ' + $resolved.WireDecision)
    }
    if (![CF7Launcher.Save.SaveMigrator]::ValidateResolvedSnapshot($resolved.Snapshot)) {
        throw ('生产存档验证器拒绝：' + $entry.slot)
    }
    $facts = [Newtonsoft.Json.Linq.JObject]::Parse('{"chains":{},"infrastructure":{},"tasks":{},"scene":{},"navigation":{"reason":""}}')
    $facts['chains'] = $resolved.Snapshot['tasks']['task_chains_progress'].DeepClone()
    $facts['infrastructure'] = $resolved.Snapshot['infrastructure'].DeepClone()
    $projected = [CF7Launcher.Data.MapDomainService]::Project($definition, $facts, [Newtonsoft.Json.Linq.JObject]::new(), $null)
    $access = $policy.Project($definition, $projected)
    $student = [bool]::Parse($access['学生妹'].ToString())
    $diplomat = [bool]::Parse($access['黑铁会外交部长'].ToString())
    $fixed = [bool]::Parse($access['Andy Law'].ToString())
    $book = [bool]::Parse($access['书中-迷之盔甲君'].ToString())
    if ($student -ne $entry.studentExpected -or $diplomat -ne $entry.diplomatExpected -or !$fixed -or $book) {
        throw ('生产地图/商人资格与预期不符：' + $entry.slot)
    }
    $entries += [ordered]@{slot=$entry.slot; displayName=$listed[0].displayName; decision=$resolved.WireDecision;
        source=$resolved.Source; productionSchemaValid=$true; studentEligible=$student; diplomatEligible=$diplomat;
        remoteStudent=($student -and $entry.motorcycle -eq 1); remoteDiplomat=($diplomat -and $entry.motorcycle -eq 1);
        fixedContactEligible=$fixed; ordinaryRoleBookEligible=$book}
}
$preserved = Get-Content -LiteralPath (Join-Path $bundle 'preexisting-saves.sha256.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($record in $preserved) {
    if ((Get-FileHash -LiteralPath $record.path -Algorithm SHA256).Hash -cne $record.sha256) {
        throw ('既有存档字节变化：' + $record.path)
    }
}
$report = [ordered]@{schema='issue152-production-save-readback.v1';createdAt=[DateTime]::UtcNow.ToString('o');
    runtime=$runtime;coreDllSha256=(Get-FileHash -LiteralPath (Join-Path $runtime 'CRAZYFLASHER7MercenaryEmpire.Core.dll')).Hash;
    preexistingSaveFilesUnchanged=$preserved.Count;slots=$entries;
    evidence='production catalog, save resolver, schema validator and map policy; offline only';
    gameplayE2e=$false;humanAccepted=$false;promoted=$false}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $bundle 'host-readback.json') -Encoding utf8NoBOM
$report | ConvertTo-Json -Depth 8
