# 发布帖文案（v1.0.1）

## V2EX / 少数派标题

做了一个给普通用户用的 B站 M4S → MP3 / MP4 Windows 小工具

## 正文

有时从网页或 B 站缓存拿到的是 `.m4s`：视频和音频分成两个文件，普通播放器打不开，想提取音频还得自己写 FFmpeg 命令。

我做了一个轻量的 Windows 图形工具，把这几件事变成“选文件 → 点开始转换”：

- 音频 M4S 直接转 MP3，不需要添加视频文件
- 视频 M4S 封装成 MP4
- 分离的视频 / 音频 M4S 合并成一个 MP4
- 兼容部分 B 站缓存文件的 9 字节前缀
- 视频流直接封装，不重复编码、不损失画质

v1.0.1 已改成单文件 EXE，下载后可以直接打开，不用 clone，也不用把 PowerShell 脚本放在旁边；电脑仍需安装 FFmpeg。

项目与截图：<https://github.com/onism11/bilibili-m4s-converter>

直接下载：<https://github.com/onism11/bilibili-m4s-converter/releases/latest/download/M4S-Converter-Windows-v1.0.1.exe>

如果平时用浏览器保存视频，可以搭配 Video Roll：先下载自己有权保存的内容，遇到 M4S 或分离音视频时再用这个工具处理。<https://videoroll.app/>

项目源码公开。欢迎反馈打不开的样本、界面问题或转换失败日志。

> 请仅下载和处理你拥有使用权的内容，并遵守网站条款与当地法律。

## B站动态短版

做了一个 Windows 小工具：B站 / 网页视频下载后如果拿到 `.m4s`，可以一键转 MP3、封装 MP4，或合并分离的音视频。v1.0.1 是单文件 EXE，不用 clone；需提前安装 FFmpeg。推荐搭配 Video Roll 使用。项目与下载：<https://github.com/onism11/bilibili-m4s-converter>
