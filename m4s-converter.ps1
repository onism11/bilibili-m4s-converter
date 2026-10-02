[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InputPath,

    [string]$AudioPath,

    [ValidateSet('mp3', 'mp4')]
    [string]$Format,

    [string]$OutputPath,

    [ValidateRange(64, 320)]
    [int]$AudioBitrate = 192,

    [switch]$Overwrite,

    [switch]$Gui,

    [string]$CaptureGuiPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Find-MediaTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "未找到 $Name。请先安装 FFmpeg，并把 ffmpeg.exe 加入 PATH。"
    }

    return $command.Source
}

function Resolve-InputFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label 不存在：$Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-OutputFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputFormat,

        [string]$RequestedPath
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        return [System.IO.Path]::ChangeExtension($InputFile, ".$OutputFormat")
    }

    $fullPath = [System.IO.Path]::GetFullPath($RequestedPath)
    $extension = [System.IO.Path]::GetExtension($fullPath)
    if ([string]::IsNullOrWhiteSpace($extension)) {
        $fullPath += ".$OutputFormat"
    }
    elseif ($extension -ne ".$OutputFormat") {
        throw "输出文件扩展名必须是 .$OutputFormat：$fullPath"
    }

    return $fullPath
}

function Get-NormalizedMediaPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TemporaryDirectory
    )

    # 部分 B 站缓存会在正常 MP4/M4S 文件头前加 9 个 ASCII 字符“0”。
    # 不修改源文件；检测到这种前缀时，只在临时目录中生成去前缀副本。
    $stream = [System.IO.File]::OpenRead($SourcePath)
    try {
        $headerLength = [int][Math]::Min([long]64, $stream.Length)
        $header = New-Object byte[] $headerLength
        $readLength = $stream.Read($header, 0, $headerLength)

        $ftypIndex = -1
        for ($index = 0; $index -le $readLength - 4; $index++) {
            if ($header[$index] -eq 0x66 -and
                $header[$index + 1] -eq 0x74 -and
                $header[$index + 2] -eq 0x79 -and
                $header[$index + 3] -eq 0x70) {
                $ftypIndex = $index
                break
            }
        }

        $prefixLength = $ftypIndex - 4
        $hasAsciiZeroPrefix = $prefixLength -gt 0 -and $prefixLength -le 32
        if ($hasAsciiZeroPrefix) {
            for ($index = 0; $index -lt $prefixLength; $index++) {
                if ($header[$index] -ne 0x30) {
                    $hasAsciiZeroPrefix = $false
                    break
                }
            }
        }

        if (-not $hasAsciiZeroPrefix) {
            return $SourcePath
        }

        # 音视频可能来自不同目录、却使用相同文件名；每份副本必须有独立路径。
        $normalizedPath = Join-Path $TemporaryDirectory (
            [Guid]::NewGuid().ToString('N') + '-' + [System.IO.Path]::GetFileName($SourcePath)
        )

        $stream.Position = $prefixLength
        $outputStream = [System.IO.File]::Create($normalizedPath)
        try {
            $stream.CopyTo($outputStream)
        }
        finally {
            $outputStream.Dispose()
        }

        return $normalizedPath
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-Ffmpeg {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FfmpegPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Verbose ("ffmpeg " + ($Arguments -join ' '))
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 会把原生程序的标准错误流包装成 ErrorRecord；
        # FFmpeg 恰好把正常进度也写在该流，因此只在调用期间按退出码判断。
        $ErrorActionPreference = 'Continue'
        $ffmpegOutput = & $FfmpegPath @Arguments 2>&1
        $ffmpegExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($ffmpegExitCode -ne 0) {
        $details = $ffmpegOutput -join [Environment]::NewLine
        throw "FFmpeg 转换失败。`r`n$details"
    }
}

function Invoke-M4sConversion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [string]$SeparateAudioPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('mp3', 'mp4')]
        [string]$OutputFormat,

        [string]$DestinationPath,

        [ValidateRange(64, 320)]
        [int]$Bitrate = 192,

        [switch]$Force
    )

    $ffmpegPath = Find-MediaTool -Name 'ffmpeg'
    $sourceFile = Resolve-InputFile -Path $SourcePath -Label '输入文件'

    if ($OutputFormat -eq 'mp3' -and -not [string]::IsNullOrWhiteSpace($SeparateAudioPath)) {
        throw '输出 MP3 时不需要填写配套音频文件。'
    }

    $audioFile = $null
    if (-not [string]::IsNullOrWhiteSpace($SeparateAudioPath)) {
        $audioFile = Resolve-InputFile -Path $SeparateAudioPath -Label '配套音频文件'
    }

    $destinationFile = Get-OutputFilePath -InputFile $sourceFile -OutputFormat $OutputFormat -RequestedPath $DestinationPath
    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($destinationFile, $sourceFile) -or
        ($audioFile -and [System.StringComparer]::OrdinalIgnoreCase.Equals($destinationFile, $audioFile))) {
        throw '输出文件不能与输入文件或配套音频文件相同。请选择其他输出位置。'
    }

    if (Test-Path -LiteralPath $destinationFile) {
        if (-not $Force) {
            throw "输出文件已存在：$destinationFile。使用 -Overwrite 可覆盖。"
        }
    }

    $destinationDirectory = Split-Path -Parent $destinationFile
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    # 临时输出与目标位于同一磁盘；成功后才移动或替换，失败时保留已有成品。
    $temporaryDirectory = Join-Path $destinationDirectory ("bilibili-m4s-converter-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

    try {
        $stagedOutput = Join-Path $temporaryDirectory ("converted.$OutputFormat")
        $normalizedSource = Get-NormalizedMediaPath -SourcePath $sourceFile -TemporaryDirectory $temporaryDirectory
        $normalizedAudio = $null
        if ($audioFile) {
            $normalizedAudio = Get-NormalizedMediaPath -SourcePath $audioFile -TemporaryDirectory $temporaryDirectory
        }

        if ($OutputFormat -eq 'mp3') {
            $arguments = @(
                '-hide_banner', '-n',
                '-i', $normalizedSource,
                '-map', '0:a:0', '-vn',
                '-c:a', 'libmp3lame', '-b:a', "${Bitrate}k",
                $stagedOutput
            )
            Invoke-Ffmpeg -FfmpegPath $ffmpegPath -Arguments $arguments
        }
        else {
            if ($normalizedAudio) {
                $arguments = @(
                    '-hide_banner', '-n',
                    '-fflags', '+genpts', '-i', $normalizedSource,
                    '-fflags', '+genpts', '-i', $normalizedAudio,
                    '-map', '0:v:0', '-map', '1:a:0',
                    '-c:v', 'copy', '-c:a', 'aac', '-b:a', "${Bitrate}k",
                    '-shortest', '-movflags', '+faststart',
                    $stagedOutput
                )
            }
            else {
                $arguments = @(
                    '-hide_banner', '-n',
                    '-fflags', '+genpts', '-i', $normalizedSource,
                    '-map', '0:v:0', '-map', '0:a:0?',
                    '-c:v', 'copy', '-c:a', 'aac', '-b:a', "${Bitrate}k",
                    '-movflags', '+faststart',
                    $stagedOutput
                )
            }

            Invoke-Ffmpeg -FfmpegPath $ffmpegPath -Arguments $arguments
        }

        if ($Force -and (Test-Path -LiteralPath $destinationFile -PathType Leaf)) {
            [System.IO.File]::Replace($stagedOutput, $destinationFile, $null)
        }
        else {
            # Move 不覆盖竞态中新出现的文件；未授权覆盖时仍保留它。
            [System.IO.File]::Move($stagedOutput, $destinationFile)
        }

        return $destinationFile
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory -PathType Container) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Show-ConverterWindow {
    param(
        [string]$CapturePath
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'B站 M4S 转换器'
    $form.ClientSize = New-Object System.Drawing.Size(720, 430)
    $form.MinimumSize = New-Object System.Drawing.Size(736, 469)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $iconPath = Join-Path $PSScriptRoot 'assets\app-icon.ico'
    if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
        $form.Icon = New-Object System.Drawing.Icon($iconPath)
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'B站 M4S 转换器'
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 17, [System.Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(24, 20)
    $form.Controls.Add($title)

    $description = New-Object System.Windows.Forms.Label
    $description.Text = '音频 m4s 可转 MP3；视频 m4s 可单独转 MP4，也可与配套音频 m4s 合并。'
    $description.AutoSize = $true
    $description.ForeColor = [System.Drawing.Color]::DimGray
    $description.Location = New-Object System.Drawing.Point(28, 58)
    $form.Controls.Add($description)

    function Add-FileRow {
        param(
            [string]$LabelText,
            [int]$Top,
            [string]$ButtonText
        )

        $label = New-Object System.Windows.Forms.Label
        $label.Text = $LabelText
        $label.AutoSize = $true
        $label.Location = New-Object System.Drawing.Point(28, ($Top + 7))
        $form.Controls.Add($label)

        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Location = New-Object System.Drawing.Point(142, $Top)
        $textBox.Size = New-Object System.Drawing.Size(462, 28)
        $textBox.Anchor = 'Top, Left, Right'
        $form.Controls.Add($textBox)

        $button = New-Object System.Windows.Forms.Button
        $button.Text = $ButtonText
        $button.Location = New-Object System.Drawing.Point(616, ($Top - 1))
        $button.Size = New-Object System.Drawing.Size(76, 30)
        $button.Anchor = 'Top, Right'
        $form.Controls.Add($button)

        return @($label, $textBox, $button)
    }

    $inputRow = Add-FileRow -LabelText '视频 m4s（MP4）' -Top 92 -ButtonText '浏览...'
    $inputLabel = $inputRow[0]
    $inputTextBox = $inputRow[1]
    $inputButton = $inputRow[2]

    $audioRow = Add-FileRow -LabelText '配套音频（可选）' -Top 136 -ButtonText '浏览...'
    $audioLabel = $audioRow[0]
    $audioTextBox = $audioRow[1]
    $audioButton = $audioRow[2]

    $formatLabel = New-Object System.Windows.Forms.Label
    $formatLabel.Text = '输出格式'
    $formatLabel.AutoSize = $true
    $formatLabel.Location = New-Object System.Drawing.Point(28, 188)
    $form.Controls.Add($formatLabel)

    $formatComboBox = New-Object System.Windows.Forms.ComboBox
    $formatComboBox.DropDownStyle = 'DropDownList'
    $formatComboBox.Items.AddRange(@('MP4', 'MP3'))
    $formatComboBox.SelectedIndex = 0
    $formatComboBox.Location = New-Object System.Drawing.Point(142, 181)
    $formatComboBox.Size = New-Object System.Drawing.Size(112, 28)
    $form.Controls.Add($formatComboBox)

    $bitrateLabel = New-Object System.Windows.Forms.Label
    $bitrateLabel.Text = '音频码率'
    $bitrateLabel.AutoSize = $true
    $bitrateLabel.Location = New-Object System.Drawing.Point(288, 188)
    $form.Controls.Add($bitrateLabel)

    $bitrateComboBox = New-Object System.Windows.Forms.ComboBox
    $bitrateComboBox.DropDownStyle = 'DropDownList'
    $bitrateComboBox.Items.AddRange(@('128 kbps', '192 kbps', '256 kbps', '320 kbps'))
    $bitrateComboBox.SelectedIndex = 1
    $bitrateComboBox.Location = New-Object System.Drawing.Point(358, 181)
    $bitrateComboBox.Size = New-Object System.Drawing.Size(118, 28)
    $form.Controls.Add($bitrateComboBox)

    $outputRow = Add-FileRow -LabelText '输出文件' -Top 226 -ButtonText '另存为...'
    $outputTextBox = $outputRow[1]
    $outputButton = $outputRow[2]

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = '就绪'
    $statusLabel.AutoEllipsis = $true
    $statusLabel.Location = New-Object System.Drawing.Point(28, 280)
    $statusLabel.Size = New-Object System.Drawing.Size(500, 24)
    $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($statusLabel)

    $convertButton = New-Object System.Windows.Forms.Button
    $convertButton.Text = '开始转换'
    $convertButton.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $convertButton.Location = New-Object System.Drawing.Point(548, 270)
    $convertButton.Size = New-Object System.Drawing.Size(144, 42)
    $convertButton.Anchor = 'Top, Right'
    $form.Controls.Add($convertButton)

    $helpBox = New-Object System.Windows.Forms.GroupBox
    $helpBox.Text = '怎么选文件？'
    $helpBox.Location = New-Object System.Drawing.Point(28, 326)
    $helpBox.Size = New-Object System.Drawing.Size(664, 80)
    $helpBox.Anchor = 'Top, Bottom, Left, Right'
    $form.Controls.Add($helpBox)

    $helpLabel = New-Object System.Windows.Forms.Label
    $helpLabel.Text = "• 转 MP3：只需选择音频 m4s，不需要视频文件。`r`n• 转 MP4：选择视频 m4s；若视频没有声音，再选择同一视频的音频 m4s。"
    $helpLabel.AutoSize = $true
    $helpLabel.Location = New-Object System.Drawing.Point(14, 24)
    $helpBox.Controls.Add($helpLabel)

    $autoOutputPath = $true

    $updateOutputPath = {
        $selectedFormat = $formatComboBox.SelectedItem.ToString().ToLowerInvariant()
        $activeInputPath = if ($selectedFormat -eq 'mp3') { $audioTextBox.Text } else { $inputTextBox.Text }
        if ($autoOutputPath -and -not [string]::IsNullOrWhiteSpace($activeInputPath)) {
            $extension = '.' + $formatComboBox.SelectedItem.ToString().ToLowerInvariant()
            $outputTextBox.Text = [System.IO.Path]::ChangeExtension($activeInputPath, $extension)
        }
    }

    $chooseM4sFile = {
        param($targetTextBox)

        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = 'M4S 媒体分片 (*.m4s)|*.m4s|所有文件 (*.*)|*.*'
        $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $targetTextBox.Text = $dialog.FileName
        }
        $dialog.Dispose()
    }

    $inputButton.Add_Click({
        & $chooseM4sFile $inputTextBox
        $autoOutputPath = $true
        & $updateOutputPath
    })

    $audioButton.Add_Click({
        & $chooseM4sFile $audioTextBox
        $autoOutputPath = $true
        & $updateOutputPath
    })

    $inputTextBox.Add_TextChanged({ & $updateOutputPath })
    $audioTextBox.Add_TextChanged({ & $updateOutputPath })

    $formatComboBox.Add_SelectedIndexChanged({
        $isMp4 = $formatComboBox.SelectedItem.ToString() -eq 'MP4'
        if (-not $isMp4 -and
            [string]::IsNullOrWhiteSpace($audioTextBox.Text) -and
            -not [string]::IsNullOrWhiteSpace($inputTextBox.Text)) {
            # 兼容旧界面：若用户已在第一栏选择音频，再切换到 MP3，自动移到音频栏。
            $audioTextBox.Text = $inputTextBox.Text
            $inputTextBox.Clear()
        }

        $inputTextBox.Enabled = $isMp4
        $inputButton.Enabled = $isMp4
        $inputLabel.ForeColor = if ($isMp4) { [System.Drawing.SystemColors]::ControlText } else { [System.Drawing.Color]::Gray }
        $audioLabel.Text = if ($isMp4) { '配套音频（可选）' } else { '音频 m4s' }
        & $updateOutputPath
    })

    $outputTextBox.Add_TextChanged({
        if ($outputTextBox.Focused) {
            $autoOutputPath = $false
        }
    })

    $outputButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $selectedFormat = $formatComboBox.SelectedItem.ToString().ToLowerInvariant()
        $dialog.Filter = if ($selectedFormat -eq 'mp4') { 'MP4 视频 (*.mp4)|*.mp4' } else { 'MP3 音频 (*.mp3)|*.mp3' }
        $dialog.DefaultExt = $selectedFormat
        $dialog.AddExtension = $true
        if (-not [string]::IsNullOrWhiteSpace($outputTextBox.Text)) {
            $dialog.FileName = [System.IO.Path]::GetFileName($outputTextBox.Text)
            $dialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($outputTextBox.Text)
        }
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $autoOutputPath = $false
            $outputTextBox.Text = $dialog.FileName
        }
        $dialog.Dispose()
    })

    $convertButton.Add_Click({
        try {
            $selectedFormat = $formatComboBox.SelectedItem.ToString().ToLowerInvariant()
            if ($selectedFormat -eq 'mp3') {
                if ([string]::IsNullOrWhiteSpace($audioTextBox.Text)) {
                    throw '请选择音频 m4s 文件。转 MP3 不需要视频文件。'
                }
                $selectedSource = $audioTextBox.Text.Trim()
                $selectedAudio = ''
            }
            else {
                if ([string]::IsNullOrWhiteSpace($inputTextBox.Text)) {
                    throw '请选择视频 m4s 文件。'
                }
                $selectedSource = $inputTextBox.Text.Trim()
                $selectedAudio = $audioTextBox.Text.Trim()
            }

            $selectedOutput = $outputTextBox.Text.Trim()
            $selectedBitrate = [int]($bitrateComboBox.SelectedItem.ToString().Split(' ')[0])

            if (Test-Path -LiteralPath $selectedOutput -PathType Leaf) {
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    $form,
                    "输出文件已存在，是否覆盖？`r`n$selectedOutput",
                    '确认覆盖',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                    return
                }
            }

            $convertButton.Enabled = $false
            $form.UseWaitCursor = $true
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
            $statusLabel.Text = '正在转换，请稍候……'
            $form.Refresh()

            $resultPath = Invoke-M4sConversion `
                -SourcePath $selectedSource `
                -SeparateAudioPath $selectedAudio `
                -OutputFormat $selectedFormat `
                -DestinationPath $selectedOutput `
                -Bitrate $selectedBitrate `
                -Force

            $statusLabel.ForeColor = [System.Drawing.Color]::ForestGreen
            $statusLabel.Text = "转换完成：$resultPath"
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                "转换完成！`r`n$resultPath",
                '完成',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        catch {
            $statusLabel.ForeColor = [System.Drawing.Color]::Firebrick
            $statusLabel.Text = '转换失败'
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                $_.Exception.Message,
                '转换失败',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        finally {
            $form.UseWaitCursor = $false
            $convertButton.Enabled = $true
        }
    })

    if (-not [string]::IsNullOrWhiteSpace($CapturePath)) {
        $inputTextBox.Text = 'C:\Downloads\video.m4s'
        $audioTextBox.Text = 'C:\Downloads\audio.m4s'
        $outputTextBox.Text = 'C:\Downloads\video.mp4'
        $form.TopMost = $true
        $form.Show()
        $form.Activate()
        $convertButton.Select()
        $form.Refresh()
        Start-Sleep -Milliseconds 500

        $captureFile = [System.IO.Path]::GetFullPath($CapturePath)
        $captureDirectory = [System.IO.Path]::GetDirectoryName($captureFile)
        if (-not (Test-Path -LiteralPath $captureDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $captureDirectory -Force | Out-Null
        }

        $bitmap = New-Object System.Drawing.Bitmap($form.ClientSize.Width, $form.ClientSize.Height)
        try {
            $captureRectangle = New-Object System.Drawing.Rectangle(
                0,
                0,
                $form.ClientSize.Width,
                $form.ClientSize.Height
            )
            $form.DrawToBitmap($bitmap, $captureRectangle)
            $bitmap.Save($captureFile, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $bitmap.Dispose()
            $form.Close()
            $form.Dispose()
        }
        return
    }

    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

try {
    if (-not [string]::IsNullOrWhiteSpace($CaptureGuiPath)) {
        Show-ConverterWindow -CapturePath $CaptureGuiPath
    }
    elseif ($Gui -or [string]::IsNullOrWhiteSpace($InputPath)) {
        Show-ConverterWindow
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Format)) {
            throw '命令行模式必须使用 -Format 指定 mp3 或 mp4。'
        }

        $result = Invoke-M4sConversion `
            -SourcePath $InputPath `
            -SeparateAudioPath $AudioPath `
            -OutputFormat $Format `
            -DestinationPath $OutputPath `
            -Bitrate $AudioBitrate `
            -Force:$Overwrite

        Write-Host "转换完成：$result" -ForegroundColor Green
    }
}
catch {
    Write-Error $_.Exception.Message
    $global:LASTEXITCODE = 1
}
