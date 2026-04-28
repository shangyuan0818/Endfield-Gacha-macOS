# Endfield-Gacha-macOS 终末地抽卡工具(macOS)

Gacha tracker and visualizer for Arknights: Endfield on macOS. Built with SwiftUI &amp; C++20.

《明日方舟：终末地》寻访(抽卡)数据保存，分析与可视化。使用 SwiftUI 与 C++20 构建，提供 macOS 原生高效体验。



## Download / 下载
**App Store Link / 链接**: [Link will be added here / 链接稍后更新]


## How to use / 如何使用
1. **Export Data / 导出数据**:
   
   Click the fetch icon in the toolbar. Drag the old UIGF file into the drop zone as the baseline (optional), input your gacha link, and click start to fetch the incremental updates. Then save or discard the new UIGF file.

   点击工具栏的拉取数据按钮。拖入旧UIGF文件作为基底（可选的），输入抽卡链接并点击开始来获取增量更新。接着选择保存或者放弃新的UIGF文件。

2. **Analyze Data / 分析数据**: 

   Drag the UIGF file into the window.
   
   拖拽UIGF文件到窗口。



## Compatibility / 兼容性
- **OS / 系统**: macOS 14.0 or higher (Sonoma+). macOS 14.0或更高。
- **Architecture / 架构**: Universal Binary (Native support for both **Intel (x86_64)** and **Apple Silicon (arm64)**). 通用二进制。
- **64-bit Only / 纯64位**: Some features of SwiftUI require at least macOS 14.0. In addition, macOS has dropped support for 32-bit (i386) applications since version 10.15. This tool is 64-bit only. 部分 SwiftUI 功能最低要求 macOS 14.0。此外，由于 macOS 10.15 后不再支持 32 位应用，本工具仅支持 64 位架构。

> - **Windows**: Please check the Windows Win32 version here 请查看该Win32版本: [Endfield-Gacha](https://github.com/shangyuan0818/Endfield-Gacha)



## Privacy Policy / 隐私政策

For details regarding data handling and usage, please refer to our [Privacy Policy](privacy-policy.md).

关于数据处理与使用的详细说明，请参阅我们的[隐私政策](privacy-policy.md)。



## Source Code (old) 源代码（旧版）

The current codebase is undergoing rapid iteration and major refactoring. Old source code is in the folder `old`.

目前代码库正在经历快速迭代与重构。旧版源代码位于文件夹`old`中

### Warning: Old source code contians known bugs and incorrect calculation logic.
### 警告：旧版源代码有已知故障和错误的计算逻辑。
