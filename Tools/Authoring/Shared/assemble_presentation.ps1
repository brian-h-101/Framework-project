#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Entity', 'Items', 'Objects')]
    [string]$Category
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function Invoke-EntityAuthoring {
    param([string[]]$OperationArgs)

    $arguments = @(
        '--headless'
        '--path'
        $projectRoot
        '--log-file'
        $logPath
        '--script'
        'res://Framework/Env/Authoring/entity_scene_authoring.gd'
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
        throw "Entity authoring failed: $($result.error)"
    }

    return $result
}


$projectRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..\..\framework-project')
)

$helperPath = Join-Path $projectRoot 'Framework\Env\Authoring\entity_scene_authoring.gd'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Authoring helper was not found: $helperPath"
}

$godotExe = (Get-Command 'Godot_v4.7.1-stable_win64_console.exe' -CommandType Application).Path

$jobRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot ('.assemble-' + [guid]::NewGuid().ToString('N')))
)
[void][System.IO.Directory]::CreateDirectory($jobRoot)
$logPath = Join-Path $jobRoot 'godot.log'

try {
    $listed = Invoke-EntityAuthoring -OperationArgs @('catalogue')
    $entries = @(
        $listed.value |
            Where-Object { $_.category -eq $Category }
    )

    if ($entries.Count -eq 0) {
        throw "No definitions were discovered for category: $Category"
    }

    Write-Host ('Available {0} definitions:' -f $Category)
    for ($index = 0; $index -lt $entries.Count; $index++) {
        Write-Host ('{0}. {1}' -f ($index + 1), $entries[$index].id)
    }

    while ($true) {
        $choiceText = Read-Host 'Select a definition number'
        $choice = 0

        if (
            [int]::TryParse($choiceText, [ref]$choice) -and
            $choice -ge 1 -and $choice -le $entries.Count
        ) {
            break
        }

        Write-Warning 'Choose one of the listed numbers.'
    }

    $selected = $entries[$choice - 1]
    $entityId = [string]$selected.id

    if ($entityId -cnotmatch '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$') {
        throw 'Scene generation currently requires lower_snake_case definition IDs.'
    }

    $scenePath = [string]$selected.scene_path
    if (-not $scenePath.StartsWith(
        'res://',
        [System.StringComparison]::Ordinal
    )) {
        throw 'The catalogue scene path must begin with res://.'
    }

    $presentationRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $projectRoot ('Framework\Content\Presentation\' + $Category))
    )
    $destination = [System.IO.Path]::GetFullPath(
        (Join-Path $projectRoot $scenePath.Substring(6).Replace('/', '\'))
    )

    if (-not $destination.StartsWith(
        $presentationRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'The output path is outside the selected presentation category.'
    }

    if (Test-Path -LiteralPath $destination) {
        throw "Presentation already exists: $destination"
    }

    $stagedScene = Join-Path $jobRoot 'presentation.tscn'
    $assembled = Invoke-EntityAuthoring -OperationArgs @(
        'assemble', $entityId, $stagedScene
    )

    if (
        -not $assembled.value.markers_verified -or
        -not $assembled.value.components_verified
    ) {
        throw 'The staged presentation failed verification.'
    }

    [void][System.IO.Directory]::CreateDirectory(
        [System.IO.Path]::GetDirectoryName($destination)
    )
    [System.IO.File]::Move($stagedScene, $destination)

    Write-Host ''
    Write-Host "Created presentation: $scenePath"
    Write-Host "Root type: $($assembled.value.root_type)"
    Write-Host "Markers verified: $($assembled.value.markers_verified)"
    Write-Host "Components verified: $($assembled.value.components_verified)"
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
