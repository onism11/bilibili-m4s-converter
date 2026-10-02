<div align="center">
  <img src="assets/app-icon.png" width="128" alt="B站 M4S 转换器图标">
  <h1>B站 M4S 转换器</h1>
  <p><strong>把零散的 M4S，变成随处可播的 MP3 / MP4。</strong></p>
  <p>一个轻量、源代码公开、无需安装的 Windows 图形工具。</p>

  [![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-1677FF?style=flat-square&logo=windows)](https://github.com/onism11/bilibili-m4s-converter/releases/latest)
  [![GitHub Release](https://img.shields.io/github/v/release/onism11/bilibili-m4s-converter?style=flat-square&color=1677FF)](https://github.com/onism11/bilibili-m4s-converter/releases/latest)
  [![FFmpeg](https://img.shields.io/badge/Powered%20by-FFmpeg-007808?style=flat-square&logo=ffmpeg)](https://ffmpeg.org/)

  [下载最新版](https://github.com/onism11/bilibili-m4s-converter/releases/latest) · [推荐搭配 Video Roll](https://videoroll.app/)
</div>

![B站 M4S 转 MP3 / MP4 的 Windows 图形界面](assets/converter-window.png)

## 为什么需要它？

从 B 站或其他网页保存的视频，有时会得到分离的 `.m4s` 视频流和音频流：视频没有声音，音频也无法直接放进常用播放器。

本工具把麻烦的 FFmpeg 命令封装成简单的 Windows 图形界面：选文件、选格式、点击转换，就完成了。

## 功能

<img width="443" height="286" alt="image" src="https://github.com/user-attachments/assets/13a90ef9-1a49-40df-8d62-404f079eedbb" />

- 🎵 音频 `.m4s` 一键转换为 `.mp3`
- 🎬 视频 `.m4s` 快速封装为 `.mp4`
- 🔊 合并独立的视频 `.m4s` 与音频 `.m4s`
- ⚡ 视频流直接封装，不重复编码、不损失画质
- 🛡️ 源文件只读处理，不会被修改
- 🧩 自动兼容部分 B 站缓存文件的 9 字节 `000000000` 前缀
- 🖥️ 原生 Windows 图形界面，也支持 PowerShell 命令行

## 推荐搭配 Video Roll

[Video Roll](https://videoroll.app/) 是一款面向 HTML5 网页视频的浏览器扩展，支持 Bilibili 等网站，并提供视频下载、倍速、画中画、截图、旋转、音量增强等功能。

推荐工作流：

1. 使用 Video Roll 在浏览器中发现并下载你有权保存的视频。
2. 如果下载结果已经是普通 MP4，直接播放即可。
3. 如果得到 `.m4s` 文件或分离的音视频流，使用本工具转换为 MP3 或合并为 MP4。

> 请仅下载和处理你拥有使用权的内容，并遵守网站条款与当地法律。

## 快速开始

### 1. 安装 FFmpeg

本工具需要 [FFmpeg](https://ffmpeg.org/)。安装后，在 PowerShell 中执行以下命令应能看到版本信息：

```powershell
ffmpeg -version
```

### 2. 下载并运行

1. 直接下载 [`M4S-Converter-Windows-v1.0.1.exe`](https://github.com/onism11/bilibili-m4s-converter/releases/latest/download/M4S-Converter-Windows-v1.0.1.exe)。
2. 双击 EXE，选文件后点击“开始转换”。

v1.0.1 起，EXE 已内嵌转换脚本与图标，不再需要把 `.ps1` 和 `assets` 放在旁边。需要命令行脚本或完整源码时，可下载 Release 中的 ZIP。

### 转 MP3

1. 输出格式选择 `MP3`。
2. 在“音频 m4s”一栏选择文件，不需要视频文件。
3. 选择码率和输出位置，点击“开始转换”。

### 转 MP4

1. 在“视频 m4s”一栏选择视频文件。
2. 如果视频没有声音，在“配套音频（可选）”中选择对应的音频 `.m4s`。
3. 输出格式选择 `MP4`，点击“开始转换”。

## 命令行

音频转 MP3：

```powershell
.\m4s-converter.ps1 -InputPath .\audio.m4s -Format mp3 -OutputPath .\audio.mp3
```

合并视频和音频：

```powershell
.\m4s-converter.ps1 -InputPath .\video.m4s -AudioPath .\audio.m4s -Format mp4 -OutputPath .\video.mp4
```

覆盖已有文件时加 `-Overwrite`。MP3 码率可通过 `-AudioBitrate 128`、`192`、`256` 或 `320` 指定。

当前源码先在输出目录生成临时成品，转换成功后才提交到目标路径；失败时保留已有成品，并拒绝把输入文件或配套音频当作输出。同名、不同目录的带前缀音视频也可分别处理。这些安全修复尚未包含在已发布的 v1.0.1 EXE 中，需要从源码重新构建。

## 常见问题：m4s 文件怎么打开？

### m4s 怎么转换成 MP3？

打开本工具，输出格式选 `MP3`，只在“音频 m4s”一栏选择文件即可，不需要添加视频文件。这也适用于搜索 **m4s to mp3** 的场景。

### B站缓存视频怎么转换成 MP4？

在“视频 m4s”中选择视频分片；如果画面和声音是两个文件，再选择配套音频，输出格式选 `MP4`。这就是常见的 **m4s to mp4**、**B站视频怎么存成mp4** 的处理方式。

### 如何下载B站缓存视频？

本工具负责转换本地 `.m4s` 文件，不负责抓取网页内容。可先用 [Video Roll](https://videoroll.app/) 下载你有权保存的内容；若结果是 M4S 或分离音视频，再交给本工具合并或转换。

### How to convert M4S to MP3 or MP4?

Use this Windows video converter to turn an audio M4S file into MP3, remux a video M4S into MP4, or merge separate Bilibili video and audio M4S streams into one MP4 file. FFmpeg is required.

## 从源码构建

重新编译 EXE 入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-launcher.ps1
```

生成单文件 EXE、Release ZIP 与 SHA-256 校验文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-release.ps1
```

运行冒烟测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-test.ps1
```

测试会在系统临时目录生成约 1 秒的音视频，检查合并、转码、同名带前缀文件、覆盖与失败保留、源文件保护，完成后自动清理。

## 说明

- Windows 10 / 11
- PowerShell 5.1 或更高版本
- FFmpeg 需要可通过系统 `PATH` 访问
- 本项目与 Bilibili、Video Roll、FFmpeg 均无隶属或官方合作关系
