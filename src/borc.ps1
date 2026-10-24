# Runs one borc command. Started by borc.cmd; the arguments arrive in $args.
Import-Module -Name (Join-Path $PSScriptRoot 'Borc\Borc.psd1') -Force
exit (Invoke-Borc -Arguments $args)
