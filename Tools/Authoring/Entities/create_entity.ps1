#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function ConvertTo-EntityId {
    param([Parameter(Mandatory = $true)][string]$Text)

    $value = $Text.Trim()
    $value = [regex]::Replace($value, '([A-Z]+)([A-Z][a-z])', '$1_$2')
    $value = [regex]::Replace($value, '([a-z0-9])([A-Z])', '$1_$2')
    $value = [regex]::Replace($value, '[ _-]+', '_')
    return $value.Trim('_').ToLowerInvariant()
}


function Resolve-ScaffoldChildPath {
    param([string]$RootPath, [string]$CandidatePath)

    $rootPrefix = [System.IO.Path]::GetFullPath($RootPath).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($CandidatePath)

    if (-not $fullPath.StartsWith(
        $rootPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Path is outside the expected directory: $fullPath"
    }

    return $fullPath
}


function Write-EntityScript {
    param([string]$StagingRoot, [string]$RelativePath, [string]$Text)

    $outputPath = Resolve-ScaffoldChildPath $StagingRoot (
        Join-Path $StagingRoot $RelativePath
    )
    $textWithTabs = [regex]::Replace(
        $Text,
        '(?m)^(?: {4})+',
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($indentMatch)
            return ([string][char]9) * [int]($indentMatch.Length / 4)
        }
    )
    $normalizedText = $textWithTabs -replace '\r?\n', [Environment]::NewLine
    [System.IO.File]::WriteAllText(
        $outputPath,
        $normalizedText.TrimEnd() + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}


function Get-RegisteredEntityIds {
    $arguments = @(
        '--headless'
        '--path'
        $projectRoot
        '--log-file'
        $logPath
        '--script'
        'res://Framework/Env/Authoring/entity_scene_authoring.gd'
        '--'
        'list'
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $nativeOutput = @(& $godotExe @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }

    $prefix = '[authoring-result] '
    $resultLines = @(
        $nativeOutput |
            ForEach-Object { $_.ToString() } |
            Where-Object { $_.StartsWith($prefix) }
    )
    if ($resultLines.Count -ne 1) {
        throw (
            'Godot did not return the entity catalogue.' +
            [Environment]::NewLine +
            ($nativeOutput -join [Environment]::NewLine)
        )
    }

    $result = $resultLines[0].Substring($prefix.Length) | ConvertFrom-Json
    if ($exitCode -ne 0 -or -not $result.ok) {
        throw "Entity discovery failed: $($result.error)"
    }

    return $result.value
}


$projectRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\..\framework-project')
)
$entityRoot = Join-Path $projectRoot 'Framework\Content\Presentation\Entity'
$helperPath = Join-Path $projectRoot 'Framework\Env\Authoring\entity_scene_authoring.gd'

if (-not (Test-Path -LiteralPath $entityRoot -PathType Container)) {
    throw "Entity presentation directory was not found: $entityRoot"
}
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Authoring helper was not found: $helperPath"
}

$godotExe = (Get-Command 'Godot_v4.7.1-stable_win64_console.exe' -CommandType Application).Path
$jobRoot = Resolve-ScaffoldChildPath $PSScriptRoot (
    Join-Path $PSScriptRoot ('.entity-' + [guid]::NewGuid().ToString('N'))
)
$stagingRoot = Join-Path $jobRoot 'entity'
$logPath = Join-Path $jobRoot 'godot.log'

try {
    [void][System.IO.Directory]::CreateDirectory($stagingRoot)
    $usedIds = @{}

    # Ask the real catalogue so IDs are checked without parsing GDScript text.
    foreach ($registeredId in @(Get-RegisteredEntityIds)) {
        $usedIds[(ConvertTo-EntityId -Text ([string]$registeredId))] = $true
    }
    foreach ($folder in Get-ChildItem -LiteralPath $entityRoot -Directory -Force) {
        $usedIds[(ConvertTo-EntityId -Text $folder.Name)] = $true
    }

    while ($true) {
        $displayName = Read-Host 'Name of the entity to create'
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            Write-Warning 'Enter an entity name.'
            continue
        }

        $displayName = $displayName.Trim()
        if ($displayName -notmatch '^[A-Za-z][A-Za-z0-9 _-]*\z') {
            Write-Warning (
                'Start with a letter. Use letters, numbers, spaces, ' +
                'underscores, or hyphens.'
            )
            continue
        }

        $entityId = ConvertTo-EntityId -Text $displayName
        $folderName = (($entityId -split '_') | ForEach-Object {
            $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
        }) -join ''

        if ($folderName -match '^(Shared|CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            Write-Warning "'$displayName' is a reserved name."
            continue
        }

        $entityPath = Resolve-ScaffoldChildPath $entityRoot (
            Join-Path $entityRoot $folderName
        )
        if ($usedIds.ContainsKey($entityId) -or (Test-Path -LiteralPath $entityPath)) {
            Write-Warning "An entity named '$entityId' already exists. Choose another name."
            continue
        }

        break
    }

    $startingPreset = @'
extends RefCounted

const StartingAttributes = preload(
    "res://Framework/Env/Setup/starting_attributes.gd"
)


static func definition() -> Dictionary:
    return StartingAttributes.define(
        &"__ENTITY_ID__",
        [
            "Attributes/Identity/identity.gd",
            "Attributes/Statistics/health.gd",
            "Attributes/Statistics/speed.gd",
            "Interactions/interactions.gd",
        ],
        {
            &"identity": {
                "name": "__ENTITY_NAME__",
            },
        }
    )
'@

    $presentationProfile = @'
extends RefCounted

const EntitySceneDefaults = preload(
    "res://Framework/Content/Configuration/Presentation/entity_scene_defaults.gd"
)


static func defaults() -> Dictionary:
    return EntitySceneDefaults.defaults()
'@

    Write-EntityScript $stagingRoot 'starting_attributes.gd' (
        $startingPreset.Replace('__ENTITY_ID__', $entityId).Replace(
            '__ENTITY_NAME__', $displayName
        )
    )
    Write-EntityScript $stagingRoot 'presentation.gd' $presentationProfile

    # Publish both files together; Directory.Move refuses an existing target.
    $checkedSource = Resolve-ScaffoldChildPath $jobRoot $stagingRoot
    $checkedDestination = Resolve-ScaffoldChildPath $entityRoot $entityPath
    [System.IO.Directory]::Move($checkedSource, $checkedDestination)

    Write-Host ''
    Write-Host "Created entity: $entityId"
    Write-Host "Folder: $entityPath"
    Write-Host ('Starting preset: ' + (Join-Path $entityPath 'starting_attributes.gd'))
    Write-Host ('Presentation profile: ' + (Join-Path $entityPath 'presentation.gd'))
    Write-Host 'GDScript files: 2'
}
finally {
    $cleanupPath = [System.IO.Path]::GetFullPath($jobRoot)
    $jobParent = [System.IO.Path]::GetDirectoryName($cleanupPath)
    $jobName = [System.IO.Path]::GetFileName($cleanupPath)
    if (
        -not [string]::Equals(
            $jobParent,
            [System.IO.Path]::GetFullPath($PSScriptRoot),
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or $jobName -notmatch '^\.entity-[a-f0-9]{32}$'
    ) {
        throw 'Unexpected temporary directory location.'
    }

    if (Test-Path -LiteralPath $cleanupPath) {
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force
    }
}
