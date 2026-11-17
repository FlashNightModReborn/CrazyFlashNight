[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,
    [string]$OutputRelativePath='tmp/tooltip-audit/tooltip-corpus.trace',
    [switch]$SkipCompile,[switch]$IncludeContext)
throw 'Issue #262 retired the AS2 content engine. Run the archived corpus runner in a separate baseline oracle worktree; see tools/tooltip-oracle/README.md. Never restore old builders to the production classpath.'
