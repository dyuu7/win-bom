[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$projectRoot = $PSScriptRoot
$wingetManifestPath = Join-Path $projectRoot 'winget.json'
$scoopManifestPath = Join-Path $projectRoot 'scoop.json'
$results = New-Object 'System.Collections.Generic.List[object]'

function Read-JsonDocument {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest not found: $Path"
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        return $content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Cannot read manifest '$Path': $($_.Exception.Message)"
    }
}

function Get-WingetManifest {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $document = Read-JsonDocument -Path $Path
    $packages = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}

    if ($null -eq $document.Sources) {
        throw "WinGet manifest has no Sources array: $Path"
    }

    foreach ($source in @($document.Sources)) {
        $sourceName = [string]$source.SourceDetails.Name
        if ([string]::IsNullOrWhiteSpace($sourceName)) {
            throw "WinGet manifest contains a source without SourceDetails.Name: $Path"
        }

        foreach ($package in @($source.Packages)) {
            $id = [string]$package.PackageIdentifier
            if ([string]::IsNullOrWhiteSpace($id)) {
                throw "WinGet manifest contains a package without PackageIdentifier: $Path"
            }

            $key = $id.ToLowerInvariant()
            if ($seen.ContainsKey($key)) {
                throw "WinGet package '$id' appears more than once in $Path"
            }

            $seen[$key] = $true
            $packages.Add([pscustomobject]@{
                Id = $id
                Source = $sourceName
            })
        }
    }

    return $packages.ToArray()
}

function Get-ScoopManifest {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $document = Read-JsonDocument -Path $Path
    $buckets = @{}
    $apps = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}

    foreach ($bucket in @($document.buckets)) {
        $name = [string]$bucket.Name
        $source = [string]$bucket.Source

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($source)) {
            throw "Every Scoop bucket must have Name and Source: $Path"
        }
        if ($buckets.ContainsKey($name)) {
            throw "Scoop bucket '$name' appears more than once in $Path"
        }

        $buckets[$name] = $source
    }

    foreach ($app in @($document.apps)) {
        $name = [string]$app.Name
        $bucket = [string]$app.Source

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($bucket)) {
            throw "Every Scoop app must have Name and Source: $Path"
        }
        if (-not $buckets.ContainsKey($bucket)) {
            throw "Scoop app '$name' refers to an undeclared bucket '$bucket': $Path"
        }

        $key = "$bucket/$name".ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            throw "Scoop app '$bucket/$name' appears more than once in $Path"
        }

        $seen[$key] = $true
        $apps.Add([pscustomobject]@{
            Name = $name
            Bucket = $bucket
        })
    }

    return [pscustomobject]@{
        Buckets = $buckets
        Apps = $apps.ToArray()
    }
}

function Resolve-WingetCommand {
    $command = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $command) {
        throw 'WinGet is unavailable. Install or repair App Installer, then retry.'
    }

    & $command.Source --version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'WinGet is present but cannot run. Install or repair App Installer, then retry.'
    }

    return $command.Source
}

function Find-ScoopCommand {
    $command = Get-Command scoop -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($env:SCOOP)) {
        $candidates.Add((Join-Path $env:SCOOP 'shims\scoop.cmd'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates.Add((Join-Path $env:USERPROFILE 'scoop\shims\scoop.cmd'))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Ensure-ScoopCommand {
    $command = Find-ScoopCommand
    if ($null -ne $command) {
        return $command
    }

    Write-Host '[Scoop] Not installed; running the official user-level installer.'
    $installer = [string](Invoke-RestMethod -Uri 'https://get.scoop.sh')
    Invoke-Expression $installer

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath) -join [IO.Path]::PathSeparator

    $command = Find-ScoopCommand
    if ($null -eq $command) {
        throw 'Scoop installation completed without creating a usable command. Open a new terminal and retry.'
    }

    return $command
}

function Get-ScoopBucketTable {
    param(
        [Parameter(Mandatory)]
        [string] $ScoopCommand
    )

    $json = & $ScoopCommand export | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Scoop could not export its current bucket state (exit code $LASTEXITCODE)."
    }

    try {
        $state = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Scoop returned an invalid export: $($_.Exception.Message)"
    }

    $table = @{}
    foreach ($bucket in @($state.buckets)) {
        $table[[string]$bucket.Name] = [string]$bucket.Source
    }
    return $table
}

function ConvertTo-ComparableGitUrl {
    param(
        [Parameter(Mandatory)]
        [string] $Url
    )

    $value = $Url.Trim().TrimEnd('/')
    if ($value.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }
    return $value
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [Parameter(Mandatory)]
        [string] $Description
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed (exit code $LASTEXITCODE)."
    }
}

