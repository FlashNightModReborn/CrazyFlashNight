@echo off
REM 代理启动器：从fscommand目录跳转到CFN-RAG-v*.exe所在目录并启动
setlocal
pushd "%~dp0.."
cd ..
for %%f in (CFN-RAG-v*.exe) do (
    start "" "%%~ff"
    popd
    exit /b 0
)
popd
exit /b 1