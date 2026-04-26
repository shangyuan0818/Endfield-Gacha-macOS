//
//  AnalyzerWrapper.mm
//  Endfield-Gacha
//

#import "AnalyzerWrapper.h"
#include <string>
#include <vector>
#include <unordered_set>
#include <unordered_map>
#include <cmath>
#include <algorithm>
#include <string_view>
#include <charconv>
#include <ranges>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

@implementation AnalysisResult
@end

// ==========================================
// [你的 C++ 核心逻辑，一字未改]
// ==========================================
size_t FindJsonKey(std::string_view source, std::string_view key, size_t startPos = 0) {
    while (true) {
        size_t pos = source.find(key, startPos); if (pos == std::string_view::npos) return std::string_view::npos;
        if (pos > 0 && source[pos - 1] == '"' && (pos + key.length() < source.length()) && source[pos + key.length()] == '"') return pos - 1;
        startPos = pos + key.length();
    }
}
std::string_view ExtractJsonValue(std::string_view source, std::string_view key, bool isString) {
    size_t pos = FindJsonKey(source, key); if (pos == std::string_view::npos) return {};
    pos = source.find(':', pos + key.length() + 2); if (pos == std::string_view::npos) return {}; pos++;
    while (pos < source.length() && (source[pos]==' '||source[pos]=='\t'||source[pos]=='\n'||source[pos]=='\r')) pos++;
    if (isString) {
        if (pos >= source.length() || source[pos] != '"') return {}; pos++; auto endPos = pos;
        while (endPos < source.length() && source[endPos] != '"') { if (source[endPos] == '\\') endPos += 2; else endPos++; }
        if (endPos > source.length()) endPos = source.length(); return source.substr(pos, endPos - pos);
    } else {
        auto endPos = pos; while (endPos < source.length() && source[endPos]!=','&&source[endPos]!='}'&&source[endPos]!=']'&&source[endPos]!=' '&&source[endPos]!='\n'&&source[endPos]!='\r') endPos++;
        return source.substr(pos, endPos-pos);
    }
}
template<typename Callback>
void ForEachJsonObject(std::string_view source, std::string_view arrayKey, Callback&& cb) {
    size_t pos = FindJsonKey(source, arrayKey); if (pos == std::string_view::npos) return;
    pos = source.find(':', pos + arrayKey.length() + 2); if (pos == std::string_view::npos) return;
    pos = source.find('[', pos); if (pos == std::string_view::npos) return;
    int depth = 0; size_t objStart = 0;
    for (size_t i = pos; i < source.length(); ++i) {
        char c = source[i];
        if (c == '"') { for (++i; i < source.length() && source[i] != '"'; ++i) { if (source[i] == '\\') i++; } continue; }
        if (c == '{') { if (depth==0) objStart=i; depth++; }
        else if (c == '}') { depth--; if (depth==0) cb(source.substr(objStart, i-objStart+1)); }
        else if (c == ']' && depth == 0) break;
    }
}

struct Pull { std::string name, item_type, rank_type, uigf_gacha_type, poolName; long long id; };
struct Stats {
    std::vector<int> all_pities, up_pities, up_win_pities; double avg_all=0, avg_up=0, avg_win=-1;
    std::unordered_map<int,int> freq_all, freq_up; double std_all=0,std_up=0,cv_all=0,cv_up=0,ci_all_err=0,ci_up_err=0;
    int win_5050=0,lose_5050=0; double win_rate_5050=-1; int max_pity_all=0,max_pity_up=0;
    std::vector<double> hazard_all, hazard_up; double ks_d_all=0; bool ks_is_normal=true;
};
static Stats statsChar, statsWep;