function Add-Result {
    param(
        [Parameter(Mandatory)]
        [string] $Manager,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'Failed')]
        [string] $Status,

        [string] $Detail = ''
    )

    $results.Add([pscustomobject]@{
        Manager = $Manager
        Name = $Name
        Status = $Status
        Detail = $Detail
    })
}

$wingetPackages = @(Get-WingetManifest -Path $wingetManifestPath)
$scoopManifest = Get-ScoopManifest -Path $scoopManifestPath
$scoopApps = @($scoopManifest.Apps)

Write-Host "Manifest validated: $($wingetPackages.Count) WinGet packages, $($scoopApps.Count) Scoop apps."

$wingetCommand = Resolve-WingetCommand
$scoopCommand = Ensure-ScoopCommand

$currentBuckets = Get-ScoopBucketTable -ScoopCommand $scoopCommand
foreach ($name in $scoopManifest.Buckets.Keys) {
    if ($currentBuckets.ContainsKey($name)) {
        $actual = ConvertTo-ComparableGitUrl -Url $currentBuckets[$name]
        $expected = ConvertTo-ComparableGitUrl -Url $scoopManifest.Buckets[$name]
        if ($actual -ne $expected) {
            throw "Scoop bucket '$name' points to '$($currentBuckets[$name])', expected '$($scoopManifest.Buckets[$name])'."
        }
    }
}

foreach ($package in $wingetPackages) {
    Write-Host "[WinGet] $($package.Id)"
    try {
        Invoke-ExternalCommand `
            -FilePath $wingetCommand `
            -ArgumentList @(
                'install',
                '--id', $package.Id,
                '--exact',
                '--source', $package.Source,
                '--silent',
                '--no-upgrade',
                '--accept-package-agreements',
                '--accept-source-agreements',
                '--disable-interactivity'
            ) `
            -Description "WinGet package '$($package.Id)'"

        Add-Result -Manager 'WinGet' -Name $package.Id -Status 'Succeeded'
        Write-Host "  [OK] $($package.Id)"
    }
    catch {
        Add-Result -Manager 'WinGet' -Name $package.Id -Status 'Failed' -Detail $_.Exception.Message
        Write-Warning "  [FAILED] $($package.Id): $($_.Exception.Message)"
    }
}

foreach ($name in $scoopManifest.Buckets.Keys) {
    if ($currentBuckets.ContainsKey($name)) {
        continue
    }

    Write-Host "[Scoop] Adding bucket '$name'"
    try {
        Invoke-ExternalCommand `
            -FilePath $scoopCommand `
            -ArgumentList @('bucket', 'add', $name, $scoopManifest.Buckets[$name]) `
            -Description "Scoop bucket '$name'"

        $currentBuckets[$name] = $scoopManifest.Buckets[$name]
    }
    catch {
        Write-Warning "  [FAILED] bucket '$name': $($_.Exception.Message)"
    }
}

foreach ($app in $scoopApps) {
    $packageName = "$($app.Bucket)/$($app.Name)"
    Write-Host "[Scoop] $packageName"

    if (-not $currentBuckets.ContainsKey($app.Bucket)) {
        $detail = "Bucket '$($app.Bucket)' is unavailable."
        Add-Result -Manager 'Scoop' -Name $packageName -Status 'Failed' -Detail $detail
        Write-Warning "  [FAILED] $packageName`: $detail"
        continue
    }

    try {
        Invoke-ExternalCommand `
            -FilePath $scoopCommand `
            -ArgumentList @('install', $packageName) `
            -Description "Scoop app '$packageName'"

        Add-Result -Manager 'Scoop' -Name $packageName -Status 'Succeeded'
        Write-Host "  [OK] $packageName"
    }
    catch {
        Add-Result -Manager 'Scoop' -Name $packageName -Status 'Failed' -Detail $_.Exception.Message
        Write-Warning "  [FAILED] $packageName`: $($_.Exception.Message)"
    }
}

$failed = @($results | Where-Object { $_.Status -eq 'Failed' })
$succeeded = @($results | Where-Object { $_.Status -eq 'Succeeded' })

Write-Host ''
Write-Host "Summary: $($succeeded.Count) succeeded (including already satisfied), $($failed.Count) failed."

if ($failed.Count -gt 0) {
    Write-Host 'Failed items:'
    foreach ($item in $failed) {
        Write-Host "  - [$($item.Manager)] $($item.Name): $($item.Detail)"
    }
    exit 1
}
