//
//  AnalysisView_iOS.swift
//  Endfield-Gacha (iOS)
//
//  分析 Tab:
//    - 顶部:摘要卡片 (2x2 关键数字, 一眼看到结论)
//    - 中部:可折叠的"详细文本输出"
//    - 下半:4 张图
//        iPhone (compact)  -> 纵向堆叠
//        iPad/横屏 (regular) -> 2x2 网格
//    - 工具栏:导入按钮 (.fileImporter,等价 macOS 的拖拽)
//
//  数据来源:
//    1) 用户点导入,弹文件选择器
//    2) 拉取 Tab 完成后通过 pendingPath 推送过来
//
//  注意:iOS 安全作用域 URL 必须 startAccessingSecurityScopedResource()
//  才能读;这里在分析期间持有,完成后 stop。
//

#if !os(macOS)

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AnalysisView_iOS: View {
    @Environment(AppConfig.self) private var config
    @Environment(\.horizontalSizeClass) private var hSize

    /// 来自拉取 Tab 的待分析路径。消费一次后置 nil。
    @Binding var pendingPath: String?

    @State private var outputText: String = "点击右上角「导入」选择 UIGF JSON 文件,\n或在「拉取」标签页从 URL 抓取数据"
    @State private var analysis: AnalysisBundle? = nil
    @State private var isProcessing: Bool = false
    @State private var showImporter: Bool = false
    @State private var showRawText: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isProcessing {
                        ProgressView("分析中...")
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if let a = analysis {
                        // 摘要卡片 2x2
                        SummaryCardsView(charts: a)
                            .padding(.horizontal)

                        // 折叠详细统计:两个卡池卡片(角色 / 武器),
                        // iOS 上结构化排版替代原 PC 风格的等宽对齐文本。
                        DisclosureGroup(isExpanded: $showRawText) {
                            VStack(spacing: 12) {
                                PoolDetailCard(
                                    poolName: "角色卡池(特许寻访)",
                                    stats: a.statsChar,
                                    kind: .character
                                )
                                PoolDetailCard(
                                    poolName: "武器卡池(武库申领)",
                                    stats: a.statsWep,
                                    kind: .weapon
                                )
                            }
                            .padding(.top, 8)
                        } label: {
                            Label("详细统计", systemImage: "doc.text")
                                .font(.subheadline)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)

                        // 4 张图布局:
                        //   iPad (regular): 2x2 网格,每行固定 360pt
                        //                   (在 ScrollView 里必须固定高度,否则坍缩为 0)
                        //   iPhone (compact): 纵向堆叠 4 张,每张 280pt
                        let layout: ChartGridLayout =
                            (hSize == .regular) ? .grid2x2Fixed : .vertical
                        ChartGridView(statsChar: a.statsChar,
                                      statsWep: a.statsWep,
                                      layout: layout)
                            .padding(.horizontal)
                    } else {
                        // 空态
                        ContentUnavailableView {
                            Label("等待分析数据", systemImage: "chart.bar.doc.horizontal")
                        } description: {
                            Text(outputText)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                        } actions: {
                            Button {
                                showImporter = true
                            } label: {
                                Label("导入 UIGF JSON",
                                      systemImage: "tray.and.arrow.down.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 360)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("抽卡分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down.fill")
                    }
                    .disabled(isProcessing)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    runAnalysisWithSecurityScope(url: url)
                case .failure(let err):
                    outputText = "选择文件失败: \(err.localizedDescription)"
                }
            }
            // 接收来自拉取 Tab 的待分析路径
            .onChange(of: pendingPath) { _, newPath in
                guard let p = newPath else { return }
                pendingPath = nil  // 消费一次,避免重入
                let url = URL(fileURLWithPath: p)
                runAnalysisWithSecurityScope(url: url)
            }
        }
    }

    /// 包装:获取安全作用域 → 分析 → 释放
    /// iOS 沙盒外的文件(用户从"文件"App 选的)必须这样访问,否则读不到内容。
    private func runAnalysisWithSecurityScope(url: URL) {
        // 注意:不能在 defer 里 stop,因为分析是异步的。
        // 必须在异步任务完成后再 stop。
        let needsAccess = url.startAccessingSecurityScopedResource()

        isProcessing = true
        analysis = nil
        outputText = "正在分析 \(url.lastPathComponent)..."

        let path = url.path
        let chars = config.chars
        let pool  = config.pool
        let weps  = config.weps

        DispatchQueue.global(qos: .userInitiated).async {
            let bundle = AnalyzerBridge.analyze(
                filePath: path, chars: chars, poolMap: pool, weapons: weps
            )
            DispatchQueue.main.async {
                self.outputText = bundle.outputText
                self.analysis = bundle.charts
                self.isProcessing = false
                if needsAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }
}

// MARK: - 摘要卡片(2x2)
//
// 把分析结果中最关键的 4 个指标做成卡片,iPhone 上信息密度高且一眼可见。
// 选取标准:用户最关心 + 与 4 张图分别呼应。
private struct SummaryCardsView: View {
    let charts: AnalysisBundle

    var body: some View {
        // 用 Grid 而非 LazyVGrid:
        //   只有 4 张卡片, lazy 加载没有意义。LazyVGrid 在 ScrollView 中
        //   遇到快速滚动/切 Tab 时, 某些 cell 会出现"内容为空但占位还在"的渲染 bug,
        //   尤其是 cell 用了 .regularMaterial 这种需要离屏采样的复杂背景。
        //   Grid 一次性渲染全部 cell,没有卸载/加载的状态切换,从源头消除该 bug。
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                // 1. 角色总样本量 + 平均抽数(对应"角色 ECDF"图)
                StatCard(
                    title: "角色 · 总样本",
                    value: "\(charts.statsChar.count_all)",
                    subtitle: String(format: "平均 %.2f 抽 / 6★",
                                     charts.statsChar.avg_all)
                )
                // 2. 角色 50/50 不歪率(用户最关心:有没有被针对)
                StatCard(
                    title: "角色 · 不歪率",
                    value: rateString(charts.statsChar.win_rate_5050),
                    subtitle: "\(charts.statsChar.win_5050) 中 / \(charts.statsChar.win_5050 + charts.statsChar.lose_5050) 总"
                )
            }
            GridRow {
                // 3. 武器总样本(对应"武器 ECDF"图)
                StatCard(
                    title: "武器 · 总样本",
                    value: "\(charts.statsWep.count_all)",
                    subtitle: String(format: "平均 %.2f 抽 / 6★",
                                     charts.statsWep.avg_all)
                )
                // 4. KS 检验 (v0.1.1 起改用 UP):
                //    UP 涉及 50% 歪率 + 各自硬保底, 比综合六星更复杂,
                //    KS 偏离度更能反映"运气是否反常"。
                //    综合六星机制本身简单(纯 hazard 函数), 偏离度本身信息量较少。
                //    若 UP 数据为 0, 降级显示综合 6 星 KS。
                //
                //    标题与前三张卡 ("角色 · 总样本" / "角色 · 不歪率" /
                //    "武器 · 总样本") 保持 "主体 · 指标" 命名格式对齐。
                //    标题随数据源动态切换:
                //      有 UP 数据 → "角色 · UP 正态性",副标题 "UP D = 0.xxx"
                //      降级综合 → "角色 · 正态性",  副标题 "综合 D = 0.xxx"
                //    这样标题和副标题始终在描述同一种数据,不会出现
                //    "标题写 UP 但副标题写综合" 的语义错位。
                StatCard(
                    title: ksDisplayTitle(charts.statsChar),
                    value: ksDisplayValue(charts.statsChar),
                    subtitle: ksDisplaySubtitle(charts.statsChar),
                    tint: ksDisplayTint(charts.statsChar)
                )
            }
        }
    }

    /// UP KS 标题: 与前三张卡 "主体 · 指标" 格式对齐。
    /// 有 UP 数据时主体为 "角色 · UP 正态性",降级时为 "角色 · 正态性",
    /// 与下方 ksDisplaySubtitle 的 "UP D" / "综合 D" 始终保持一致。
    private func ksDisplayTitle(_ s: ChartData) -> String {
        s.count_up > 0 ? "角色 · UP 正态性" : "角色 · 正态性"
    }

    /// UP KS 主显示: 优先用 UP, 数据不足降级综合
    private func ksDisplayValue(_ s: ChartData) -> String {
        if s.count_up > 0 { return s.ks_is_normal_up ? "符合" : "偏离" }
        return s.ks_is_normal ? "符合" : "偏离"
    }
    private func ksDisplaySubtitle(_ s: ChartData) -> String {
        if s.count_up > 0 {
            return String(format: "UP D = %.3f", s.ks_d_up)
        }
        return String(format: "综合 D = %.3f", s.ks_d_all)
    }
    private func ksDisplayTint(_ s: ChartData) -> Color {
        let normal = (s.count_up > 0) ? s.ks_is_normal_up : s.ks_is_normal
        return normal ? .primary : .orange
    }

    private func rateString(_ r: Double) -> String {
        r < 0 ? "—" : String(format: "%.1f%%", r * 100)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // 用语义色而非 .regularMaterial:
        //   1) 材质背景需要离屏采样下方像素做模糊, 是渲染最贵的部分,
        //      在快速滚动 + Tab 切换组合下偶发"上下层错位"的渲染 bug;
        //   2) 纯色 secondarySystemBackground 是 iOS 标准卡片背景色
        //      (设置 App 等系统应用都用它), 暗色模式下接近 #1C1C1E,
        //      视觉上与材质几乎一致, 但稳定性高得多。
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - 详细统计:卡池卡片
//
// 把原 C++ 输出的 PC 风格等宽对齐报表,在移动端重排成结构化卡片。
// 完全从 ChartData 直接读取数值,不解析任何文本。
//
// 设计要点:
//   - header: 卡池名 + 总抽数 / UP 数 / 当前垫刀(精简一行)
//   - 数据行: 用左标签 + 右数值的 HStack,可换行,但数字保持等宽对齐
//   - 子注释(理论 / CV / KS / CI 等)用 Text 的 secondary 样式压低视觉权重
//   - 等宽数字用 .monospacedDigit() 而非整体 .monospaced(),
//     中文字符仍走系统字体,避免 monospace 中文的丑陋渲染
private struct PoolDetailCard: View {
    enum Kind {
        case character  // 显示"真实不歪率"
        case weapon     // 显示"6 星中 UP 率"
    }

    let poolName: String
    let stats: ChartData
    let kind: Kind

    // 理论值常量(与 C++ 端格式串里的硬编码值一致)
    // 来源: AnalyzerWrapper.mm 中 PrintReport 格式串
    private var theoryAvgAll: Double { kind == .character ? 51.81 : 19.17 }
    private var theoryAvgUp:  Double { kind == .character ? 74.33 : 81.66 }
    private var theoryUpRate: Double { kind == .character ? 0.50  : 0.25  }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ---- Header ----
            HStack(alignment: .firstTextBaseline) {
                Text(poolName)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(stats.count_all) 总 / \(stats.count_up) UP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // 当前垫刀
            HStack(spacing: 12) {
                pityChip(label: "距上次六星", value: stats.censored_pity_all)
                pityChip(label: "距上次 UP",  value: stats.censored_pity_up)
            }
            .padding(.bottom, 2)

            Divider()

            // ---- 数据行 ----
            // 综合六星出货平均
            DetailRow(
                label: "综合六星出货均值",
                value: String(format: "%.2f 抽", stats.avg_all),
                hint: String(format: "理论 %.2f · CV %.1f%% · 95%% CI [%.1f, %.1f]",
                             theoryAvgAll,
                             stats.cv_all * 100,
                             max(0, stats.avg_all - stats.ci_all_err),
                             stats.avg_all + stats.ci_all_err)
            )

            // K-S 检验 (综合六星)
            DetailRow(
                label: "综合六星 K-S 偏离度",
                value: String(format: "D = %.3f", stats.ks_d_all),
                hint: stats.ks_is_normal ? "符合理论模型" : "偏离理论模型",
                valueTint: stats.ks_is_normal ? .primary : .orange
            )

            // 抽到 UP 平均
            if stats.count_up > 0 {
                DetailRow(
                    label: "抽到 UP 综合均值",
                    value: String(format: "%.2f 抽", stats.avg_up),
                    hint: String(format: "理论 %.2f · 95%% CI [%.1f, %.1f]",
                                 theoryAvgUp,
                                 max(0, stats.avg_up - stats.ci_up_err),
                                 stats.avg_up + stats.ci_up_err)
                )

                // K-S 检验 (UP 六星, v0.1.2 新增)
                // 与综合六星 KS 行紧邻, 让用户能直接对比"机制大盘 vs 当期 UP"
                // 是否各自符合理论模型。
                DetailRow(
                    label: "UP 六星 K-S 偏离度",
                    value: String(format: "D = %.3f", stats.ks_d_up),
                    hint: stats.ks_is_normal_up ? "符合理论模型" : "偏离理论模型",
                    valueTint: stats.ks_is_normal_up ? .primary : .orange
                )
            }

            // 不歪率(角色) / 6 星 UP 率(武器)
            switch kind {
            case .character:
                if stats.win_rate_5050 >= 0 {
                    DetailRow(
                        label: "真实不歪率",
                        value: String(format: "%.1f%%", stats.win_rate_5050 * 100),
                        hint: "理论 \(Int(theoryUpRate * 100))% · \(stats.win_5050) 胜 \(stats.lose_5050) 负"
                    )
                }
                if stats.avg_win > 0 {
                    DetailRow(
                        label: "赢下小保底均值",
                        value: String(format: "%.2f 抽", stats.avg_win),
                        hint: nil
                    )
                }
            case .weapon:
                let upRate = stats.count_all > 0
                    ? Double(stats.win_5050) / Double(stats.count_all)
                    : 0
                if stats.count_up > 0 {
                    DetailRow(
                        label: "6 星 UP 率",
                        value: String(format: "%.1f%%", upRate * 100),
                        hint: "理论 \(Int(theoryUpRate * 100))% · \(stats.win_5050) UP / \(stats.lose_5050) 非 UP"
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // 垫刀 chip:简短的左右胶囊
    private func pityChip(label: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color(uiColor: .tertiarySystemBackground))
        )
    }
}

// 单行数据展示: 左标签 / 右数值, 数值下方可选 hint
private struct DetailRow: View {
    let label: String
    let value: String
    let hint: String?
    var valueTint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.callout.bold())
                    .foregroundStyle(valueTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }
}

#endif