std::unordered_set<std::string> ParseCommaSeparated(const std::string& text) {
    std::unordered_set<std::string> result; std::string cur;
    for (size_t i = 0; i < text.size(); ++i) {
        // UTF-8 全角逗号 = 0xEF 0xBC 0x8C (，) — 必须匹配完整 3 字节
        bool isComma = (text[i] == ',');
        if (!isComma && (unsigned char)text[i] == 0xEF && i+2 < text.size() && (unsigned char)text[i+1] == 0xBC && (unsigned char)text[i+2] == 0x8C) {
            isComma = true; i += 2; // 跳过后两字节
        }
        if (isComma) {
            auto s = cur.find_first_not_of(" \t\r\n"); auto e = cur.find_last_not_of(" \t\r\n");
            if (s != std::string::npos) result.insert(cur.substr(s, e-s+1));
            cur.clear();
        } else cur += text[i];
    }
    auto s = cur.find_first_not_of(" \t\r\n"); auto e = cur.find_last_not_of(" \t\r\n");
    if (s != std::string::npos) result.insert(cur.substr(s, e-s+1));
    return result;
}

std::unordered_map<std::string,std::string> ParsePoolMap(const std::string& text) {
    std::unordered_map<std::string,std::string> result; std::string cur, cur_pool; bool reading_up = false;
    auto trim = [](const std::string& s) -> std::string {
        auto a = s.find_first_not_of(" \t\r\n"); auto b = s.find_last_not_of(" \t\r\n");
        return (a != std::string::npos) ? s.substr(a, b-a+1) : "";
    };
    for (size_t i = 0; i < text.size(); ++i) {
        // UTF-8 全角冒号 = 0xEF 0xBC 0x9A (：)
        bool isColon = (text[i] == ':');
        if (!isColon && (unsigned char)text[i]==0xEF && i+2<text.size() && (unsigned char)text[i+1]==0xBC && (unsigned char)text[i+2]==0x9A) { isColon=true; i+=2; }
        // UTF-8 全角逗号 = 0xEF 0xBC 0x8C (，)
        bool isComma = (text[i] == ',');
        if (!isComma && !isColon && (unsigned char)text[i]==0xEF && i+2<text.size() && (unsigned char)text[i+1]==0xBC && (unsigned char)text[i+2]==0x8C) { isComma=true; i+=2; }
        
        if (isColon && !reading_up) { cur_pool = trim(cur); cur.clear(); reading_up = true; }
        else if (isComma) { auto val = trim(cur); if (!cur_pool.empty() && !val.empty()) result[cur_pool]=val; cur.clear(); cur_pool.clear(); reading_up=false; }
        else cur += text[i];
    }
    if (reading_up) { auto val = trim(cur); if (!cur_pool.empty() && !val.empty()) result[cur_pool]=val; }
    return result;
}

static double g_cdf_char[81] = {}, g_cdf_wep[41] = {};
void InitCDFTables() {
    static bool init = false; if(init) return; init = true;
    double surv = 1.0; for (int i = 1; i <= 80; ++i) { double p = (i<=65)?0.008:(i<=79)?0.058+(i-66)*0.05:1.0; g_cdf_char[i] = g_cdf_char[i-1] + surv*p; surv *= (1.0-p); }
    surv = 1.0; for (int i = 1; i <= 40; ++i) { double p = (i>=40)?1.0:0.04; g_cdf_wep[i] = g_cdf_wep[i-1] + surv*p; surv *= (1.0-p); }
}

double ComputeKS(const std::unordered_map<int,int>& freq, int max_pity, int n, const double* cdf_table, int cdf_len) {
    if (n==0) return 0; double max_d = 0; int cum = 0;
    for (int x = 1; x <= max_pity; ++x) {
        auto it = freq.find(x); int cnt = (it!=freq.end())?it->second:0; double fv = (x<cdf_len)?cdf_table[x]:1.0;
        double d1 = std::abs((double)cum/n - fv); cum += cnt; double d2 = std::abs((double)cum/n - fv);
        if (d1>max_d) max_d=d1; if (d2>max_d) max_d=d2;
    } return max_d;
}

