# Second half of install.ps1, run under PowerShell 7 from the engine clone.
Import-Module -Name (Join-Path $PSScriptRoot 'Borc\Borc.psd1') -Force
exit (Invoke-BorcSetup)
