//
//  FetcherView.swift
//  Endfield-Gacha
//
//  URL 粘贴 → 拉取 → 进度日志。关闭时把结果 JSON 路径回传给 ContentView 触发分析。
//
//  设计:
//    - 粘贴 URL + 点"开始" → 后台跑 C++ fetchAllPools
//    - 用户可看到实时进度日志(逐条记录);按"完成"关闭弹窗并启动分析
//    - 失败时显示错误信息,按"关闭"返回不触发分析
//

#if os(macOS)

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FetcherView: View {
    @Environment(\.dismiss) private var dismiss
    let onFinish: (String?) -> Void

    @State private var urlInput: String = ""
    @State private var droppedFilePath: String? = nil
    @State private var isHoveringDropZone: Bool = false

    @State private var log: [String] = []
    @State private var isRunning: Bool = false
    @State private var finishedPath: String? = nil
    @State private var errorMessage: String? = nil

    // 临时文件路径(用户取消保存时需要清理)
    @State private var pendingTempPath: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("拉取抽卡数据")
                .font(.title2.bold())

            Text("粘贴游戏内抽卡记录链接(含 token 参数)，工具会自动抓取并生成 JSON。")
                .font(.callout)
                .foregroundStyle(.secondary)

            // 拖拽 / 点击 文件更新区
            //
            // 两种交互方式都能选基底文件:
            //   1) 拖拽: 整个弹窗(VStack)都接收拖拽,见外层 .onDrop,
            //      但视觉高亮(虚线变色 / 背景变色)仍只在这块卡片显示,
            //      因为它是用户预期的"目标区"
            //   2) 点击: 整个区域包成 Button,弹 NSOpenPanel 选文件,
            //      为不熟悉拖拽的用户提供 fallback
            //
            // 清除按钮 (X) 用 overlay 叠在右侧,而不是放在 Button label 内部。
            // 因为 SwiftUI Button 会吞掉 label 内部的点击事件,内嵌按钮无法独立响应。
            ZStack(alignment: .trailing) {
                Button {
                    openBaseFilePanel()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(droppedFilePath == nil ? Color.secondary : Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("用于更新的基底文件 (可选):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(droppedFilePath != nil
                                 ? URL(fileURLWithPath: droppedFilePath!).lastPathComponent
                                 : "拖入或点击此处选择已有的 UIGF JSON 文件,留空则创建全新文件。")
                                .font(.system(size: 12))
                                .foregroundStyle(droppedFilePath != nil ? .primary : .tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        // 占位,给 overlay 的 X 按钮留出空间;
                        // 占位宽度需与 X 图标视觉宽度一致(约 20pt)
                        if droppedFilePath != nil {
                            Color.clear.frame(width: 20, height: 20)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                // X 按钮: 独立于 Button label, 在 ZStack 顶层接收点击
                if droppedFilePath != nil {
                    Button {
                        droppedFilePath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                }
            }
            .padding(12)
            .background(isHoveringDropZone ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHoveringDropZone ? Color.accentColor : Color(nsColor: .separatorColor),
                            style: StrokeStyle(lineWidth: isHoveringDropZone ? 2 : 1,
                                               dash: droppedFilePath == nil ? [6] : []))
            )

            // URL 输入与开始按钮
            HStack {
                TextField(
                    "https://ef-webview.gryphline.com/api/record/...&token=...&server_id=...",
                    text: $urlInput
                )
                .textFieldStyle(.roundedBorder)
                .disabled(isRunning)
                .onSubmit { if !isRunning { startFetch() } }

                Button {
                    startFetch()
                } label: {
                    if isRunning {
                        ProgressView().controlSize(.small).padding(.horizontal, 8)
                    } else {
                        Text("开始")
                            .frame(minWidth: 48)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // 日志区
            ScrollViewReader { sp in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(lineColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 260, maxHeight: 420)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .onChange(of: log.count) { _, newCount in
                    if newCount > 0 {
                        withAnimation(.easeOut(duration: 0.1)) {
                            sp.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            // 底部按钮行
            HStack {
                Spacer()
                if finishedPath != nil {
                    Button("取消此次") {
                        cleanupPendingTemp()
                        onFinish(nil)
                        dismiss()
                    }
                    Button("完成并分析") {
                        onFinish(finishedPath)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                } else {
                    Button("关闭") {
                        cleanupPendingTemp()
                        onFinish(nil)
                        dismiss()
                    }
                    .disabled(isRunning)
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 720)
        // 整个弹窗都接收 UIGF JSON 拖入。
        // 视觉高亮(虚线变色)仍由基底文件卡片自己呈现 (isTargeted: $isHoveringDropZone),
        // 这样用户拖到任意位置都能成功投递,但仍能从卡片状态判断"已识别"。
        .onDrop(of: [.fileURL], isTargeted: $isHoveringDropZone) { providers in
            guard !isRunning, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let path = url?.path,
                      path.lowercased().hasSuffix(".json") else { return }
                DispatchQueue.main.async {
                    self.droppedFilePath = path
                }
            }
            return true
        }
    }

    /// 弹系统文件选择器选基底 JSON 文件。
    /// 与拖拽是等效的两条入口,都最终写到 droppedFilePath。
    private func openBaseFilePanel() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择已有的 UIGF JSON 文件"
        panel.prompt = "选择"
        // 用 begin(completionHandler:) 而非模态 runModal(),
        // 避免阻塞当前 sheet 的渲染
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.droppedFilePath = url.path
            }
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("[错误]") || line.contains("[警告]") || line.contains("失败") { return .red }
        if line.hasPrefix(">>>") || line.contains("完成") || line.contains("已保存") { return .accentColor }
        if line.hasPrefix("  获取到") { return .primary.opacity(0.75) }
        return .primary
    }

    /// 清理临时拉取文件(用户取消保存或最终取消时调用)
    private func cleanupPendingTemp() {
        guard let path = pendingTempPath else { return }
        pendingTempPath = nil
        // 后台清理,避免阻塞 UI
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func startFetch() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isRunning = true
        errorMessage = nil
        log.removeAll()
        finishedPath = nil
        cleanupPendingTemp()  // 清理上一次未确认的临时文件

        let existFile = droppedFilePath ?? ""
        if !existFile.isEmpty {
            log.append("尝试读取基底文件...")
        }

        FetcherBridge.fetchAll(
            url: trimmed,
            existingFile: existFile,
            progress: { msg in
                // ObjC 已经 dispatch 到主线程,使用 assumeIsolated 静态消除警告。
                // assumeIsolated 是同步检查 API: debug 下断言"当前确实在 MainActor",
                // release 下零开销,完美匹配 ObjC 端 dispatch_async(main_queue) 的现实。
                MainActor.assumeIsolated {
                    self.log.append(msg)
                }
            },
            completion: { ok, newCount, total, tempOutputPath, errMsg in
                // ObjC 已经 dispatch 到主线程,assumeIsolated 包裹整个 completion 体
                MainActor.assumeIsolated {
                    if !ok {
                        self.isRunning = false
                        self.errorMessage = errMsg.isEmpty ? "拉取失败(未知错误)" : errMsg
                        return
                    }

                    // 暂存:用户没确认前,这个临时文件需要在取消时清理
                    self.pendingTempPath = tempOutputPath

                    // 拉取成功,弹保存对话框
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [UTType.json]
                    panel.nameFieldStringValue = "uigf_endfield.json"
                    panel.message = "选择保存 UIGF 文件的位置"

                    if let dropped = self.droppedFilePath {
                        let url = URL(fileURLWithPath: dropped)
                        panel.directoryURL = url.deletingLastPathComponent()
                        panel.nameFieldStringValue = url.lastPathComponent
                    }

                    panel.begin { response in
                        // panel.begin 的 completion 本来就在主线程触发
                        if response == .OK, let destURL = panel.url {
                            // 把同步 IO 移到后台,避免主线程卡死
                            DispatchQueue.global(qos: .userInitiated).async {
                                var moveError: String? = nil
                                do {
                                    if FileManager.default.fileExists(atPath: destURL.path) {
                                        try FileManager.default.removeItem(at: destURL)
                                    }
                                    try FileManager.default.moveItem(atPath: tempOutputPath,
                                                                     toPath: destURL.path)
                                } catch {
                                    moveError = "保存文件失败: \(error.localizedDescription)"
                                }
                                // IO 完成后回 UI,使用一致的 GCD 风格 (DispatchQueue.main)
                                DispatchQueue.main.async {
                                    self.isRunning = false
                                    if let me = moveError {
                                        self.errorMessage = me
                                        // 失败时,临时文件可能还在/可能已被删,无论如何尝试清理
                                        self.cleanupPendingTemp()
                                    } else {
                                        self.pendingTempPath = nil  // 已 move,无需清理
                                        self.log.append("")
                                        self.log.append("====================")
                                        self.log.append("完成! 本次新增 \(newCount) 条, 文件内共计 \(total) 条")
                                        self.log.append("已保存至: \(destURL.path)")
                                        self.finishedPath = destURL.path
                                    }
                                }
                            }
                        } else {
                            // 用户在保存面板中按了取消,已经在主线程
                            self.isRunning = false
                            self.cleanupPendingTemp()
                            self.log.append("")
                            self.log.append("用户取消了保存对话框,本次拉取的数据已被废弃。")
                            self.finishedPath = nil
                        }
                    }
                }
            }
        )
    }
}

#endif
