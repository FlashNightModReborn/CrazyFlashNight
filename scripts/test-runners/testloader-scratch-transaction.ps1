function Get-Cf7TestLoaderScratchRecord {
    param([Parameter(Mandatory = $true)][string]$MarkerPath)

    try {
        return ([System.IO.File]::ReadAllText(
                $MarkerPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
    } catch {
        throw "Cannot parse TestLoader scratch transaction marker '$MarkerPath': $($_.Exception.Message)"
    }
}

function New-Cf7TestLoaderScratchTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$MarkerPath,
        [Parameter(Mandatory = $true)][string]$RunnerPath,
        [Parameter(Mandatory = $true)][string]$RepoHash,
        [Parameter(Mandatory = $true)][string]$CompileLease,
        [Parameter(Mandatory = $true)][string]$OwnerKind
    )

    if (Test-Path -LiteralPath $MarkerPath) {
        throw 'A TestLoader scratch transaction is already in flight. Inspect its recovery backup and scripts/TestLoader.as before removing scripts/testloader_scratch_inflight.marker.'
    }

    $absoluteRunnerPath = [System.IO.Path]::GetFullPath($RunnerPath)
    $hadRunner = Test-Path -LiteralPath $absoluteRunnerPath
    $originalHash = $null
    $backupPath = $null
    $recoveryDirectory = $null
    $token = [System.Guid]::NewGuid().ToString('N')
    if ($hadRunner) {
        $originalHash = (Get-FileHash -LiteralPath $absoluteRunnerPath -Algorithm SHA256).Hash
        $recoveryDirectory = Join-Path (Split-Path -Parent $MarkerPath) `
            '.testloader-scratch-recovery'
        if (-not (Test-Path -LiteralPath $recoveryDirectory)) {
            [void](New-Item -ItemType Directory -Path $recoveryDirectory)
        }
        $backupPath = Join-Path $recoveryDirectory ($token + '.as')
        try {
            Copy-Item -LiteralPath $absoluteRunnerPath -Destination $backupPath
            if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -ne
                    $originalHash) {
                throw 'Persistent TestLoader recovery backup hash mismatch; scratch installation was not started.'
            }
        } catch {
            if (Test-Path -LiteralPath $backupPath) {
                Remove-Item -LiteralPath $backupPath -Force
            }
            if ((Test-Path -LiteralPath $recoveryDirectory) -and
                @(Get-ChildItem -LiteralPath $recoveryDirectory -Force).Count -eq 0) {
                Remove-Item -LiteralPath $recoveryDirectory -Force
            }
            throw
        }
    }

    $record = [ordered]@{
        schema = 'cf7-testloader-scratch-transaction.v1'
        token = $token
        created_utc = [System.DateTime]::UtcNow.ToString('o')
        owner_pid = $PID
        owner_kind = $OwnerKind
        repo_hash = $RepoHash
        compile_lease = $CompileLease
        runner_path = $absoluteRunnerPath
        had_runner = $hadRunner
        backup_path = $backupPath
        original_sha256 = $originalHash
    }
    $body = $record | ConvertTo-Json -Compress
    try {
        [System.IO.File]::WriteAllText(
            $MarkerPath, $body, [System.Text.UTF8Encoding]::new($false))
        if ([System.IO.File]::ReadAllText(
                $MarkerPath, [System.Text.Encoding]::UTF8) -cne $body) {
            throw 'TestLoader scratch transaction marker was not written byte-exactly; refusing to install scratch.'
        }
    } catch {
        # Scratch has not been installed yet. Clean only artifacts that are still
        # byte-exactly ours; otherwise retain marker+backup for manual inspection.
        if (Test-Path -LiteralPath $MarkerPath) {
            try {
                if ([System.IO.File]::ReadAllText(
                        $MarkerPath, [System.Text.Encoding]::UTF8) -ceq $body) {
                    Remove-Item -LiteralPath $MarkerPath -Force
                }
            } catch {}
        }
        if (-not (Test-Path -LiteralPath $MarkerPath) -and $backupPath -and
            (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Force
        }
        if ($recoveryDirectory -and
            (Test-Path -LiteralPath $recoveryDirectory) -and
            @(Get-ChildItem -LiteralPath $recoveryDirectory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $recoveryDirectory -Force
        }
        throw
    }

    return [pscustomobject]@{
        MarkerPath = $MarkerPath
        MarkerBody = $body
        RunnerPath = $absoluteRunnerPath
        HadRunner = $hadRunner
        BackupPath = $backupPath
        OriginalHash = $originalHash
        CompileLease = $CompileLease
        RepoHash = $RepoHash
        OwnerKind = $OwnerKind
    }
}

function Assert-Cf7TestLoaderScratchReadyToInstall {
    param([Parameter(Mandatory = $true)]$Transaction)

    if (-not (Test-Path -LiteralPath $Transaction.MarkerPath) -or
        [System.IO.File]::ReadAllText(
            $Transaction.MarkerPath, [System.Text.Encoding]::UTF8) -cne
            $Transaction.MarkerBody) {
        throw 'TestLoader scratch transaction marker changed before installation.'
    }
    if ($Transaction.HadRunner) {
        if (-not (Test-Path -LiteralPath $Transaction.RunnerPath) -or
            (Get-FileHash -LiteralPath $Transaction.RunnerPath -Algorithm SHA256).Hash -ne
                $Transaction.OriginalHash) {
            throw 'TestLoader changed after its recovery snapshot; refusing scratch installation.'
        }
    } elseif (Test-Path -LiteralPath $Transaction.RunnerPath) {
        throw 'TestLoader appeared after the transaction recorded that it was absent.'
    }
}

function Assert-Cf7TestLoaderScratchAdmission {
    param(
        [Parameter(Mandatory = $true)][string]$MarkerPath,
        [Parameter(Mandatory = $true)][string]$RunnerPath,
        [Parameter(Mandatory = $true)][string]$RepoHash,
        [AllowEmptyString()][string]$CompileLease,
        [int]$LeaseOwnerPid
    )

    $hasMarker = Test-Path -LiteralPath $MarkerPath
    $hasLease = -not [string]::IsNullOrWhiteSpace($CompileLease)
    if (-not $hasLease) {
        if ($hasMarker) {
            throw 'An unfinished TestLoader scratch transaction blocks ordinary compilation. Inspect the marker, recovery backup, and scripts/TestLoader.as before manual recovery.'
        }
        return
    }
    if (-not $hasMarker) {
        throw 'A focused compile lease has no persistent TestLoader scratch transaction marker.'
    }

    $record = Get-Cf7TestLoaderScratchRecord -MarkerPath $MarkerPath
    if ($record.schema -cne 'cf7-testloader-scratch-transaction.v1' -or
        $record.repo_hash -cne $RepoHash -or
        $record.compile_lease -cne $CompileLease -or
        [int]$record.owner_pid -ne $LeaseOwnerPid) {
        throw 'TestLoader scratch transaction identity does not match the focused compile lease.'
    }
    $expectedRunner = [System.IO.Path]::GetFullPath($RunnerPath).TrimEnd('\').ToUpperInvariant()
    $markedRunner = [System.IO.Path]::GetFullPath(
        [string]$record.runner_path).TrimEnd('\').ToUpperInvariant()
    if ($markedRunner -cne $expectedRunner) {
        throw 'TestLoader scratch transaction points at a different runner path.'
    }
    if ([bool]$record.had_runner) {
        if ([string]::IsNullOrWhiteSpace([string]$record.backup_path) -or
            -not (Test-Path -LiteralPath ([string]$record.backup_path))) {
            throw 'TestLoader scratch recovery backup is missing.'
        }
        $expectedRecoveryDirectory = [System.IO.Path]::GetFullPath(
            (Join-Path (Split-Path -Parent $MarkerPath) '.testloader-scratch-recovery')).
            TrimEnd('\').ToUpperInvariant()
        $markedRecoveryDirectory = [System.IO.Path]::GetFullPath(
            (Split-Path -Parent ([string]$record.backup_path))).
            TrimEnd('\').ToUpperInvariant()
        if ($markedRecoveryDirectory -cne $expectedRecoveryDirectory) {
            throw 'TestLoader scratch recovery backup is outside the repository recovery directory.'
        }
        if ((Get-FileHash -LiteralPath ([string]$record.backup_path) -Algorithm SHA256).Hash -ne
                [string]$record.original_sha256) {
            throw 'TestLoader scratch recovery backup hash does not match the transaction marker.'
        }
    }
}

function Restore-Cf7TestLoaderScratchTransaction {
    param(
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)][string]$InstalledHash
    )

    if (-not (Test-Path -LiteralPath $Transaction.MarkerPath) -or
        [System.IO.File]::ReadAllText(
            $Transaction.MarkerPath, [System.Text.Encoding]::UTF8) -cne
            $Transaction.MarkerBody) {
        throw 'TestLoader scratch transaction marker changed or disappeared; refusing automatic recovery.'
    }
    if (-not (Test-Path -LiteralPath $Transaction.RunnerPath) -or
        (Get-FileHash -LiteralPath $Transaction.RunnerPath -Algorithm SHA256).Hash -ne
            $InstalledHash) {
        throw 'TestLoader changed during the scratch transaction; refusing to overwrite that edit.'
    }

    if ($Transaction.HadRunner) {
        if (-not $Transaction.BackupPath -or
            -not (Test-Path -LiteralPath $Transaction.BackupPath)) {
            throw 'Cannot restore TestLoader because its persistent recovery backup is missing.'
        }
        if ((Get-FileHash -LiteralPath $Transaction.BackupPath -Algorithm SHA256).Hash -ne
                $Transaction.OriginalHash) {
            throw 'TestLoader recovery backup no longer matches its recorded SHA-256.'
        }
        Copy-Item -LiteralPath $Transaction.BackupPath `
            -Destination $Transaction.RunnerPath -Force
        if ((Get-FileHash -LiteralPath $Transaction.RunnerPath -Algorithm SHA256).Hash -ne
                $Transaction.OriginalHash) {
            throw 'Restored TestLoader hash does not match the original scratch runner.'
        }
    } else {
        Remove-Item -LiteralPath $Transaction.RunnerPath -Force
        if (Test-Path -LiteralPath $Transaction.RunnerPath) {
            throw 'Temporary TestLoader still exists after recovery removal.'
        }
    }

    if ([System.IO.File]::ReadAllText(
            $Transaction.MarkerPath, [System.Text.Encoding]::UTF8) -cne
            $Transaction.MarkerBody) {
        throw 'TestLoader scratch transaction marker changed during recovery.'
    }
    # Recovery is already byte-verified. A crash after clearing the marker but
    # before deleting the sidecar can leave only an inert orphan backup.
    Remove-Item -LiteralPath $Transaction.MarkerPath -Force
    if (Test-Path -LiteralPath $Transaction.MarkerPath) {
        throw 'TestLoader scratch transaction marker could not be cleared after verified recovery.'
    }
    if ($Transaction.BackupPath -and
        (Test-Path -LiteralPath $Transaction.BackupPath)) {
        Remove-Item -LiteralPath $Transaction.BackupPath -Force
        $recoveryDirectory = Split-Path -Parent $Transaction.BackupPath
        if ((Test-Path -LiteralPath $recoveryDirectory) -and
            @(Get-ChildItem -LiteralPath $recoveryDirectory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $recoveryDirectory -Force
        }
    }
}
