[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$projectDirectory = Split-Path -Parent $PSScriptRoot
$converterPath = Join-Path $projectDirectory 'm4s-converter.ps1'
$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("bilibili-m4s-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null

function Invoke-TestCommand {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    $commandOutput = & $Executable @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage`r`n$($commandOutput -join [Environment]::NewLine)"
    }
}

function Add-PrefixedCopy {
    param([string]$SourcePath, [string]$DestinationPath)

    $prefixBytes = [System.Text.Encoding]::ASCII.GetBytes('000000000')
    $sourceBytes = [System.IO.File]::ReadAllBytes($SourcePath)
    $combinedBytes = New-Object byte[] ($prefixBytes.Length + $sourceBytes.Length)
    [System.Array]::Copy($prefixBytes, 0, $combinedBytes, 0, $prefixBytes.Length)
    [System.Array]::Copy($sourceBytes, 0, $combinedBytes, $prefixBytes.Length, $sourceBytes.Length)
    [System.IO.File]::WriteAllBytes($DestinationPath, $combinedBytes)
}

function Assert-ConversionFails {
    param([hashtable]$Parameters, [string]$ExpectedMessage)

    $failure = $null
    try {
        & $converterPath @Parameters | Out-Null
    }
    catch {
        $failure = $_
    }

    if ($null -eq $failure -or $failure.Exception.Message -notlike "*$ExpectedMessage*") {
        throw "转换应失败并报告：$ExpectedMessage；实际结果：$failure"
    }
}

function Assert-FileUnchanged {
    param([string]$Path, [string]$ExpectedHash)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw "文件被删除或修改：$Path"
    }
}

