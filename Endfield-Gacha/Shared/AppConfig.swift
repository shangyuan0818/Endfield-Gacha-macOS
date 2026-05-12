//
//  AppConfig.swift
//  Endfield-Gacha
//
//  跨平台共享配置:常驻角色 / 当期 UP / 常驻武器
//  - iOS: 通过 SettingsView 修改并持久化到 UserDefaults
//  - macOS: 现有 ContentView 暂仍用 @State 直接持有,
//           未来要统一也可以接入这里(留作后续重构)
//
//  @Observable 让 SwiftUI 自动追踪字段变化,
//  设置页改完分析页能立即拿到新值。
//

import SwiftUI

@Observable
final class AppConfig {
    var chars: String
    var pool:  String
    var weps:  String

    static let defaultChars = "骏卫,黎风,别礼,余烬,艾尔黛拉"
    static let defaultPool  = "熔火灼痕:莱万汀,轻飘飘的信使:洁尔佩塔,热烈色彩:伊冯,河流的女儿:汤汤,狼珀:洛茜,春雷动，万物生:庄方宜"
    static let defaultWeps  = "宏愿,不知归,黯色火炬,扶摇,热熔切割器,显赫声名,白夜新星,大雷斑,赫拉芬格,典范,昔日精品,破碎君王,J.E.T.,骁勇,负山,同类相食,楔子,领航者,骑士精神,遗忘,爆破单元,作品：蚀迹,沧溟星梦,光荣记忆,望乡"

    init() {
        let d = UserDefaults.standard
        self.chars = d.string(forKey: "cfg.chars") ?? Self.defaultChars
        self.pool  = d.string(forKey: "cfg.pool")  ?? Self.defaultPool
        self.weps  = d.string(forKey: "cfg.weps")  ?? Self.defaultWeps
    }

    /// 把当前配置写回 UserDefaults。
    /// 调用时机:Settings Tab 退出 / App 进入后台。
    func persist() {
        let d = UserDefaults.standard
        d.set(chars, forKey: "cfg.chars")
        d.set(pool,  forKey: "cfg.pool")
        d.set(weps,  forKey: "cfg.weps")
    }
}
