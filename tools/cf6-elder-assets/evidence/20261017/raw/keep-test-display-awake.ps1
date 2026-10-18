$ErrorActionPreference='Stop'
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class Cf6OvernightPower { [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags); }'
$until=[DateTime]::UtcNow.AddHours(3)
$stop=Join-Path $PSScriptRoot 'release-display-request.marker'
try {
  $previous=[Cf6OvernightPower]::SetThreadExecutionState([uint32]2147483651)
  if ($previous -eq 0) { throw 'Temporary display/system request failed' }
  Write-Output ('Temporary display request acquired '+[DateTime]::UtcNow.ToString('o'))
  while ([DateTime]::UtcNow -lt $until -and -not (Test-Path -LiteralPath $stop)) { Start-Sleep -Seconds 1 }
} finally {
  [void][Cf6OvernightPower]::SetThreadExecutionState([uint32]2147483648)
  Write-Output ('Temporary display request released '+[DateTime]::UtcNow.ToString('o'))
}