Stats Calculate(const std::vector<Pull>& pulls, bool isWeapon, const std::unordered_set<std::string>& standard_names, const std::unordered_map<std::string,std::string>& pool_map) {
    Stats s; int current_pity=0, pity_since_last_up=0; bool had_non_up=false; long long sum_all=0,sum_sq_all=0,sum_up=0,sum_sq_up=0,sum_win=0;
    for (const auto& p : pulls) {
        bool isSpecial = false;
        if (isWeapon) { if (p.item_type == "Weapon" && p.uigf_gacha_type.find("constant")==std::string::npos && p.uigf_gacha_type.find("standard")==std::string::npos && p.uigf_gacha_type.find("beginner")==std::string::npos) isSpecial = true; }
        else { if (p.item_type == "Character" && p.uigf_gacha_type.find("special") != std::string::npos) isSpecial = true; }
        if (!isSpecial) continue;
        current_pity++; pity_since_last_up++;
        if (p.rank_type == "6") {
            s.all_pities.push_back(current_pity); s.freq_all[current_pity]++; if (current_pity > s.max_pity_all) s.max_pity_all = current_pity; sum_all += current_pity; sum_sq_all += (long long)current_pity*current_pity;
            bool isUP = false; auto it = pool_map.find(p.poolName); if (it != pool_map.end()) isUP = (p.name == it->second); else isUP = !standard_names.contains(p.name);
            if (isUP) {
                s.up_pities.push_back(pity_since_last_up); s.freq_up[pity_since_last_up]++; if (pity_since_last_up > s.max_pity_up) s.max_pity_up = pity_since_last_up; sum_up += pity_since_last_up; sum_sq_up += (long long)pity_since_last_up*pity_since_last_up;
                if (!had_non_up) { s.up_win_pities.push_back(current_pity); s.win_5050++; sum_win += current_pity; }
                had_non_up = false; pity_since_last_up = 0;
            } else { if (!had_non_up) s.lose_5050++; had_non_up = true; }
            current_pity = 0;
        }
    }
    size_t na=s.all_pities.size(), nu=s.up_pities.size(), nw=s.up_win_pities.size();
    if (na>0) {
        s.avg_all = (double)sum_all/na; double var = (double)sum_sq_all/na - s.avg_all*s.avg_all; s.std_all = std::sqrt(var>0?var:0); s.cv_all = s.avg_all>0 ? s.std_all/s.avg_all : 0; s.ci_all_err = 1.96*s.std_all/std::sqrt((double)na); s.hazard_all.resize(s.max_pity_all+1, 0); int surv = (int)na;
        for (int x=1; x<=s.max_pity_all; ++x) { auto it=s.freq_all.find(x); int c=it!=s.freq_all.end()?it->second:0; if(surv>0) s.hazard_all[x]=(double)c/surv; surv-=c; }
        auto* tbl = isWeapon?g_cdf_wep:g_cdf_char; int len = isWeapon?41:81; s.ks_d_all = ComputeKS(s.freq_all, s.max_pity_all, (int)na, tbl, len); s.ks_is_normal = (s.ks_d_all <= 1.36/std::sqrt((double)na));
    }
    if (nu>0) {
        s.avg_up = (double)sum_up/nu; double var = (double)sum_sq_up/nu - s.avg_up*s.avg_up; s.std_up = std::sqrt(var>0?var:0); s.cv_up = s.avg_up>0 ? s.std_up/s.avg_up : 0; s.ci_up_err = 1.96*s.std_up/std::sqrt((double)nu); s.hazard_up.resize(s.max_pity_up+1, 0); int surv = (int)nu;
        for (int x=1; x<=s.max_pity_up; ++x) { auto it=s.freq_up.find(x); int c=it!=s.freq_up.end()?it->second:0; if(surv>0) s.hazard_up[x]=(double)c/surv; surv-=c; }
    }
    if (nw>0) s.avg_win = (double)sum_win/nw; if (s.win_5050+s.lose_5050>0) s.win_rate_5050 = (double)s.win_5050/(s.win_5050+s.lose_5050);
    return s;
}

