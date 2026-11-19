#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Entity', 'Items', 'Objects')]
    [string]$Category
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function ConvertTo-ResourcePath {
    param([string]$FilePath)

    $absolutePath = [System.IO.Path]::GetFullPath($FilePath)
    $projectPrefix = $projectRoot + [System.IO.Path]::DirectorySeparatorChar

    if (-not $absolutePath.StartsWith(
        $projectPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Scene is outside the project: $absolutePath"
    }

    return 'res://' + $absolutePath.Substring($projectPrefix.Length).Replace('\', '/')
}


function Select-SceneFile {
    param(
        [string]$Directory,
        [string]$Heading
    )

    $files = @(
        Get-ChildItem -LiteralPath $Directory -Filter '*.tscn' -File -Recurse |
            Sort-Object -Property FullName
    )

    if ($files.Count -eq 0) {
        throw "No scene files were found in: $Directory"
    }

    Write-Host ''
    Write-Host $Heading

    for ($index = 0; $index -lt $files.Count; $index++) {
        $resourcePath = ConvertTo-ResourcePath -FilePath $files[$index].FullName
        Write-Host ('{0}. {1}' -f ($index + 1), $resourcePath)
    }

    while ($true) {
        $choiceText = Read-Host 'Select a scene number'
        $choice = 0

        if (
            [int]::TryParse($choiceText, [ref]$choice) -and
            $choice -ge 1 -and $choice -le $files.Count
        ) {
            return $files[$choice - 1].FullName
        }

        Write-Warning 'Choose one of the listed numbers.'
    }
}


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

$presentationRoot = Join-Path $projectRoot (
    'Framework\Content\Presentation\' + $Category
)
$presentationFile = Select-SceneFile -Directory $presentationRoot -Heading (
    'Available {0} presentations:' -f $Category
)

$gamesRoot = Join-Path $projectRoot 'Games'
$mapFile = Select-SceneFile -Directory $gamesRoot -Heading 'Available map scenes:'

while ($true) {
    $entityKey = (Read-Host 'Placement key').Trim()

    if ($entityKey -cmatch '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$') {
        break
    }

    Write-Warning 'Use lower_snake_case, starting with a letter.'
}

$presentationPath = ConvertTo-ResourcePath -FilePath $presentationFile
$mapPath = ConvertTo-ResourcePath -FilePath $mapFile

$jobRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot ('.append-' + [guid]::NewGuid().ToString('N')))
)
$logPath = Join-Path $jobRoot 'godot.log'
$draftScene = Join-Path $jobRoot 'map.tscn'

try {
    [void][System.IO.Directory]::CreateDirectory($jobRoot)

    $originalHash = (Get-FileHash -LiteralPath $mapFile -Algorithm SHA256).Hash

    $appended = Invoke-EntityAuthoring -OperationArgs @(
        'append',
        $presentationPath,
        $mapPath,
        $entityKey,
        $draftScene
    )

    if (
        -not $appended.value.existing_nodes_verified -or
        -not $appended.value.instance_verified -or
        -not $appended.value.uid_verified
    ) {
        throw 'The draft did not pass its scene verification.'
    }

    $currentHash = (Get-FileHash -LiteralPath $mapFile -Algorithm SHA256).Hash
    if ($currentHash -ne $originalHash) {
        throw 'The destination map changed during processing. Run the appender again.'
    }

    [System.IO.File]::Replace(
        $draftScene,
        $mapFile,
        [System.Management.Automation.Language.NullString]::Value
    )

    Write-Host ''
    Write-Host "Appended entity: $($appended.value.definition_id)"
    Write-Host "Placement key: $entityKey"
    Write-Host "Node name: $($appended.value.node_name)"
    Write-Host "Scene: $mapPath"
    Write-Host "Existing nodes verified: $($appended.value.existing_nodes_verified)"
    Write-Host "Scene instance verified: $($appended.value.instance_verified)"
    Write-Host "Map UID verified: $($appended.value.uid_verified)"
    Write-Host "Map UID: $($appended.value.uid)"
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