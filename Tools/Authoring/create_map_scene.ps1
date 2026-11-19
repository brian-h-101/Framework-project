#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function ConvertTo-SceneId {
    param([string]$Text)

    $value = $Text.Trim()
    $value = [regex]::Replace($value, '([A-Z]+)([A-Z][a-z])', '$1_$2')
    $value = [regex]::Replace($value, '([a-z0-9])([A-Z])', '$1_$2')
    $value = [regex]::Replace($value, '[ _-]+', '_')

    return $value.Trim('_').ToLowerInvariant()
}


function Invoke-MapAuthoring {
    param([string[]]$OperationArgs)

    $arguments = @(
        '--headless'
        '--path'
        $projectRoot
        '--log-file'
        $logPath
        '--script'
        'res://Framework/Env/Authoring/map_scene_authoring.gd'
        '--'
    ) + $OperationArgs

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
            'Godot did not return an authoring result.' +
            [Environment]::NewLine +
            ($nativeOutput -join [Environment]::NewLine)
        )
    }

    $result = $resultLines[0].Substring($prefix.Length) | ConvertFrom-Json

    if ($exitCode -ne 0 -or -not $result.ok) {
        throw "Map authoring failed: $($result.error)"
    }

    return $result
}


$projectRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\framework-project')
)
$worldRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'Games\ExampleGame\World')
)
$helperPath = Join-Path $projectRoot 'Framework\Env\Authoring\map_scene_authoring.gd'

if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Map authoring helper was not found: $helperPath"
}

if (-not (Test-Path -LiteralPath $worldRoot -PathType Container)) {
    throw "Map directory was not found: $worldRoot"
}

$godotExe = (Get-Command 'Godot_v4.7.1-stable_win64_console.exe' -CommandType Application).Path

while ($true) {
    $displayName = (Read-Host 'Name of the map scene to create').Trim()

    if ($displayName -notmatch '^[A-Za-z][A-Za-z0-9 _-]*\z') {
        Write-Warning 'Start with a letter. Use letters, numbers, spaces, underscores, or hyphens.'
        continue
    }

    $sceneId = ConvertTo-SceneId -Text $displayName

    if ($sceneId -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        Write-Warning "'$displayName' is a reserved name."
        continue
    }

    $existingScenes = @(
        Get-ChildItem -LiteralPath $worldRoot -Filter '*.tscn' -File |
            Where-Object {
                (ConvertTo-SceneId -Text $_.BaseName) -eq $sceneId
            }
    )

    if ($existingScenes.Count -gt 0) {
        Write-Warning "A map named '$sceneId' already exists. Choose another name."
        continue
    }

    break
}

$sceneNodeName = (($sceneId -split '_') | ForEach-Object {
    $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
}) -join ''

$destination = [System.IO.Path]::GetFullPath(
    (Join-Path $worldRoot ($sceneId + '.tscn'))
)
$worldPrefix = $worldRoot + [System.IO.Path]::DirectorySeparatorChar

if (-not $destination.StartsWith(
    $worldPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw 'The output path is outside the map directory.'
}

$jobRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot ('.create-map-' + [guid]::NewGuid().ToString('N')))
)
$logPath = Join-Path $jobRoot 'godot.log'
$stagedScene = Join-Path $jobRoot 'map.tscn'

try {
    [void][System.IO.Directory]::CreateDirectory($jobRoot)

    $created = Invoke-MapAuthoring -OperationArgs @(
        'create',
        $sceneNodeName,
        $stagedScene
    )

    if (
        -not $created.value.structure_verified -or
        -not $created.value.content_verified
    ) {
        throw 'The generated map did not pass its verification.'
    }

    [System.IO.File]::Move($stagedScene, $destination)

    Write-Host ''
    Write-Host "Created map scene: res://Games/ExampleGame/World/$sceneId.tscn"
    Write-Host "Root node: $($created.value.node_name)"
    Write-Host "Root type: $($created.value.root_type)"
    Write-Host "Structure verified: $($created.value.structure_verified)"
    Write-Host "Content verified: $($created.value.content_verified)"
    Write-Host "UID: $($created.value.uid)"
}
finally {
    $jobParent = [System.IO.Path]::GetDirectoryName(
        [System.IO.Path]::GetFullPath($jobRoot)
    )

    if (-not [string]::Equals(
        $jobParent,
        [System.IO.Path]::GetFullPath($PSScriptRoot),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Unexpected temporary directory location.'
    }

    if (Test-Path -LiteralPath $jobRoot) {
        Remove-Item -LiteralPath $jobRoot -Recurse -Force
    }
}