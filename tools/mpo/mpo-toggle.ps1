#Requires -Version 5.1
<#
.SYNOPSIS
    CF7 dev tool: toggle Windows MPO (Multiplane Overlay) for A/B perf testing.

.DESCRIPTION
    Multiplane Overlay (MPO) is a DWM / display-controller feature. On the CF7
    launcher's layered-window overlay stack (InputShield ULW + transparent
    WebView2 overlay + Flash HWND) MPO can churn -- repeatedly promoting and
    demoting overlay planes -- which stalls the SWF present pipeline and shows
    up as stutter / WebView2 "freeze".

    This tool toggles MPO so the regression can be A/B tested on a low-spec
    machine. It does so through the well-known registry value:

        HKLM\SOFTWARE\Microsoft\Windows\Dwm\OverlayTestMode = 5   (MPO disabled)

    SCOPE / SAFETY
      * The value is SYSTEM-WIDE, persistent, and undocumented ("test mode").
      * It affects every application on the machine, not just CF7.
      * A reboot is required for any change to take effect.
      * It is reversible: this tool snapshots the pre-change state once and
        restores it exactly on -Restore.

    THIS IS A DEVELOPMENT / DIAGNOSTIC TOOL ONLY.
    The shipping launcher must NOT write this value. The production fix for the
    MPO regression must be process-scoped (WebView2 / Chromium overlay flags,
    launcher swapchain config, or the Ruffle single-surface migration).
    See tools/mpo/README.md for the full rationale and test protocol.

.PARAMETER Status
    Show current MPO state, the tool snapshot, and whether a reboot is pending.
    This is the default action when no switch is given.

.PARAMETER Disable
    Disable MPO: snapshot the current state (once), then write OverlayTestMode=5.
    Requires elevation (UAC prompt). Requires a reboot to take effect.

.PARAMETER Restore
    Restore MPO to the snapshot captured before the first -Disable.
    Requires elevation (UAC prompt). Requires a reboot to take effect.

.PARAMETER Reboot
    After a successful -Disable / -Restore, reboot the machine (10s grace
    period; cancel with:  shutdown /a ).

.EXAMPLE
    .\mpo-toggle.ps1
    Show status.

.EXAMPLE
    .\mpo-toggle.ps1 -Disable -Reboot
    Disable MPO and reboot to apply.

.EXAMPLE
    .\mpo-toggle.ps1 -Restore
    Restore the original MPO setting (reboot separately).
#>
param(
    [switch]$Status,
    [switch]$Disable,
    [switch]$Restore,
    [switch]$Reboot,

    # --- internal: used by the elevated child process; do not pass manually ---
    [int]$RawWrite = -1,
    [switch]$RawDelete
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null

# --- constants -------------------------------------------------------------
$RegKey    = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm'
$RegName   = 'OverlayTestMode'
$MpoOffVal = 5                                            # OverlayTestMode=5 => MPO off
$StateDir  = Join-Path $env:LOCALAPPDATA 'cfn-mpo-toggle'
$StateFile = Join-Path $StateDir 'state.json'

# --- helpers ---------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-MpoValue {
    # Returns [int] current OverlayTestMode, or $null if the value is not set.
    try {
        $item = Get-ItemProperty -Path $RegKey -Name $RegName -ErrorAction Stop
        return [int]$item.$RegName
    } catch {
        return $null
    }
}

