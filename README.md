# B站 M4S 转换器

一个面向 Windows 的本地转换工具：

- 把音频 `.m4s` 转成 `.mp3`
- 把视频 `.m4s` 封装成 `.mp4`
- 把 B 站分离的视频 `.m4s` 和音频 `.m4s` 合并成有声音的 `.mp4`
- 自动兼容部分 B 站缓存文件开头的 9 字节 `000000000` 前缀，并且不会修改源文件

## 使用前准备

需要安装 [FFmpeg](https://ffmpeg.org/)，并确保在 PowerShell 中执行下面的命令能看到版本信息：

```powershell
ffmpeg -version
```

## 图形界面

双击 `启动转换器.cmd`。

### 转 MP3

1. “输入 m4s”选择音频文件。
2. 输出格式选择 `MP3`。
3. 选择码率和输出位置，点击“开始转换”。

### 转 MP4

1. “输入 m4s”选择视频文件。
2. 如果这个视频文件没有声音，在“配套音频”中选择同一视频的音频 `.m4s`。
3. 输出格式选择 `MP4`，点击“开始转换”。

视频流会直接封装进 MP4，不重新编码，因此速度快且不会损失画质；音频会编码为兼容性较好的 AAC。

## 命令行

音频转 MP3：

```powershell
.\m4s-converter.ps1 -InputPath .\audio.m4s -Format mp3 -OutputPath .\audio.mp3
```

合并视频和音频：

```powershell
.\m4s-converter.ps1 -InputPath .\video.m4s -AudioPath .\audio.m4s -Format mp4 -OutputPath .\video.mp4
```

覆盖已有输出文件时加 `-Overwrite`。MP3 码率可以用 `-AudioBitrate 128`、`192`、`256` 或 `320` 指定。

如果 PowerShell 阻止脚本运行，可以使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\m4s-converter.ps1 -Gui
```

## 验证

运行冒烟测试（会在系统临时目录生成约 1 秒的测试音视频，测试结束后自动删除）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-test.ps1
```
