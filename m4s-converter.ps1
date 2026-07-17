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

    [switch]$Gui
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
        $headerLength = [Math]::Min(64, [int]$stream.Length)
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

        $normalizedPath = Join-Path $TemporaryDirectory ([System.IO.Path]::GetFileName($SourcePath))
        if ([System.StringComparer]::OrdinalIgnoreCase.Equals($normalizedPath, $SourcePath)) {
            $normalizedPath = Join-Path $TemporaryDirectory ("normalized-" + [System.IO.Path]::GetFileName($SourcePath))
        }

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
    if (Test-Path -LiteralPath $destinationFile) {
        if (-not $Force) {
            throw "输出文件已存在：$destinationFile。使用 -Overwrite 可覆盖。"
        }
    }

    $destinationDirectory = Split-Path -Parent $destinationFile
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("bilibili-m4s-converter-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

    try {
        $normalizedSource = Get-NormalizedMediaPath -SourcePath $sourceFile -TemporaryDirectory $temporaryDirectory
        $normalizedAudio = $null
        if ($audioFile) {
            $normalizedAudio = Get-NormalizedMediaPath -SourcePath $audioFile -TemporaryDirectory $temporaryDirectory
        }

        $overwriteArgument = if ($Force) { '-y' } else { '-n' }

        if ($OutputFormat -eq 'mp3') {
            $arguments = @(
                '-hide_banner', $overwriteArgument,
                '-i', $normalizedSource,
                '-map', '0:a:0', '-vn',
                '-c:a', 'libmp3lame', '-b:a', "${Bitrate}k",
                $destinationFile
            )
            Invoke-Ffmpeg -FfmpegPath $ffmpegPath -Arguments $arguments
        }
        else {
            if ($normalizedAudio) {
                $arguments = @(
                    '-hide_banner', $overwriteArgument,
                    '-fflags', '+genpts', '-i', $normalizedSource,
                    '-fflags', '+genpts', '-i', $normalizedAudio,
                    '-map', '0:v:0', '-map', '1:a:0',
                    '-c:v', 'copy', '-c:a', 'aac', '-b:a', "${Bitrate}k",
                    '-shortest', '-movflags', '+faststart',
                    $destinationFile
                )
            }
            else {
                $arguments = @(
                    '-hide_banner', $overwriteArgument,
                    '-fflags', '+genpts', '-i', $normalizedSource,
                    '-map', '0:v:0', '-map', '0:a:0?',
                    '-c:v', 'copy', '-c:a', 'aac', '-b:a', "${Bitrate}k",
                    '-movflags', '+faststart',
                    $destinationFile
                )
            }

            Invoke-Ffmpeg -FfmpegPath $ffmpegPath -Arguments $arguments
        }

        return $destinationFile
    }
    catch {
        if (Test-Path -LiteralPath $destinationFile -PathType Leaf) {
            Remove-Item -LiteralPath $destinationFile -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory -PathType Container) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Show-ConverterWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $backgroundColor = [System.Drawing.ColorTranslator]::FromHtml('#F5F7FA')
    $surfaceColor = [System.Drawing.ColorTranslator]::FromHtml('#FFFFFF')
    $primaryColor = [System.Drawing.ColorTranslator]::FromHtml('#1677FF')
    $primaryHoverColor = [System.Drawing.ColorTranslator]::FromHtml('#0F60D5')
    $primarySoftColor = [System.Drawing.ColorTranslator]::FromHtml('#EAF3FF')
    $textColor = [System.Drawing.ColorTranslator]::FromHtml('#1F2329')
    $mutedColor = [System.Drawing.ColorTranslator]::FromHtml('#646A73')
    $borderColor = [System.Drawing.ColorTranslator]::FromHtml('#DDE2E9')
    $disabledColor = [System.Drawing.ColorTranslator]::FromHtml('#A8ADB5')

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'B站 M4S 转换器'
    $form.ClientSize = New-Object System.Drawing.Size(760, 700)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $form.MaximizeBox = $false
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $form.BackColor = $backgroundColor

    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Location = New-Object System.Drawing.Point(0, 0)
    $headerPanel.Size = New-Object System.Drawing.Size(760, 86)
    $headerPanel.BackColor = $surfaceColor
    $form.Controls.Add($headerPanel)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'B站 M4S 转换器'
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 18, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $textColor
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(28, 15)
    $headerPanel.Controls.Add($title)

    $description = New-Object System.Windows.Forms.Label
    $description.Text = '本地转换 · MP3 音频提取 · MP4 音视频合并 · 不修改源文件'
    $description.AutoSize = $true
    $description.ForeColor = $mutedColor
    $description.Location = New-Object System.Drawing.Point(31, 54)
    $headerPanel.Controls.Add($description)

    $formatLabel = New-Object System.Windows.Forms.Label
    $formatLabel.Text = '输出格式'
    $formatLabel.AutoSize = $true
    $formatLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $formatLabel.ForeColor = $textColor
    $formatLabel.Location = New-Object System.Drawing.Point(28, 109)
    $form.Controls.Add($formatLabel)

    $formatMp4Button = New-Object System.Windows.Forms.RadioButton
    $formatMp4Button.Appearance = [System.Windows.Forms.Appearance]::Button
    $formatMp4Button.Text = 'MP4'
    $formatMp4Button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $formatMp4Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $formatMp4Button.Location = New-Object System.Drawing.Point(120, 99)
    $formatMp4Button.Size = New-Object System.Drawing.Size(112, 36)
    $formatMp4Button.Checked = $true
    $formatMp4Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($formatMp4Button)

    $formatMp3Button = New-Object System.Windows.Forms.RadioButton
    $formatMp3Button.Appearance = [System.Windows.Forms.Appearance]::Button
    $formatMp3Button.Text = 'MP3'
    $formatMp3Button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $formatMp3Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $formatMp3Button.Location = New-Object System.Drawing.Point(231, 99)
    $formatMp3Button.Size = New-Object System.Drawing.Size(112, 36)
    $formatMp3Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($formatMp3Button)

    function Add-FileCard {
        param(
            [string]$TitleText,
            [string]$SubtitleText,
            [string]$IconText,
            [int]$Top,
            [System.Drawing.Color]$AccentColor
        )

        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(28, $Top)
        $card.Size = New-Object System.Drawing.Size(704, 108)
        $card.BackColor = $surfaceColor
        $card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $form.Controls.Add($card)

        $iconPanel = New-Object System.Windows.Forms.Panel
        $iconPanel.Location = New-Object System.Drawing.Point(16, 15)
        $iconPanel.Size = New-Object System.Drawing.Size(42, 42)
        $iconPanel.BackColor = $primarySoftColor
        $card.Controls.Add($iconPanel)

        $iconLabel = New-Object System.Windows.Forms.Label
        $iconLabel.Text = $IconText
        $iconLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
        $iconLabel.ForeColor = $AccentColor
        $iconLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $iconLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
        $iconPanel.Controls.Add($iconLabel)

        $cardTitle = New-Object System.Windows.Forms.Label
        $cardTitle.Text = $TitleText
        $cardTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
        $cardTitle.ForeColor = $textColor
        $cardTitle.AutoSize = $true
        $cardTitle.Location = New-Object System.Drawing.Point(70, 13)
        $card.Controls.Add($cardTitle)

        $subtitle = New-Object System.Windows.Forms.Label
        $subtitle.Text = $SubtitleText
        $subtitle.ForeColor = $mutedColor
        $subtitle.AutoSize = $true
        $subtitle.Location = New-Object System.Drawing.Point(70, 39)
        $card.Controls.Add($subtitle)

        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Location = New-Object System.Drawing.Point(70, 68)
        $textBox.Size = New-Object System.Drawing.Size(518, 27)
        $textBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $card.Controls.Add($textBox)

        $button = New-Object System.Windows.Forms.Button
        $button.Text = '选择文件'
        $button.Location = New-Object System.Drawing.Point(598, 65)
        $button.Size = New-Object System.Drawing.Size(86, 31)
        $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $button.FlatAppearance.BorderColor = $primaryColor
        $button.BackColor = $surfaceColor
        $button.ForeColor = $primaryColor
        $button.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.Controls.Add($button)

        return @($card, $cardTitle, $subtitle, $textBox, $button, $iconPanel, $iconLabel)
    }

    $videoCard = Add-FileCard -TitleText '视频 m4s' -SubtitleText '选择 B 站视频分片（仅 MP4 使用）' -IconText '▶' -Top 148 -AccentColor $primaryColor
    $videoPanel = $videoCard[0]
    $inputLabel = $videoCard[1]
    $videoSubtitle = $videoCard[2]
    $inputTextBox = $videoCard[3]
    $inputButton = $videoCard[4]
    $videoIconPanel = $videoCard[5]
    $videoIconLabel = $videoCard[6]

    $audioCard = Add-FileCard -TitleText '音频 m4s' -SubtitleText '可选：与视频合并；转 MP3 时只需选择此文件' -IconText '♫' -Top 268 -AccentColor $primaryColor
    $audioPanel = $audioCard[0]
    $audioLabel = $audioCard[1]
    $audioSubtitle = $audioCard[2]
    $audioTextBox = $audioCard[3]
    $audioButton = $audioCard[4]

    $settingsPanel = New-Object System.Windows.Forms.Panel
    $settingsPanel.Location = New-Object System.Drawing.Point(28, 388)
    $settingsPanel.Size = New-Object System.Drawing.Size(704, 116)
    $settingsPanel.BackColor = $surfaceColor
    $settingsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $form.Controls.Add($settingsPanel)

    $settingsTitle = New-Object System.Windows.Forms.Label
    $settingsTitle.Text = '输出设置'
    $settingsTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $settingsTitle.ForeColor = $textColor
    $settingsTitle.AutoSize = $true
    $settingsTitle.Location = New-Object System.Drawing.Point(16, 12)
    $settingsPanel.Controls.Add($settingsTitle)

    $outputLabel = New-Object System.Windows.Forms.Label
    $outputLabel.Text = '输出文件'
    $outputLabel.AutoSize = $true
    $outputLabel.ForeColor = $textColor
    $outputLabel.Location = New-Object System.Drawing.Point(16, 48)
    $settingsPanel.Controls.Add($outputLabel)

    $outputTextBox = New-Object System.Windows.Forms.TextBox
    $outputTextBox.Location = New-Object System.Drawing.Point(92, 42)
    $outputTextBox.Size = New-Object System.Drawing.Size(496, 27)
    $outputTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $settingsPanel.Controls.Add($outputTextBox)

    $outputButton = New-Object System.Windows.Forms.Button
    $outputButton.Text = '另存为'
    $outputButton.Location = New-Object System.Drawing.Point(598, 39)
    $outputButton.Size = New-Object System.Drawing.Size(86, 31)
    $outputButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $outputButton.FlatAppearance.BorderColor = $borderColor
    $outputButton.BackColor = $surfaceColor
    $outputButton.ForeColor = $textColor
    $outputButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $settingsPanel.Controls.Add($outputButton)

    $bitrateLabel = New-Object System.Windows.Forms.Label
    $bitrateLabel.Text = '音频码率'
    $bitrateLabel.AutoSize = $true
    $bitrateLabel.ForeColor = $textColor
    $bitrateLabel.Location = New-Object System.Drawing.Point(16, 85)
    $settingsPanel.Controls.Add($bitrateLabel)

    $bitrateComboBox = New-Object System.Windows.Forms.ComboBox
    $bitrateComboBox.DropDownStyle = 'DropDownList'
    $bitrateComboBox.Items.AddRange(@('128 kbps', '192 kbps', '256 kbps', '320 kbps'))
    $bitrateComboBox.SelectedIndex = 1
    $bitrateComboBox.Location = New-Object System.Drawing.Point(92, 78)
    $bitrateComboBox.Size = New-Object System.Drawing.Size(140, 28)
    $settingsPanel.Controls.Add($bitrateComboBox)

    $statusTitle = New-Object System.Windows.Forms.Label
    $statusTitle.Text = '转换状态'
    $statusTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $statusTitle.ForeColor = $textColor
    $statusTitle.AutoSize = $true
    $statusTitle.Location = New-Object System.Drawing.Point(28, 522)
    $form.Controls.Add($statusTitle)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(28, 548)
    $progressBar.Size = New-Object System.Drawing.Size(704, 12)
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $progressBar.Value = 0
    $form.Controls.Add($progressBar)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = '就绪，等待选择文件'
    $statusLabel.AutoEllipsis = $true
    $statusLabel.Location = New-Object System.Drawing.Point(28, 569)
    $statusLabel.Size = New-Object System.Drawing.Size(704, 22)
    $statusLabel.ForeColor = $mutedColor
    $form.Controls.Add($statusLabel)

    $convertButton = New-Object System.Windows.Forms.Button
    $convertButton.Text = '开始转换'
    $convertButton.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
    $convertButton.Location = New-Object System.Drawing.Point(28, 606)
    $convertButton.Size = New-Object System.Drawing.Size(704, 50)
    $convertButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $convertButton.FlatAppearance.BorderSize = 0
    $convertButton.FlatAppearance.MouseOverBackColor = $primaryHoverColor
    $convertButton.BackColor = $primaryColor
    $convertButton.ForeColor = [System.Drawing.Color]::White
    $convertButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($convertButton)

    $helpLabel = New-Object System.Windows.Forms.Label
    $helpLabel.Text = '提示：转 MP3 只需音频文件；转 MP4 可选择视频并搭配音频文件。'
    $helpLabel.AutoSize = $true
    $helpLabel.ForeColor = $mutedColor
    $helpLabel.Location = New-Object System.Drawing.Point(29, 672)
    $form.Controls.Add($helpLabel)

    $autoOutputPath = $true

    $getSelectedFormat = {
        if ($formatMp3Button.Checked) { return 'mp3' }
        return 'mp4'
    }

    $updateOutputPath = {
        $selectedFormat = & $getSelectedFormat
        $activeInputPath = if ($selectedFormat -eq 'mp3') { $audioTextBox.Text } else { $inputTextBox.Text }
        if ($autoOutputPath -and -not [string]::IsNullOrWhiteSpace($activeInputPath)) {
            $extension = '.' + $selectedFormat
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

    $applyFormatStyle = {
        $isMp4 = $formatMp4Button.Checked
        if (-not $isMp4 -and
            [string]::IsNullOrWhiteSpace($audioTextBox.Text) -and
            -not [string]::IsNullOrWhiteSpace($inputTextBox.Text)) {
            # 兼容旧界面：若用户已在第一栏选择音频，再切换到 MP3，自动移到音频栏。
            $audioTextBox.Text = $inputTextBox.Text
            $inputTextBox.Clear()
        }

        $formatMp4Button.BackColor = if ($isMp4) { $primaryColor } else { $surfaceColor }
        $formatMp4Button.ForeColor = if ($isMp4) { [System.Drawing.Color]::White } else { $textColor }
        $formatMp4Button.FlatAppearance.BorderColor = if ($isMp4) { $primaryColor } else { $borderColor }
        $formatMp3Button.BackColor = if ($isMp4) { $surfaceColor } else { $primaryColor }
        $formatMp3Button.ForeColor = if ($isMp4) { $textColor } else { [System.Drawing.Color]::White }
        $formatMp3Button.FlatAppearance.BorderColor = if ($isMp4) { $borderColor } else { $primaryColor }

        $inputTextBox.Enabled = $isMp4
        $inputButton.Enabled = $isMp4
        $videoPanel.BackColor = if ($isMp4) { $surfaceColor } else { $backgroundColor }
        $inputLabel.ForeColor = if ($isMp4) { $textColor } else { $disabledColor }
        $videoSubtitle.ForeColor = if ($isMp4) { $mutedColor } else { $disabledColor }
        $videoIconPanel.BackColor = if ($isMp4) { $primarySoftColor } else { $backgroundColor }
        $videoIconLabel.ForeColor = if ($isMp4) { $primaryColor } else { $disabledColor }
        $audioSubtitle.Text = if ($isMp4) { '可选：与视频合并；若视频已有声音可不选' } else { '选择音频文件即可转换，不需要视频文件' }
        & $updateOutputPath
    }

    $formatMp4Button.Add_CheckedChanged({
        if ($formatMp4Button.Checked) { & $applyFormatStyle }
    })
    $formatMp3Button.Add_CheckedChanged({
        if ($formatMp3Button.Checked) { & $applyFormatStyle }
    })
    & $applyFormatStyle

    $outputTextBox.Add_TextChanged({
        if ($outputTextBox.Focused) {
            $autoOutputPath = $false
        }
    })

    $outputButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $selectedFormat = & $getSelectedFormat
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
            $selectedFormat = & $getSelectedFormat
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
            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
            $progressBar.MarqueeAnimationSpeed = 25
            $statusLabel.ForeColor = $primaryColor
            $statusLabel.Text = '正在转换，请稍候……'
            $form.Refresh()

            $resultPath = Invoke-M4sConversion `
                -SourcePath $selectedSource `
                -SeparateAudioPath $selectedAudio `
                -OutputFormat $selectedFormat `
                -DestinationPath $selectedOutput `
                -Bitrate $selectedBitrate `
                -Force

            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            $progressBar.Value = 100
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
            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            $progressBar.Value = 0
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

    $form.AcceptButton = $convertButton
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

try {
    if ($Gui -or [string]::IsNullOrWhiteSpace($InputPath)) {
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
