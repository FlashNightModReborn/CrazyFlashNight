@echo off
REM 从 data\rag 定位到游戏根目录（..\..），再向上一级启动同目录下 CFN-RAG-v*.exe（版本号可变）
setlocal
pushd "%~dp0..\.."
cd ..
for %%f in (CFN-RAG-v*.exe) do (
  start "" "%%~ff"
  popd
  exit /b 0
)
popd
exit /b 1
