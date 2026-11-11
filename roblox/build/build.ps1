<#
    Builds StroopGame.rbxlx from the src/ tree.

    The place file contains nothing but Folders, Scripts, LocalScripts and
    ModuleScripts, so there are no serialized property values that a future
    Studio version could reject — everything else (lighting, character spawning,
    the camera) is configured at runtime by the scripts themselves.

    Naming follows the Rojo convention:
        Name.lua           -> ModuleScript "Name"
        Name.server.lua    -> Script       "Name"
        Name.client.lua    -> LocalScript  "Name"
        dir/init.lua       -> ModuleScript named after the directory
        dir/init.client.lua-> LocalScript  named after the directory
        dir/init.server.lua-> Script       named after the directory
        any other dir      -> Folder

    Usage:  powershell -ExecutionPolicy Bypass -File build\build.ps1
#>

[CmdletBinding()]
param(
    [string]$Source,
    [string]$Output
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
$projectRoot = Split-Path -Parent $scriptDir
if ([string]::IsNullOrEmpty($Source)) { $Source = Join-Path $projectRoot 'src' }
if ([string]::IsNullOrEmpty($Output)) { $Output = Join-Path $projectRoot 'StroopGame.rbxlx' }

if (-not (Test-Path $Source)) {
    throw "Source directory not found: $Source"
}

$script:Referent = 0
$script:Builder = New-Object System.Text.StringBuilder

function Next-Referent {
    $id = "RBX$script:Referent"
    $script:Referent++
    return $id
}

function Escape-Xml([string]$text) {
    if ($null -eq $text) { return '' }
    # Only these three are structural in element content. CR is normalized away
    # so Roblox does not see stray carriage returns inside Source.
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"
    $text = $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    # XML 1.0 forbids these control characters outright.
    $text = [regex]::Replace($text, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    return $text
}

function Add-Line([string]$line) {
    [void]$script:Builder.AppendLine($line)
}

function Get-ScriptClass([string]$fileName) {
    if ($fileName -like '*.server.lua') { return @{ Class = 'Script';       Name = $fileName -replace '\.server\.lua$', '' } }
    if ($fileName -like '*.client.lua') { return @{ Class = 'LocalScript';  Name = $fileName -replace '\.client\.lua$', '' } }
    if ($fileName -like '*.lua')        { return @{ Class = 'ModuleScript'; Name = $fileName -replace '\.lua$', '' } }
    return $null
}

function Write-ScriptItem([string]$class, [string]$name, [string]$sourcePath, [scriptblock]$children, [string]$indent) {
    $ref = Next-Referent
    $code = [System.IO.File]::ReadAllText($sourcePath)
    Add-Line "$indent<Item class=`"$class`" referent=`"$ref`">"
    Add-Line "$indent  <Properties>"
    Add-Line "$indent    <string name=`"Name`">$(Escape-Xml $name)</string>"
    Add-Line "$indent    <ProtectedString name=`"Source`">$(Escape-Xml $code)</ProtectedString>"
    Add-Line "$indent  </Properties>"
    if ($children) { & $children ("$indent  ") }
    Add-Line "$indent</Item>"
}

function Write-FolderItem([string]$class, [string]$name, [scriptblock]$children, [string]$indent) {
    $ref = Next-Referent
    Add-Line "$indent<Item class=`"$class`" referent=`"$ref`">"
    Add-Line "$indent  <Properties>"
    Add-Line "$indent    <string name=`"Name`">$(Escape-Xml $name)</string>"
    Add-Line "$indent  </Properties>"
    if ($children) { & $children ("$indent  ") }
    Add-Line "$indent</Item>"
}

# Emits every child of $dir, skipping whichever file became the container itself.
function Write-Children([string]$dir, [string]$skipFile, [string]$indent) {
    $entries = Get-ChildItem -LiteralPath $dir | Sort-Object { -not $_.PSIsContainer }, Name

    foreach ($entry in $entries) {
        if ($entry.PSIsContainer) {
            Write-Directory -Dir $entry.FullName -Indent $indent
            continue
        }
        if ($entry.Name -eq $skipFile) { continue }
        $info = Get-ScriptClass $entry.Name
        if ($null -eq $info) { continue }
        Write-ScriptItem -Class $info.Class -Name $info.Name -SourcePath $entry.FullName -Children $null -Indent $indent
    }
}

# Roblox services that own a class of their own rather than being plain folders.
$script:ServiceClasses = @{
    'ReplicatedStorage'      = 'ReplicatedStorage'
    'ServerScriptService'    = 'ServerScriptService'
    'ServerStorage'          = 'ServerStorage'
    'StarterGui'             = 'StarterGui'
    'StarterPlayer'          = 'StarterPlayer'
    'StarterPlayerScripts'   = 'StarterPlayerScripts'
    'StarterCharacterScripts'= 'StarterCharacterScripts'
    'ReplicatedFirst'        = 'ReplicatedFirst'
    'Workspace'              = 'Workspace'
    'Lighting'               = 'Lighting'
}

function Write-Directory([string]$Dir, [string]$Indent) {
    $name = Split-Path -Leaf $Dir

    $initModule = Join-Path $Dir 'init.lua'
    $initClient = Join-Path $Dir 'init.client.lua'
    $initServer = Join-Path $Dir 'init.server.lua'

    if (Test-Path -LiteralPath $initClient) {
        Write-ScriptItem -Class 'LocalScript' -Name $name -SourcePath $initClient -Indent $Indent -Children {
            param($childIndent) Write-Children -Dir $Dir -SkipFile 'init.client.lua' -Indent $childIndent
        }
        return
    }
    if (Test-Path -LiteralPath $initServer) {
        Write-ScriptItem -Class 'Script' -Name $name -SourcePath $initServer -Indent $Indent -Children {
            param($childIndent) Write-Children -Dir $Dir -SkipFile 'init.server.lua' -Indent $childIndent
        }
        return
    }
    if (Test-Path -LiteralPath $initModule) {
        Write-ScriptItem -Class 'ModuleScript' -Name $name -SourcePath $initModule -Indent $Indent -Children {
            param($childIndent) Write-Children -Dir $Dir -SkipFile 'init.lua' -Indent $childIndent
        }
        return
    }

    $class = $script:ServiceClasses[$name]
    if (-not $class) { $class = 'Folder' }
    Write-FolderItem -Class $class -Name $name -Indent $Indent -Children {
        param($childIndent) Write-Children -Dir $Dir -SkipFile $null -Indent $childIndent
    }
}

# ---------- emit ----------
Add-Line '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
Add-Line '  <External>null</External>'
Add-Line '  <External>nil</External>'

foreach ($service in (Get-ChildItem -LiteralPath $Source -Directory | Sort-Object Name)) {
    Write-Directory -Dir $service.FullName -Indent '  '
}

Add-Line '</roblox>'

$xml = $script:Builder.ToString()

# Fail loudly here rather than in Studio.
try {
    $doc = New-Object System.Xml.XmlDocument
    $doc.LoadXml($xml)
} catch {
    throw "Generated XML is not well-formed: $($_.Exception.Message)"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Output, $xml, $utf8NoBom)

$count = ([regex]::Matches($xml, '<Item class=')).Count
Write-Host "Wrote $Output"
Write-Host "  $count instances"
Write-Host "  $([math]::Round((Get-Item $Output).Length / 1KB)) KB"
