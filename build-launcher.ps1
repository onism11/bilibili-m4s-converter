[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$projectDirectory = $PSScriptRoot
$sourcePath = Join-Path $projectDirectory 'launcher\Program.cs'
$outputPath = Join-Path $projectDirectory 'M4S-Converter.exe'
$iconPath = Join-Path $projectDirectory 'assets\app-icon.ico'
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    throw "找不到系统 C# 编译器：$compilerPath"
}

if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    throw "找不到 EXE 图标：$iconPath"
}

& $compilerPath `
    /nologo `
    /target:winexe `
    /optimize+ `
    /platform:anycpu `
    /reference:System.Windows.Forms.dll `
    "/win32icon:$iconPath" `
    "/out:$outputPath" `
    $sourcePath

if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw 'EXE 入口编译失败。'
}

Write-Host "已生成：$outputPath" -ForegroundColor Green
