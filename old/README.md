# Endfield-Gacha-macOS 终末地抽卡工具(macOS)
Gacha tracker and visualizer for Arknights: Endfield on macOS. Built with SwiftUI &amp; C++20.

《明日方舟：终末地》寻访(抽卡)数据保存，分析与可视化。使用 SwiftUI 与 C++20 构建，提供 macOS 原生高效体验。



# How to use 如何使用
1. **Export Data / 导出数据**: 
   Run the `export` binary file and input your gacha link.  
   运行 `export` 二进制文件并输入你的抽卡链接。
   
   The `uigf_endfield.json` file will be generated in the **same directory** as the exporter.  
   数据将保存在 `export` 文件同目录下的 `uigf_endfield.json` 中。

2. **Analyze / 分析数据**: 
   Launch `Endfield-Gacha-GUI.app` and drag the `uigf_endfield.json` file into the window.  
   运行 `Endfield-Gacha-GUI.app` 图形程序，并将 `uigf_endfield.json` 拖拽到窗口中。


# How to compile 如何编译
Download and install Xcode in App Store.

在App Store下载并安装Xcode。

https://developer.apple.com/xcode/

### GUI (Main App)
Open `Endfield-Gacha-GUI.xcodeproj` in Xcode.  
通过 Xcode 打开 `Endfield-Gacha-GUI.xcodeproj`。

- For local testing: Press `Cmd + R` to run.
- For distribution: Go to `Product -> Archive`. In the Organizer, right-click the archive -> `Show in Finder`. Right-click the `.xcarchive` file -> `Show Package Contents`. You will find the `.app` file under `Products/Applications`.
- 导出发布版：点击菜单栏 `Product -> Archive`。在弹出的窗口中右键选择 `Show in Finder`。对 `.xcarchive` 文件点右键“显示包内容”，在 `Products/Applications` 路径下即可找到 `.app` 程序。

### Exporter (CLI Tool)
For Exporter only, Navigate to the `Exporter` folder. The compile command is provided in the first few lines of `main_mac.mm`.  
进入 `Exporter` 文件夹。在 `main_mac.mm` 的文件开头即可找到编译命令，将其复制到终端运行即可。


# Compatibility / 兼容性
- **OS**: macOS 12.0 or higher (Monterey+).
- **Architecture**: Universal Binary (Native support for both **Intel (x86_64)** and **Apple Silicon (arm64)**). 通用二进制。
- **Note**: macOS has dropped support for 32-bit (i386) applications since version 10.15. This tool is 64-bit only.
- **原因**: 部分 SwiftUI 功能最低要求 macOS 12.0。此外，由于 macOS 10.15 后不再支持 32 位应用，本工具仅支持 64 位架构。


# Demostrate 效果展示
<img width="1012" height="917" alt="截屏2026-04-03 上午12 09 54" src="https://github.com/user-attachments/assets/9a7aa919-5da6-4c30-a0a4-d8e222210121" />