try {
    $videoM4s = Join-Path $testDirectory 'video.m4s'
    $audioM4s = Join-Path $testDirectory 'audio.m4s'
    $prefixedAudioM4s = Join-Path $testDirectory 'audio-prefixed.m4s'
    $outputMp4 = Join-Path $testDirectory 'merged.mp4'
    $outputMp3 = Join-Path $testDirectory 'audio.mp3'

    Invoke-TestCommand -Executable $ffmpeg -FailureMessage '无法生成测试视频。' -Arguments @(
        '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'testsrc=size=320x180:rate=24',
        '-t', '1', '-an', '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
        '-movflags', 'frag_keyframe+empty_moov', '-f', 'mp4', $videoM4s
    )
    Invoke-TestCommand -Executable $ffmpeg -FailureMessage '无法生成测试音频。' -Arguments @(
        '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000',
        '-t', '1', '-c:a', 'aac',
        '-movflags', 'frag_keyframe+empty_moov', '-f', 'mp4', $audioM4s
    )

    Add-PrefixedCopy -SourcePath $audioM4s -DestinationPath $prefixedAudioM4s

    # 先放入旧成品，确保成功转换后确实可以覆盖，而不只测试新建输出。
    [System.IO.File]::WriteAllText($outputMp4, 'previous output')
    & $converterPath -InputPath $videoM4s -AudioPath $audioM4s -Format mp4 -OutputPath $outputMp4 -Overwrite
    if ($LASTEXITCODE -ne 0) {
        throw 'MP4 合并命令返回失败。'
    }

    & $converterPath -InputPath $prefixedAudioM4s -Format mp3 -OutputPath $outputMp3 -Overwrite
    if ($LASTEXITCODE -ne 0) {
        throw 'MP3 转换命令返回失败。'
    }

    Invoke-TestCommand -Executable $ffmpeg -FailureMessage 'MP4 视频流校验失败。' -Arguments @(
        '-hide_banner', '-loglevel', 'error', '-i', $outputMp4,
        '-map', '0:v:0', '-frames:v', '1', '-f', 'null', 'NUL'
    )
    Invoke-TestCommand -Executable $ffmpeg -FailureMessage 'MP4 音频流校验失败。' -Arguments @(
        '-hide_banner', '-loglevel', 'error', '-i', $outputMp4,
        '-map', '0:a:0', '-frames:a', '1', '-f', 'null', 'NUL'
    )
    Invoke-TestCommand -Executable $ffmpeg -FailureMessage 'MP3 音频流校验失败。' -Arguments @(
        '-hide_banner', '-loglevel', 'error', '-i', $outputMp3,
        '-map', '0:a:0', '-frames:a', '1', '-f', 'null', 'NUL'
    )

    $outputHash = (Get-FileHash -LiteralPath $outputMp4 -Algorithm SHA256).Hash
    Assert-ConversionFails -ExpectedMessage '输出文件已存在' -Parameters @{
        InputPath = $videoM4s; AudioPath = $audioM4s; Format = 'mp4'; OutputPath = $outputMp4
    }
    Assert-FileUnchanged -Path $outputMp4 -ExpectedHash $outputHash
    Assert-ConversionFails -ExpectedMessage 'FFmpeg 转换失败' -Parameters @{
        InputPath = $audioM4s; Format = 'mp4'; OutputPath = $outputMp4; Overwrite = $true
    }
    Assert-FileUnchanged -Path $outputMp4 -ExpectedHash $outputHash

    $failedOutput = Join-Path $testDirectory 'failed.mp4'
    Assert-ConversionFails -ExpectedMessage 'FFmpeg 转换失败' -Parameters @{
        InputPath = $audioM4s; Format = 'mp4'; OutputPath = $failedOutput
    }
    if (Test-Path -LiteralPath $failedOutput) {
        throw '转换失败后留下了不完整的目标文件。'
    }

    $inputHash = (Get-FileHash -LiteralPath $outputMp3 -Algorithm SHA256).Hash
    Assert-ConversionFails -ExpectedMessage '输出文件不能与输入文件或配套音频文件相同' -Parameters @{
        InputPath = $outputMp3; Format = 'mp3'; OutputPath = $outputMp3; Overwrite = $true
    }
    Assert-FileUnchanged -Path $outputMp3 -ExpectedHash $inputHash

    $audioMp4 = Join-Path $testDirectory 'audio-input.mp4'
    Copy-Item -LiteralPath $audioM4s -Destination $audioMp4
    $audioHash = (Get-FileHash -LiteralPath $audioMp4 -Algorithm SHA256).Hash
    Assert-ConversionFails -ExpectedMessage '输出文件不能与输入文件或配套音频文件相同' -Parameters @{
        InputPath = $videoM4s; AudioPath = $audioMp4; Format = 'mp4'; OutputPath = $audioMp4; Overwrite = $true
    }
    Assert-FileUnchanged -Path $audioMp4 -ExpectedHash $audioHash

    # 不同目录下的同名带前缀文件不能共享归一化副本；同时覆盖中文和空格路径。
    $videoDirectory = Join-Path $testDirectory '同名 视频'
    $audioDirectory = Join-Path $testDirectory '同名 音频'
    New-Item -ItemType Directory -Path $videoDirectory, $audioDirectory | Out-Null
    $sameNameVideo = Join-Path $videoDirectory 'stream.m4s'
    $sameNameAudio = Join-Path $audioDirectory 'stream.m4s'
    $sameNameOutput = Join-Path $testDirectory '同名 合并.mp4'
    Add-PrefixedCopy -SourcePath $videoM4s -DestinationPath $sameNameVideo
    Add-PrefixedCopy -SourcePath $audioM4s -DestinationPath $sameNameAudio
    $videoHash = (Get-FileHash -LiteralPath $sameNameVideo -Algorithm SHA256).Hash
    $audioHash = (Get-FileHash -LiteralPath $sameNameAudio -Algorithm SHA256).Hash

    & $converterPath -InputPath $sameNameVideo -AudioPath $sameNameAudio -Format mp4 -OutputPath $sameNameOutput
    Invoke-TestCommand -Executable $ffmpeg -FailureMessage '同名文件合并后的音视频流校验失败。' -Arguments @(
        '-hide_banner', '-loglevel', 'error', '-i', $sameNameOutput,
        '-map', '0:v:0', '-map', '0:a:0', '-t', '0.1', '-f', 'null', 'NUL'
    )
    Assert-FileUnchanged -Path $sameNameVideo -ExpectedHash $videoHash
    Assert-FileUnchanged -Path $sameNameAudio -ExpectedHash $audioHash

    if (@(Get-ChildItem -LiteralPath $testDirectory -Directory -Filter 'bilibili-m4s-converter-*').Count -ne 0) {
        throw '转换结束后没有清理临时目录。'
    }

    Write-Host '冒烟测试通过：MP4/MP3、前缀与同名文件兼容、成功覆盖、失败保留和源文件保护均正常。' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testDirectory -PathType Container) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}