// ==========================================
// 绘图助手
// ==========================================
static void DrawTextAt(NSString* text, float x, float y, NSFont* font, NSColor* color) {
    [text drawAtPoint:NSMakePoint(x, y) withAttributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: color }];
}

void DrawKDE_CG(NSRect rect, const std::unordered_map<int,int>& freq_all, const std::unordered_map<int,int>& freq_up, NSString* title, int limit_base) {
    static NSFont* g_fontTitle = [NSFont boldSystemFontOfSize:13];
    static NSFont* g_fontTick = [NSFont systemFontOfSize:10];
    [[NSColor clearColor] setFill]; NSRectFill(rect); // 透明背景适应深色模式
    DrawTextAt(title, rect.origin.x+15, rect.origin.y+12, g_fontTitle, [NSColor labelColor]);
    if (freq_all.empty() && freq_up.empty()) return;
    int max_x = limit_base; for (auto&[v,c]:freq_all) if(v>max_x) max_x=v; for (auto&[v,c]:freq_up) if(v>max_x) max_x=v; max_x = ((max_x/10)+1)*10;
    auto calcKDE = [&](const std::unordered_map<int,int>& freqs) { std::vector<double> curve(max_x+1, 0); int total=0; for(auto&[v,c]:freqs) total+=c; if (!total) return curve; for (auto&[v,c]:freqs) { int lo=std::max(1,v-17), hi=std::min(max_x,v+17); for (int x=lo;x<=hi;++x) { double u=(x-v)/4.0; curve[x]+=c*std::exp(-0.5*u*u); } } for(int x=1;x<=max_x;++x) curve[x]*=(1.0/total); return curve; };
    auto kde_all = calcKDE(freq_all), kde_up = calcKDE(freq_up);
    double max_y = 0.0001; for (double v:kde_all) max_y=std::max(max_y,v); for (double v:kde_up) max_y=std::max(max_y,v); max_y *= 1.25;

    float pX=rect.origin.x+50, pY=rect.origin.y+40, pW=rect.size.width-75, pH=rect.size.height-65;
    auto getPt = [&](int x, double y) -> NSPoint { return NSMakePoint(pX + (float)x/max_x*pW, pY + pH - (float)(y/max_y)*pH); };
    NSBezierPath* axis = [NSBezierPath bezierPath]; [axis setLineWidth:1.2]; [[NSColor gridColor] setStroke];
    [axis moveToPoint:NSMakePoint(pX, pY)]; [axis lineToPoint:NSMakePoint(pX, pY+pH)]; [axis moveToPoint:NSMakePoint(pX, pY+pH)]; [axis lineToPoint:NSMakePoint(pX+pW, pY+pH)]; [axis stroke];

    for (int i=0;i<=4;++i) { float py = pY + pH - (float)i/4.0f*pH; if (i>0) { NSBezierPath* grid=[NSBezierPath bezierPath]; [grid setLineWidth:0.5]; [[NSColor gridColor] setStroke]; [grid moveToPoint:NSMakePoint(pX,py)]; [grid lineToPoint:NSMakePoint(pX+pW,py)]; [grid stroke]; } char buf[32]; snprintf(buf, 32, "%.1f%%", (max_y/4.0)*i*100.0); DrawTextAt([NSString stringWithUTF8String:buf], pX-45, py-6, g_fontTick, [NSColor secondaryLabelColor]); }
    for (int x=0;x<=max_x;x+=(max_x>140)?20:10) { float px = pX + (float)x/max_x*pW; char buf[16]; snprintf(buf,16,"%d",x); DrawTextAt([NSString stringWithUTF8String:buf], px-6, pY+pH+4, g_fontTick, [NSColor secondaryLabelColor]); }
    auto drawCurve = [&](const std::vector<double>& curve, NSColor* color) { if (curve.empty()) return; NSBezierPath* path = [NSBezierPath bezierPath]; [path setLineWidth:2.2]; [path moveToPoint:getPt(0, curve[0])]; for (int x=1;x<=max_x;++x) [path lineToPoint:getPt(x, curve[x])]; [color setStroke]; [path stroke]; };
    drawCurve(kde_all, [NSColor systemBlueColor]); drawCurve(kde_up, [NSColor systemRedColor]);
    DrawTextAt(@"━━ 综合六星 (含歪)", rect.origin.x+rect.size.width-175, rect.origin.y+15, g_fontTick, [NSColor systemBlueColor]); DrawTextAt(@"━━ 当期限定 UP", rect.origin.x+rect.size.width-175, rect.origin.y+32, g_fontTick, [NSColor systemRedColor]);
}

