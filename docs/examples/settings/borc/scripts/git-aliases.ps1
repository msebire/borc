# Loaded in every PowerShell 7 terminal by the borc profile block.
function gs { git status --short --branch @args }
function gl { git log --oneline --graph -20 @args }
