@echo off
chcp 65001 >nul 2>&1
title CF7 Packer
setlocal enabledelayedexpansion

set "ELECTRON_RUN_AS_NODE="

set "TOOL_ROOT=%~dp0"
set "ELECTRON_VER=35.7.5"
set "ELECTRON_MAIN=!TOOL_ROOT!packages\web\dist\electron\main.cjs"

set "CACHE_DIR=%TEMP%\cf7-electron-v%ELECTRON_VER%"
set "CACHE_EXE=!CACHE_DIR!\dist\electron.exe"
set "NPM_EXE=!TOOL_ROOT!node_modules\electron\dist\electron.exe"

set "EXPECTED_SHA256=b87b2d6167845ece1d373eb37f5ce49868a07ec90203de44b6bd415d6c673c6d"
set "MIRROR_URL=https://cdn.npmmirror.com/binaries/electron/v%ELECTRON_VER%/electron-v%ELECTRON_VER%-win32-x64.zip"
set "GITHUB_URL=https://github.com/electron/electron/releases/download/v%ELECTRON_VER%/electron-v%ELECTRON_VER%-win32-x64.zip"

pushd "!TOOL_ROOT!"

:: === Phase 1: npm deps + build ===
call node scripts\ensure-runtime.mjs
if errorlevel 1 goto :phase1_fail
goto :phase1_ok

:phase1_fail
echo.
echo [X] Runtime preparation failed.
goto :fail

:phase1_ok

:: === Phase 2: locate Electron binary ===
set "ELECTRON_EXE="

if exist "!CACHE_EXE!" goto :found_cache
goto :try_npm

:found_cache
echo [OK] Electron: TEMP cache
set "ELECTRON_EXE=!CACHE_EXE!"
set "ELECTRON_DIST=!CACHE_DIR!\dist"
goto :electron_ready

:try_npm
if exist "!NPM_EXE!" goto :found_npm
goto :need_download

:found_npm
echo [OK] Electron: node_modules
set "ELECTRON_EXE=!NPM_EXE!"
set "ELECTRON_DIST=!TOOL_ROOT!node_modules\electron\dist"
goto :electron_ready

:need_download
:: === Phase 3: download Electron ===
echo [*] Electron v%ELECTRON_VER% not found, downloading...
echo     Target: !CACHE_DIR!\electron.zip

if not exist "!CACHE_DIR!" mkdir "!CACHE_DIR!"
set "ZIP_PATH=!CACHE_DIR!\electron.zip"

:: Pre-clean: delete any existing zip smaller than 50 MB (treat as corrupt / partial)
:: This prevents previous failed runs from short-circuiting all 4 strategies
:: (the legitimate zip is ~115 MB; any smaller file is guaranteed garbage)
if exist "!ZIP_PATH!" (
    for %%S in ("!ZIP_PATH!") do set "ZIP_SIZE=%%~zS"
    if !ZIP_SIZE! LSS 52428800 (
        echo     [!] Existing zip looks corrupt ^(!ZIP_SIZE! bytes^), removing...
        del "!ZIP_PATH!" 2>nul
    )
)

:: Helper macro concept: each strategy inlines its own size check.
:: A "success" means curl/powershell exited 0 AND file is >= 50 MB.
:: The legitimate zip is ~115 MB; anything smaller is garbage (HTML error page,
:: partial/aborted download). We fall through to the next strategy on garbage.

:: Strategy 1: curl + GitHub (primary — direct, no mirror)
if exist "!ZIP_PATH!" goto :download_done
where curl >nul 2>&1
if errorlevel 1 goto :try_curl_mirror
echo     [1/4] curl + GitHub...
curl -fSL --connect-timeout 15 --max-time 300 --retry 1 -o "!ZIP_PATH!" "!GITHUB_URL!" 2>nul
if errorlevel 1 goto :s1_cleanup
for %%S in ("!ZIP_PATH!") do set "ZIP_SIZE=%%~zS"
if !ZIP_SIZE! GEQ 52428800 goto :download_done
echo     [!] Strategy 1 file too small ^(!ZIP_SIZE! bytes^), trying next...
:s1_cleanup
del "!ZIP_PATH!" 2>nul