void DrawHazard_CG(NSRect rect, const std::vector<double>& hazard_all, const std::vector<double>& hazard_up, NSString* title, int limit_base) {
    static NSFont* g_fontTitle = [NSFont boldSystemFontOfSize:13];
    static NSFont* g_fontTick = [NSFont systemFontOfSize:10];
    [[NSColor clearColor] setFill]; NSRectFill(rect);
    DrawTextAt(title, rect.origin.x+15, rect.origin.y+12, g_fontTitle, [NSColor labelColor]);
    if (hazard_all.empty() && hazard_up.empty()) return;
    int max_x = limit_base; if (!hazard_all.empty() && (int)hazard_all.size()-1>max_x) max_x=(int)hazard_all.size()-1; if (!hazard_up.empty() && (int)hazard_up.size()-1>max_x) max_x=(int)hazard_up.size()-1; max_x = ((max_x/10)+1)*10;
    double max_y = 0.1; for (double v:hazard_all) max_y=std::max(max_y,v); for (double v:hazard_up) max_y=std::max(max_y,v); if (max_y>0.8) max_y=1.05; else max_y=std::ceil(max_y*10)/10.0+0.1;
    float pX=rect.origin.x+50, pY=rect.origin.y+40, pW=rect.size.width-75, pH=rect.size.height-65;
    auto getPt = [&](int x, double y) -> NSPoint { return NSMakePoint(pX+(float)x/max_x*pW, pY+pH-(float)(y/max_y)*pH); };
    NSBezierPath* axis=[NSBezierPath bezierPath]; [axis setLineWidth:1.2]; [[NSColor gridColor] setStroke];
    [axis moveToPoint:NSMakePoint(pX,pY)]; [axis lineToPoint:NSMakePoint(pX,pY+pH)]; [axis moveToPoint:NSMakePoint(pX,pY+pH)]; [axis lineToPoint:NSMakePoint(pX+pW,pY+pH)]; [axis stroke];

    for (int i=0;i<=4;++i) { float py = pY + pH - (float)i/4.0f*pH; if (i>0) { NSBezierPath* grid=[NSBezierPath bezierPath]; [grid setLineWidth:0.5]; [[NSColor gridColor] setStroke]; [grid moveToPoint:NSMakePoint(pX,py)]; [grid lineToPoint:NSMakePoint(pX+pW,py)]; [grid stroke]; } char buf[32]; snprintf(buf,32,"%.0f%%",(max_y/4.0)*i*100.0); DrawTextAt([NSString stringWithUTF8String:buf], pX-40, py-6, g_fontTick, [NSColor secondaryLabelColor]); }
    for (int x=0;x<=max_x;x+=(max_x>140)?20:10) { float px=pX+(float)x/max_x*pW; char buf[16]; snprintf(buf,16,"%d",x); DrawTextAt([NSString stringWithUTF8String:buf], px-6, pY+pH+4, g_fontTick, [NSColor secondaryLabelColor]); }
    float barW = std::max(1.5f, pW/max_x*0.4f);
    auto drawBars = [&](const std::vector<double>& h, NSColor* color, float offset) { [color setFill]; for (size_t x=1;x<h.size();++x) if (h[x]>0) { NSPoint pt = getPt((int)x, h[x]); NSRectFill(NSMakeRect(pt.x+offset, pt.y, barW, (pY+pH)-pt.y)); } };
    drawBars(hazard_all, [[NSColor systemBlueColor] colorWithAlphaComponent:0.7], -barW); drawBars(hazard_up, [[NSColor systemRedColor] colorWithAlphaComponent:0.7], 0);
    DrawTextAt(@"■ 综合六星条件概率", rect.origin.x+rect.size.width-150, rect.origin.y+15, g_fontTick, [NSColor systemBlueColor]); DrawTextAt(@"■ 限定 UP 条件概率", rect.origin.x+rect.size.width-150, rect.origin.y+32, g_fontTick, [NSColor systemRedColor]);
}

