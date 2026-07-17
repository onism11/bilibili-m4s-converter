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

    $prefixBytes = [System.Text.Encoding]::ASCII.GetBytes('000000000')
    $sourceBytes = [System.IO.File]::ReadAllBytes($audioM4s)
    $combinedBytes = New-Object byte[] ($prefixBytes.Length + $sourceBytes.Length)
    [System.Array]::Copy($prefixBytes, 0, $combinedBytes, 0, $prefixBytes.Length)
    [System.Array]::Copy($sourceBytes, 0, $combinedBytes, $prefixBytes.Length, $sourceBytes.Length)
    [System.IO.File]::WriteAllBytes($prefixedAudioM4s, $combinedBytes)

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

    Write-Host '冒烟测试通过：MP4 音视频合并、MP3 转换、B站 9 字节前缀兼容均正常。' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testDirectory -PathType Container) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}
