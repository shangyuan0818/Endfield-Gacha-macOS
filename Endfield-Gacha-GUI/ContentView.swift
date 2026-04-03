//
//  ContentView.swift
//  Endfield-Gacha
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var chars: String = "骏卫,黎风,别礼,余烬,艾尔黛拉"
    @State private var pool: String = "熔火灼痕:莱万汀,轻飘飘的信使:洁尔佩塔,热烈色彩:伊冯,河流的女儿:汤汤,狼珀:洛茜"
    @State private var weps: String = "宏愿,不知归,黯色火炬,扶摇,热熔切割器,显赫声名,白夜新星,大雷斑,赫拉芬格,典范,昔日精品,破碎君王,J.E.T.,骁勇,负山,同类相食,楔子,领航者,骑士精神,遗忘,爆破单元,作品：蚀迹,沧溟星梦,光荣记忆,望乡"
    
    @State private var outputText: String = "将 UIGF JSON 文件直接拖入本窗口即可..."
    @State private var chartImage: NSImage? = nil
    @State private var isHovering: Bool = false
    @State private var isProcessing: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            
            // 顶部提示语
            Text("支持“限定角色卡池:当期UP角色”映射。未包含的限定角色卡池将仅排查常驻六星角色名单。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            
            // 输入区域 (现代表单样式)
            VStack(spacing: 12) {
                HStack { Text("常驻六星角色:").frame(width: 100, alignment: .trailing); TextField("", text: $chars).textFieldStyle(.roundedBorder) }
                HStack { Text("当期UP角色:").frame(width: 100, alignment: .trailing); TextField("", text: $pool).textFieldStyle(.roundedBorder) }
                HStack { Text("常驻六星武器:").frame(width: 100, alignment: .trailing); TextField("", text: $weps).textFieldStyle(.roundedBorder) }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            
            // 输出文字区 (强行制造类似 Win32 的不可编辑灰色底)
            ScrollView {
                Text(outputText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .textSelection(.enabled) // 依然保留框选复制功能
            .frame(height: 155) // 140
            // 关键改动：强制加上一层 15% 透明度的灰色，完美复刻禁用底色
            .background(Color.gray.opacity(0.15))
            .cornerRadius(6)
            // 加深边框颜色和对比度，勾勒出明显的输入框轮廓
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
            
            // 图表渲染区
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                
                if let img = chartImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    if isProcessing {
                        ProgressView("分析中...") // 给予用户及时反馈
                    } else {
                        Text("等待分析数据...").foregroundColor(.gray)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 700)
        .overlay(
            // 拖拽高亮提示层
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, dash: [10]))
                .background(Color.blue.opacity(0.1))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(false)
        )
        // 绑定拖拽事件
        .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let path = url?.path {
                    // 切回主线程改变状态
                    DispatchQueue.main.async {
                        self.isProcessing = true
                        self.chartImage = nil // 清空旧图表
                        self.outputText = "正在读取并解析文件，请稍候..."
                    }
                    // 开启后台线程进行 C++ 计算
                    processFile(path: path)
                }
            }
            return true
        }
    }
    
    func processFile(path: String) {
        // 在高优先级后台队列中执行沉重的 C++ 解析和绘图操作
        DispatchQueue.global(qos: .userInitiated).async {
            if let result = AnalyzerWrapper.analyzeFile(path, chars: chars, pool: pool, weps: weps) {
                // 计算完成后，将生成的静态文字和图片送回主线程更新 UI
                DispatchQueue.main.async {
                    self.outputText = result.textOutput
                    self.chartImage = result.chartImage
                    self.isProcessing = false
                }
            } else {
                DispatchQueue.main.async {
                    self.outputText = "内部错误：无法获取分析结果。"
                    self.isProcessing = false
                }
            }
        }
    }
}