// ==========================================
// [接口实现：彻底舍弃 drawingHandler 动态重绘]
// ==========================================
@implementation AnalyzerWrapper

+ (AnalysisResult *)analyzeFile:(NSString *)filePath chars:(NSString *)chars pool:(NSString *)pool weps:(NSString *)weps {
    AnalysisResult *res = [[AnalysisResult alloc] init];
    InitCDFTables();

    auto stdChars = ParseCommaSeparated(chars.UTF8String ? chars.UTF8String : "");
    auto poolMap = ParsePoolMap(pool.UTF8String ? pool.UTF8String : "");
    auto stdWeps = ParseCommaSeparated(weps.UTF8String ? weps.UTF8String : "");

    int fd = open(filePath.UTF8String, O_RDONLY);
    if (fd < 0) { res.textOutput = @"文件读取失败"; return res; }
    struct stat st; fstat(fd, &st); if (st.st_size <= 0) { close(fd); res.textOutput = @"文件为空"; return res; }
    const char* mapData = (const char*)mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (mapData == MAP_FAILED) { close(fd); res.textOutput = @"内存映射失败"; return res; }

    std::string_view bufferView(mapData, st.st_size);
    if (bufferView.size()>=3 && (uint8_t)bufferView[0]==0xEF && (uint8_t)bufferView[1]==0xBB && (uint8_t)bufferView[2]==0xBF) bufferView.remove_prefix(3);

    std::vector<Pull> pulls; pulls.reserve(1000);
    ForEachJsonObject(bufferView, "list", [&](std::string_view itemStr) {
        Pull p;
        p.name = std::string(ExtractJsonValue(itemStr, "name", true)); p.item_type = std::string(ExtractJsonValue(itemStr, "item_type", true)); p.rank_type = std::string(ExtractJsonValue(itemStr, "rank_type", true)); p.poolName = std::string(ExtractJsonValue(itemStr, "poolName", true));
        if (p.poolName.empty()) p.poolName = std::string(ExtractJsonValue(itemStr, "gacha_name", true)); if (p.poolName.empty()) p.poolName = std::string(ExtractJsonValue(itemStr, "poolname", true));
        std::string raw_type(ExtractJsonValue(itemStr, "uigf_gacha_type", true)); std::ranges::transform(raw_type, raw_type.begin(), [](unsigned char c) { return std::tolower(c); }); p.uigf_gacha_type = raw_type;
        auto idStr = ExtractJsonValue(itemStr, "id", true); if (idStr.empty()) idStr = ExtractJsonValue(itemStr, "id", false);
        long long pid=0; if(!idStr.empty()) std::from_chars(idStr.data(), idStr.data()+idStr.size(), pid); p.id = pid;
        pulls.push_back(std::move(p));
    });
    munmap((void*)mapData, st.st_size); close(fd);
    
    if (pulls.empty()) { res.textOutput = @"JSON 解析失败或无数据。"; return res; }
    std::ranges::sort(pulls, {}, [](const Pull& p){ return std::abs(p.id); });
    
    statsChar = Calculate(pulls, false, stdChars, poolMap);
    statsWep  = Calculate(pulls, true, stdWeps, {});

    char winC[64] = "[无数据]", winW[64] = "[无数据]";
    if (statsChar.avg_win>=0) snprintf(winC,64,"%.2f 抽",statsChar.avg_win); if (statsWep.avg_win>=0) snprintf(winW,64,"%.2f 抽",statsWep.avg_win);
    char outBuf[2048];
    snprintf(outBuf, sizeof(outBuf),
        "【角色卡池 (特许寻访)】 总计六星: %zu | 出当期 UP: %zu\n ▶ 综合六星期望: %.2f 抽  [95%% CI: %.1f ~ %.1f]  |  CV: %.1f%%  [K-S D: %.3f (%s)]\n ▶ 当期UP期望: %.2f 抽  [95%% CI: %.1f ~ %.1f]  |  不歪率: %.1f%% (%d胜%d负)\n ▶ 直接命中UP期望: %s\n\n"
        "【武器卡池 (武库申领)】 总计六星: %zu | 出当期 UP: %zu\n ▶ 综合六星期望: %.2f 抽  [95%% CI: %.1f ~ %.1f]  |  CV: %.1f%%  [K-S D: %.3f (%s)]\n ▶ 当期UP期望: %.2f 抽  [95%% CI: %.1f ~ %.1f]  |  不歪率: %.1f%% (%d胜%d负)\n ▶ 直接命中UP期望: %s",
        statsChar.all_pities.size(), statsChar.up_pities.size(), statsChar.avg_all, std::max(1.0,statsChar.avg_all-statsChar.ci_all_err), statsChar.avg_all+statsChar.ci_all_err, statsChar.cv_all*100, statsChar.ks_d_all, statsChar.all_pities.empty()?"-":(statsChar.ks_is_normal?"符合理论":"偏离过大"), statsChar.avg_up, std::max(1.0,statsChar.avg_up-statsChar.ci_up_err), statsChar.avg_up+statsChar.ci_up_err, statsChar.win_rate_5050>=0?statsChar.win_rate_5050*100:0.0, statsChar.win_5050, statsChar.lose_5050, winC,
        statsWep.all_pities.size(), statsWep.up_pities.size(), statsWep.avg_all, std::max(1.0,statsWep.avg_all-statsWep.ci_all_err), statsWep.avg_all+statsWep.ci_all_err, statsWep.cv_all*100, statsWep.ks_d_all, statsWep.all_pities.empty()?"-":(statsWep.ks_is_normal?"符合理论":"偏离过大"), statsWep.avg_up, std::max(1.0,statsWep.avg_up-statsWep.ci_up_err), statsWep.avg_up+statsWep.ci_up_err, statsWep.win_rate_5050>=0?statsWep.win_rate_5050*100:0.0, statsWep.win_5050, statsWep.lose_5050, winW
    );
    res.textOutput = [NSString stringWithUTF8String:outBuf];

    // ==========================================
    // 重点优化：一次性绘制定死的静态缓存图[cite: 5]
    // ==========================================
    NSSize sz = NSMakeSize(1100, 480);
    NSImage *image = [[NSImage alloc] initWithSize:sz];
    
    // 锁定焦点进入后台绘制状态，等同于 AppKit 版的 lockFocus[cite: 5]
    [image lockFocusFlipped:YES];
    
    float w = sz.width / 2.0; float h = sz.height / 2.0;
    DrawKDE_CG(NSMakeRect(0, 0, w, h), statsChar.freq_all, statsChar.freq_up, @"角色期望核密度", 130);
    DrawHazard_CG(NSMakeRect(w, 0, w, h), statsChar.hazard_all, statsChar.hazard_up, @"角色经验风险函数", 130);
    DrawKDE_CG(NSMakeRect(0, h, w, h), statsWep.freq_all, statsWep.freq_up, @"武器期望核密度", 80);
    DrawHazard_CG(NSMakeRect(w, h, w, h), statsWep.hazard_all, statsWep.hazard_up, @"武器经验风险函数", 80);
    
    // 解锁焦点，生成最终死图
    [image unlockFocus];
    
    res.chartImage = image;
    return res;
}
@end