function Get-BootTime {
    (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
}

function Set-MpoRegistry {
    # Must run elevated. $Value -eq $null => delete; otherwise write DWORD.
    param($Value)
    if ($null -eq $Value) {
        if ($null -ne (Get-MpoValue)) {
            Remove-ItemProperty -Path $RegKey -Name $RegName -ErrorAction Stop
        }
    } else {
        New-ItemProperty -Path $RegKey -Name $RegName -PropertyType DWord `
            -Value ([int]$Value) -Force | Out-Null
    }
}

function Read-State {
    if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
    try {
        return (Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-State {
    param($State)
    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function New-State {
    [pscustomobject]@{ original = $null; lastApply = $null }
}

function Invoke-ElevatedSelf {
    # Re-launch this script elevated to perform a single raw registry op.
    param([string[]]$ChildArgs)
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',
                 ('"' + $PSCommandPath + '"')) + $ChildArgs
    try {
        $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
                -ArgumentList $argList -Wait -PassThru
        return [int]$p.ExitCode
    } catch {
        Write-Host ("  Elevation cancelled or failed: " + $_.Exception.Message) `
            -ForegroundColor Yellow
        return 1
    }
}

function Apply-MpoChange {
    # Apply a registry change, elevating only if needed.
    # $TargetValue -eq $null => delete the value. Returns $true on success.
    param($TargetValue)
    if (Test-Admin) {
        try {
            Set-MpoRegistry $TargetValue
            return $true
        } catch {
            Write-Host ("  Registry op failed: " + $_.Exception.Message) -ForegroundColor Red
            return $false
        }
    }
    $childArgs = if ($null -eq $TargetValue) { @('-RawDelete') }
                 else { @('-RawWrite', "$TargetValue") }
    return ((Invoke-ElevatedSelf $childArgs) -eq 0)
}

function Show-RebootState {
    param($State)
    if ($null -eq $State -or $null -eq $State.lastApply) { return }
    try {
        $stored = [datetime]$State.lastApply.bootTime
        $now    = Get-BootTime
        if ($now -gt $stored.AddSeconds(5)) {
            Write-Host ("Last action     : {0} ({1})  ->  EFFECTIVE (rebooted since)" -f `
                $State.lastApply.kind, $State.lastApply.at) -ForegroundColor Green
        } else {
            Write-Host ("Last action     : {0} ({1})  ->  WRITTEN, PENDING REBOOT" -f `
                $State.lastApply.kind, $State.lastApply.at) -ForegroundColor Yellow
            Write-Host "                  (the change is NOT active until you reboot)" `
                -ForegroundColor Yellow
        }
    } catch { }
}

function Do-Reboot {
    Write-Host ""
    Write-Host "Rebooting in 10 seconds.  Cancel with:  shutdown /a" -ForegroundColor Yellow
    & shutdown.exe /r /t 10 /c "CF7 mpo-toggle: applying MPO registry change" | Out-Null
}

# === internal raw branch (runs only inside the elevated child process) =====
if ($RawDelete -or $RawWrite -ge 0) {
    if (-not (Test-Admin)) {
        Write-Host "ERROR: raw registry op requires administrator rights." -ForegroundColor Red
        exit 1
    }
    try {
        if ($RawDelete) { Set-MpoRegistry $null }
        else            { Set-MpoRegistry $RawWrite }
        exit 0
    } catch {
        Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}

# === actions ===============================================================
function Invoke-Status {
    $cur   = Get-MpoValue
    $state = Read-State

    Write-Host ""
    Write-Host "=== CF7 MPO toggle - status ===" -ForegroundColor Cyan
    if ($null -eq $cur) {
        Write-Host "OverlayTestMode : (not set)"
        Write-Host "MPO state       : default (Windows decides; MPO may be used)"
    } else {
        Write-Host ("OverlayTestMode : {0}" -f $cur)
        if ($cur -eq $MpoOffVal) {
            Write-Host "MPO state       : DISABLED (OverlayTestMode=5)" -ForegroundColor Green
        } else {
            Write-Host ("MPO state       : non-default (value {0}; standard MPO-off is 5)" -f $cur) `
                -ForegroundColor Yellow
        }
    }

    if ($null -ne $state -and $null -ne $state.original) {
        $o = $state.original
        $base = if ($o.existed) { "OverlayTestMode=$($o.value)" } else { "(not set)" }
        Write-Host ("Tool snapshot   : baseline = {0}  (captured {1})" -f $base, $o.capturedAt)
    } elseif ($null -ne $cur) {
        Write-Host "Tool snapshot   : none -- OverlayTestMode was set outside this tool"
        Write-Host "                  (-Restore needs a snapshot; see tools/mpo/README.md)"
    } else {
        Write-Host "Tool snapshot   : none"
    }

    Show-RebootState $state

    Write-Host ""
    Write-Host "Usage : mpo-toggle.ps1 [-Status | -Disable | -Restore] [-Reboot]" -ForegroundColor DarkGray
    Write-Host "Measure: tools\sample-launcher-gpu.ps1   (GPU load, before/after)" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-Disable {
    $cur   = Get-MpoValue
    $state = Read-State
    if ($null -eq $state) { $state = New-State }

    if ($cur -eq $MpoOffVal) {
        if ($null -eq $state.original) {
            $state.original = [pscustomobject]@{
                existed    = $true
                value      = $MpoOffVal
                capturedAt = (Get-Date).ToString('o')
                note       = 'OverlayTestMode=5 was already set before this tool ran; adopted as baseline'
            }
            Write-State $state
            Write-Host "Note: OverlayTestMode=5 was already set (not by this tool)." -ForegroundColor Yellow
            Write-Host "      Adopted as the restore baseline -- -Restore will return to 5, not remove it." -ForegroundColor Yellow
            Write-Host "      To make 'MPO on' the baseline, remove OverlayTestMode manually first." -ForegroundColor Yellow
        }
        Write-Host "MPO is already disabled (OverlayTestMode=5). Nothing to do." -ForegroundColor Green
        Show-RebootState $state
        return
    }

    # Capture the pristine baseline exactly once.
    if ($null -eq $state.original) {
        $state.original = [pscustomobject]@{
            existed    = ($null -ne $cur)
            value      = $cur
            capturedAt = (Get-Date).ToString('o')
            note       = 'pre-tool state'
        }
        Write-State $state
    }

    Write-Host ""
    Write-Host "About to write a SYSTEM-WIDE setting:" -ForegroundColor Yellow
    Write-Host ("  {0}\{1} = {2}  (DWORD)" -f $RegKey, $RegName, $MpoOffVal)
    Write-Host "A UAC prompt will appear -- approve it to continue." -ForegroundColor Yellow

    if (-not (Apply-MpoChange -TargetValue $MpoOffVal)) {
        Write-Host "Aborted: the registry write did not complete." -ForegroundColor Red
        return
    }

    $new = Get-MpoValue
    if ($new -ne $MpoOffVal) {
        Write-Host ("Verification FAILED: OverlayTestMode is now '{0}', expected {1}." -f $new, $MpoOffVal) `
            -ForegroundColor Red
        return
    }

    $state.lastApply = [pscustomobject]@{
        kind        = 'disable-mpo'
        targetValue = $MpoOffVal
        at          = (Get-Date).ToString('o')
        bootTime    = (Get-BootTime).ToString('o')
    }
    Write-State $state

    Write-Host ""
    Write-Host "MPO disabled: OverlayTestMode=5 written and verified." -ForegroundColor Green
    Write-Host "REBOOT REQUIRED for this to take effect." -ForegroundColor Yellow

    if ($Reboot) { Do-Reboot }
    else { Write-Host "Reboot now, or re-run with -Reboot." -ForegroundColor DarkGray }
}

function Invoke-Restore {
    $state = Read-State
    if ($null -eq $state -or $null -eq $state.original) {
        Write-Host "No snapshot found -- this tool has not captured a baseline." -ForegroundColor Yellow
        Write-Host "Nothing to restore. Current state:" -ForegroundColor Yellow
        $cur = Get-MpoValue
        if ($null -eq $cur) { Write-Host "  OverlayTestMode : (not set)" }
        else { Write-Host ("  OverlayTestMode : {0}" -f $cur) }
        Write-Host "  To remove it manually, run elevated:" -ForegroundColor DarkGray
        Write-Host "    Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' OverlayTestMode" `
            -ForegroundColor DarkGray
        return
    }

    $o   = $state.original
    $cur = Get-MpoValue

    $atBaseline = ($o.existed -and $cur -eq $o.value) -or `
                  ((-not $o.existed) -and $null -eq $cur)
    if ($atBaseline) {
        $desc = if ($o.existed) { "OverlayTestMode=$($o.value)" } else { "(not set)" }
        Write-Host ("Already at the baseline ({0}). Clearing snapshot." -f $desc) -ForegroundColor Green
        $state.original = $null
        Write-State $state
        return
    }

    if ($o.existed) {
        $target = [int]$o.value
        $desc   = "OverlayTestMode=$($o.value)"
    } else {
        $target = $null
        $desc   = "(remove OverlayTestMode)"
    }

    Write-Host ""
    Write-Host ("About to restore the baseline: {0}" -f $desc) -ForegroundColor Yellow
    Write-Host "A UAC prompt will appear -- approve it to continue." -ForegroundColor Yellow

    if (-not (Apply-MpoChange -TargetValue $target)) {
        Write-Host "Aborted: the registry restore did not complete." -ForegroundColor Red
        return
    }

    $new = Get-MpoValue
    $ok  = ($o.existed -and $new -eq $o.value) -or `
           ((-not $o.existed) -and $null -eq $new)
    if (-not $ok) {
        Write-Host ("Verification FAILED: OverlayTestMode is now '{0}'." -f $new) -ForegroundColor Red
        return
    }

    $state.lastApply = [pscustomobject]@{
        kind        = 'restore'
        targetValue = $o.value
        at          = (Get-Date).ToString('o')
        bootTime    = (Get-BootTime).ToString('o')
    }
    $state.original = $null                                # baseline consumed
    Write-State $state

    Write-Host ""
    Write-Host ("MPO setting restored to baseline: {0}." -f $desc) -ForegroundColor Green
    Write-Host "REBOOT REQUIRED for this to take effect." -ForegroundColor Yellow

    if ($Reboot) { Do-Reboot }
    else { Write-Host "Reboot now, or re-run with -Reboot." -ForegroundColor DarkGray }
}

# === dispatch ==============================================================
if ($Disable -and $Restore) {
    Write-Host "ERROR: use only one of -Disable / -Restore." -ForegroundColor Red
    exit 1
}

if ($Disable)     { Invoke-Disable }
elseif ($Restore) { Invoke-Restore }
else              { Invoke-Status }