:try_curl_mirror
:: Strategy 2: curl + npmmirror (fallback if GitHub blocked)
if exist "!ZIP_PATH!" goto :download_done
where curl >nul 2>&1
if errorlevel 1 goto :try_ps_proxy
echo     [2/4] curl + npmmirror...
curl -fSL --connect-timeout 15 --max-time 300 --retry 1 -o "!ZIP_PATH!" "!MIRROR_URL!" 2>nul
if errorlevel 1 goto :s2_cleanup
for %%S in ("!ZIP_PATH!") do set "ZIP_SIZE=%%~zS"
if !ZIP_SIZE! GEQ 52428800 goto :download_done
echo     [!] Strategy 2 file too small ^(!ZIP_SIZE! bytes^), trying next...
:s2_cleanup
del "!ZIP_PATH!" 2>nul

:try_ps_proxy
:: Strategy 3: PowerShell + system proxy
if exist "!ZIP_PATH!" goto :download_done
echo     [3/4] PowerShell + system proxy...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { (New-Object System.Net.WebClient).DownloadFile('!GITHUB_URL!', '!ZIP_PATH!') } catch { exit 1 }" 2>nul
if errorlevel 1 goto :s3_cleanup
for %%S in ("!ZIP_PATH!") do set "ZIP_SIZE=%%~zS"
if !ZIP_SIZE! GEQ 52428800 goto :download_done
echo     [!] Strategy 3 file too small ^(!ZIP_SIZE! bytes^), trying next...
:s3_cleanup
del "!ZIP_PATH!" 2>nul

:: Strategy 4: PowerShell direct (no proxy)
if exist "!ZIP_PATH!" goto :download_done
echo     [4/4] PowerShell direct...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { $wc = New-Object System.Net.WebClient; $wc.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy(); $wc.DownloadFile('!GITHUB_URL!', '!ZIP_PATH!') } catch { exit 1 }" 2>nul
if errorlevel 1 goto :s4_cleanup
for %%S in ("!ZIP_PATH!") do set "ZIP_SIZE=%%~zS"
if !ZIP_SIZE! GEQ 52428800 goto :download_done
echo     [!] Strategy 4 file too small ^(!ZIP_SIZE! bytes^), giving up.
:s4_cleanup
del "!ZIP_PATH!" 2>nul

:: All strategies failed
goto :download_failed

:download_failed
echo.
echo [X] All download methods failed.
echo.
echo     Please download manually:
echo       Mirror: !MIRROR_URL!
echo       GitHub: !GITHUB_URL!
echo.
echo     Save as: !ZIP_PATH!
echo     Then re-run launch.bat.
goto :fail

:download_done

:: === Phase 3.5: verify checksum ===
echo     Verifying SHA256 checksum...
for /f "skip=1 delims=" %%H in ('certutil -hashfile "!ZIP_PATH!" SHA256') do if not defined ACTUAL_SHA256 set "ACTUAL_SHA256=%%H"
set "ACTUAL_SHA256=!ACTUAL_SHA256: =!"
if /i not "!ACTUAL_SHA256!"=="!EXPECTED_SHA256!" (
    echo [X] SHA256 checksum mismatch!
    echo     Expected: !EXPECTED_SHA256!
    echo     Actual:   !ACTUAL_SHA256!
    echo     The downloaded file may be corrupted or tampered with.
    del "!ZIP_PATH!" 2>nul
    goto :fail
)
echo     Checksum OK.

:: === Phase 4: extract ===
echo     Extracting...
powershell -NoProfile -Command "Expand-Archive -Path '!ZIP_PATH!' -DestinationPath '!CACHE_DIR!\dist' -Force"

if not exist "!CACHE_EXE!" goto :extract_failed
goto :extract_ok

:extract_failed
echo [X] Extract failed, zip may be corrupted. Deleting...
del "!ZIP_PATH!" 2>nul
echo     Re-run launch.bat to retry.
goto :fail

:extract_ok
echo [OK] Electron v%ELECTRON_VER% ready.
set "ELECTRON_EXE=!CACHE_EXE!"
set "ELECTRON_DIST=!CACHE_DIR!\dist"

:: === Phase 5: launch ===
:electron_ready

if not exist "!ELECTRON_MAIN!" goto :main_missing
goto :do_launch

:main_missing
echo [X] Main process bundle missing: !ELECTRON_MAIN!
goto :fail

:do_launch
set "ELECTRON_OVERRIDE_DIST_PATH=!ELECTRON_DIST!"

echo Starting CF7 Packer...
start "" "!ELECTRON_EXE!" "!ELECTRON_MAIN!"
popd
exit /b 0

:fail
echo.
popd
pause
exit /b 1
