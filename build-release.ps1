[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$projectDirectory = $PSScriptRoot
$distributionDirectory = Join-Path $projectDirectory 'dist'
$archiveName = "M4S-Converter-Windows-v$Version.zip"
$archivePath = Join-Path $distributionDirectory $archiveName
$checksumPath = "$archivePath.sha256"
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$stagingDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $temporaryRoot ("m4s-converter-release-" + [Guid]::NewGuid().ToString('N')))
)

if (-not $stagingDirectory.StartsWith($temporaryRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "临时打包目录不安全：$stagingDirectory"
}

& (Join-Path $projectDirectory 'build-launcher.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'EXE 编译失败，停止打包。'
}

New-Item -ItemType Directory -Path $distributionDirectory -Force | Out-Null
if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
    Remove-Item -LiteralPath $archivePath -Force
}
if (Test-Path -LiteralPath $checksumPath -PathType Leaf) {
    Remove-Item -LiteralPath $checksumPath -Force
}

try {
    New-Item -ItemType Directory -Path (Join-Path $stagingDirectory 'assets') -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $projectDirectory 'M4S-Converter.exe') -Destination $stagingDirectory
    Copy-Item -LiteralPath (Join-Path $projectDirectory 'm4s-converter.ps1') -Destination $stagingDirectory
    Copy-Item -LiteralPath (Join-Path $projectDirectory '启动转换器.cmd') -Destination $stagingDirectory
    Copy-Item -LiteralPath (Join-Path $projectDirectory 'README.md') -Destination $stagingDirectory
    Copy-Item -LiteralPath (Join-Path $projectDirectory 'assets\app-icon.ico') -Destination (Join-Path $stagingDirectory 'assets')

    Compress-Archive -Path (Join-Path $stagingDirectory '*') -DestinationPath $archivePath -CompressionLevel Optimal

    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumLine = "$hash  $archiveName`r`n"
    [System.IO.File]::WriteAllText($checksumPath, $checksumLine, (New-Object System.Text.UTF8Encoding($false)))
}
finally {
    if (Test-Path -LiteralPath $stagingDirectory -PathType Container) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
    }
}

Write-Host "已生成：$archivePath" -ForegroundColor Green
Write-Host "校验文件：$checksumPath" -ForegroundColor Green
