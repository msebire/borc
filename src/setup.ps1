# Second half of install.ps1, run under PowerShell 7 from the engine clone.
Import-Module -Name (Join-Path $PSScriptRoot 'borc\borc.psd1') -Force
exit (Invoke-BorcSetup)
