@echo off
rem The borc command. borc copies this file to %LOCALAPPDATA%\borc\bin, which
rem is on the user PATH. Bypass applies to this pwsh process only.
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\borc\engine\src\borc.ps1" %*
exit /b %ERRORLEVEL%
