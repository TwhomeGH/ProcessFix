@echo off
setlocal
rem Use the installed CLI with this project's configuration.
set "PYTHONUTF8=1"
set "PYTHONDONTWRITEBYTECODE=1"
where changelogkit >nul 2>nul
if errorlevel 1 (
    echo The installed changelogkit command was not found on PATH.
    pause
    exit /b 1
)
pushd "%~dp0."
if errorlevel 1 exit /b 1
if "%~1"=="" (
    changelogkit --locale zh-TW serve --port 8711
) else (
    changelogkit --locale zh-TW %*
)
set "CHANGELOGKIT_EXIT=%ERRORLEVEL%"
popd
if not "%CHANGELOGKIT_EXIT%"=="0" pause
exit /b %CHANGELOGKIT_EXIT%
