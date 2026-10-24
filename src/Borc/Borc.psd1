@{
  RootModule = 'Borc.psm1'
  # Set when a release is cut, together with its CHANGELOG.md section.
  ModuleVersion = '0.0.0'
  GUID = '6f0c3c1e-6d0a-4c41-9a63-2b9b8d7e1a54'
  Description = 'borc: turns a blank Windows machine into a working developer workstation with winget and WinGet Configuration.'
  PowerShellVersion = '7.2'
  CompatiblePSEditions = @('Core')
  FunctionsToExport = @('Invoke-Borc', 'Invoke-BorcSetup', 'Get-BorcSecret')
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
}
