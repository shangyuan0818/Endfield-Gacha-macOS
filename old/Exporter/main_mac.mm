// main_mac.mm - 终末地 UIGF 导出工具 (macOS)
// clang++ -std=c++20 -ObjC++ -framework Foundation main_mac.mm -o export
// clang++ -std=c++20 -ObjC++ -framework Foundation -arch arm64 -arch x86_64 main_mac.mm -o export
#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include <unordered_set>
#include <algorithm>
#include <ctime>
#include <string_view>
#include <charconv>
#include <ranges>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstring>

// ---------------------------------------------------------
// [极简 JSON 解析模块 - 零分配纯净版] (纯 C++, 跨平台)
// ---------------------------------------------------------
size_t FindJsonKey(std::string_view source, std::string_view key, size_t startPos = 0) {
    while (true) {
        size_t pos = source.find(key, startPos);
        if (pos == std::string_view::npos) return std::string_view::npos;
        if (pos > 0 && source[pos - 1] == '"' && 
            (pos + key.length() < source.length()) && source[pos + key.length()] == '"') {
            return pos - 1; 
        }
        startPos = pos + key.length();
    }
}

std::string_view ExtractJsonValue(std::string_view source, std::string_view key, bool isString) {
    size_t pos = FindJsonKey(source, key);
    if (pos == std::string_view::npos) return {};
    pos = source.find(':', pos + key.length() + 2);
    if (pos == std::string_view::npos) return {};
    pos++; 
    while (pos < source.length() && (source[pos] == ' ' || source[pos] == '\t' || source[pos] == '\n' || source[pos] == '\r')) pos++;
    
    if (isString) {
        if (pos >= source.length() || source[pos] != '"') return {};
        pos++; 
        auto endPos = pos;
        while (endPos < source.length() && source[endPos] != '"') {
            if (source[endPos] == '\\') endPos++; 
            endPos++;
        }
        return (endPos < source.length()) ? source.substr(pos, endPos - pos) : std::string_view{};
    } else {
        auto endPos = pos;
        while (endPos < source.length() && source[endPos] != ',' && source[endPos] != '}' && source[endPos] != ']' && source[endPos] != ' ' && source[endPos] != '\n' && source[endPos] != '\r') endPos++;
        return source.substr(pos, endPos - pos);
    }
}

template<typename Callback>
void ForEachJsonObject(std::string_view source, std::string_view arrayKey, Callback&& cb) {
    size_t pos = FindJsonKey(source, arrayKey);
    if (pos == std::string_view::npos) return;
    pos = source.find(':', pos + arrayKey.length() + 2);
    if (pos == std::string_view::npos) return;
    pos = source.find('[', pos);
    if (pos == std::string_view::npos) return;
    
    int depth = 0;
    size_t objStart = 0;
    for (size_t i = pos; i < source.length(); ++i) {
        char c = source[i];
        if (c == '"') {
            for (++i; i < source.length(); ++i) {
                if (source[i] == '\\') { ++i; continue; }
                if (source[i] == '"') break;
            }
            continue;
        }
        if (c == '{') {
            if (depth == 0) objStart = i;
            depth++;
        } else if (c == '}') {
            depth--;
            if (depth == 0) cb(source.substr(objStart, i - objStart + 1));
        } else if (c == ']' && depth == 0) break;
    }
}
// ---------------------------------------------------------

std::string MsToTimeString(long long ms) {
    time_t t = ms / 1000;
    struct tm tm_info;
    localtime_r(&t, &tm_info); // POSIX 替代 localtime_s
    char buf[64];
    snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d",
        tm_info.tm_year + 1900, tm_info.tm_mon + 1, tm_info.tm_mday,
        tm_info.tm_hour, tm_info.tm_min, tm_info.tm_sec);
    return std::string(buf);
}

char* I64ToStr(long long val, char* buf) {
    auto [ptr, ec] = std::to_chars(buf, buf + 20, val);
    *ptr = '\0';
    return buf;
}

std::string_view ExtractUrlParam(std::string_view url, std::string_view key) {
    size_t pos = url.find(key);
    if (pos == std::string_view::npos) return {};
    pos += key.length();
    size_t end = url.find('&', pos);
    return (end == std::string_view::npos) ? url.substr(pos) : url.substr(pos, end - pos);
}

struct UIGFItem {
    std::string uigf_gacha_type, id, item_id, name, item_type, rank_type, time, gachaTs, poolName, weaponType;
    bool isNew = false, isFree = false;
    long long parsed_id = 0, parsed_ts = 0;
};

// NSURLSession 同步 HTTPS 请求 (替代 WinHTTP)
std::string FetchURL(const std::string& urlStr) {
    @autoreleasepool {
        NSString* nsUrl = [NSString stringWithUTF8String:urlStr.c_str()];
        NSURL* url = [NSURL URLWithString:nsUrl];
        if (!url) return {};
        
        __block NSData* resultData = nil;
        __block NSError* resultError = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        
        NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithURL:url
            completionHandler:^(NSData* data, NSURLResponse* resp, NSError* err) {
                resultData = data;
                resultError = err;
                dispatch_semaphore_signal(sem);
            }];
        [task resume];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        
        if (resultError || !resultData) return {};
        return std::string((const char*)resultData.bytes, resultData.length);
    }
}

struct PoolConfig { std::string poolType, displayName; bool isWeapon; };

// ---------------------------------------------------------
// POSIX 缓冲写入器 (替代 Win32 BufferedWriter)
// ---------------------------------------------------------
struct BufferedWriter {
    int fd;
    char buf[65536];
    size_t pos = 0;
    
    void Flush() {
        if (pos > 0) { ::write(fd, buf, pos); pos = 0; }
    }
    void Write(const char* data, size_t len) {
        while (len > 0) {
            size_t space = sizeof(buf) - pos;
            size_t chunk = (len < space) ? len : space;
            memcpy(buf + pos, data, chunk);
            pos += chunk; data += chunk; len -= chunk;
            if (pos == sizeof(buf)) Flush();
        }
    }
    void Write(std::string_view sv) { Write(sv.data(), sv.size()); }
    
    void WriteEscaped(std::string_view s) {
        const char* p = s.data();
        const char* end = p + s.size();
        while (p < end) {
            const char* clean = p;
            while (p < end && *p != '"' && *p != '\\') ++p;
            if (p > clean) Write(clean, (size_t)(p - clean));
            if (p < end) {
                if (*p == '"')       Write("\\\"", 2);
                else if (*p == '\\') Write("\\\\", 2);
                ++p;
            }
        }
    }
    
    void WriteKV(std::string_view key, std::string_view val) {
        Write("            \"", 13);
        Write(key);
        Write("\": \"", 4);
        WriteEscaped(val);
        Write("\"", 1);
    }
};

int main() {
    @autoreleasepool {
    
    char urlBuffer[1024];
    printf("请输入您的终末地抽卡记录完整链接:\n> ");
    if (!fgets(urlBuffer, sizeof(urlBuffer), stdin)) return 1;
    
    std::string_view inputUrl(urlBuffer);
    while (!inputUrl.empty() && (inputUrl.back() == ' ' || inputUrl.back() == '\n' || inputUrl.back() == '\r' || inputUrl.back() == '\t'))
        inputUrl.remove_suffix(1);

    auto token = ExtractUrlParam(inputUrl, "token=");
    if (token.empty()) {
        printf("错误: 无法提取 token。\n"); return 1;
    }
    
    auto serverId = ExtractUrlParam(inputUrl, "server_id=");
    if (serverId.empty()) serverId = "1";
    printf("\n已自动识别 Server ID: %.*s\n", (int)serverId.size(), serverId.data());

    std::vector<PoolConfig> pools = {
        {"E_CharacterGachaPoolType_Special", "角色 - 特许寻访", false},
        {"E_CharacterGachaPoolType_Standard", "角色 - 基础寻访", false},
        {"E_CharacterGachaPoolType_Beginner", "角色 - 启程寻访", false},
        {"", "武器 - 全历史记录", true}
    };
    
    // --- 新增：定位程序运行目录 ---
    NSString *exePath = [[NSBundle mainBundle] executablePath];
    NSString *exeDir = [exePath stringByDeletingLastPathComponent];
    NSString *fullPath = [exeDir stringByAppendingPathComponent:@"uigf_endfield.json"];
    std::string uigfFilename = [fullPath UTF8String];
    // -------------------------
    // std::string uigfFilename = "uigf_endfield.json";
    std::vector<UIGFItem> allRecords;
    std::unordered_set<long long> localIds;
    
    // POSIX mmap 读取本地文件 (替代 CreateFileMapping)
    int fd = open(uigfFilename.c_str(), O_RDONLY);
    if (fd >= 0) {
        struct stat st;
        if (fstat(fd, &st) == 0 && st.st_size > 0) {
            const char* mapData = (const char*)mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
            if (mapData != MAP_FAILED) {
                std::string_view bufferView(mapData, st.st_size);
                
                ForEachJsonObject(bufferView, "list", [&](std::string_view itemStr) {
                    UIGFItem uItem;
                    uItem.uigf_gacha_type = ExtractJsonValue(itemStr, "uigf_gacha_type", true);
                    uItem.id = ExtractJsonValue(itemStr, "id", true);
                    uItem.item_id = ExtractJsonValue(itemStr, "item_id", true);
                    uItem.name = ExtractJsonValue(itemStr, "name", true);
                    uItem.item_type = ExtractJsonValue(itemStr, "item_type", true);
                    uItem.rank_type = ExtractJsonValue(itemStr, "rank_type", true);
                    uItem.time = ExtractJsonValue(itemStr, "time", true);
                    uItem.gachaTs = ExtractJsonValue(itemStr, "gachaTs", true);
                    uItem.poolName = ExtractJsonValue(itemStr, "poolName", true);
                    uItem.weaponType = ExtractJsonValue(itemStr, "weaponType", true);
                    uItem.isNew = (ExtractJsonValue(itemStr, "isNew", false) == "true");
                    uItem.isFree = (ExtractJsonValue(itemStr, "isFree", false) == "true");
                    
                    if (!uItem.id.empty()) std::from_chars(uItem.id.data(), uItem.id.data() + uItem.id.size(), uItem.parsed_id);
                    if (!uItem.gachaTs.empty()) std::from_chars(uItem.gachaTs.data(), uItem.gachaTs.data() + uItem.gachaTs.size(), uItem.parsed_ts);
                    
                    localIds.insert(uItem.parsed_id);
                    allRecords.push_back(std::move(uItem));
                });
                munmap((void*)mapData, st.st_size);
            }
        }
        close(fd);
        printf("成功加载本地存储的 %zu 条抽卡记录。\n", allRecords.size());
    } else {
        printf("未发现本地记录，将创建新文件。\n");
    }

    // 区服判断
    std::string hostName = "ef-webview.gryphline.com";
    if (inputUrl.find("hypergryph") != std::string_view::npos) {
        hostName = "ef-webview.hypergryph.com";
        printf("已自动识别区服: 国服 (Hypergryph)\n");
    } else {
        printf("已自动识别区服: 国际服 (Gryphline)\n");
    }

    printf("\n========================================\n");
    printf("        开始向服务器拉取抽卡数据\n");
    printf("========================================\n");

    std::unordered_set<long long> sessionIds;
    std::string tokenStr(token);
    std::string serverIdStr(serverId);

    for (const auto& pool : pools) {
        printf("\n>>> 正在抓取 [%s] ...\n", pool.displayName.c_str());
        bool hasMore = true, reachedExisting = false;
        long long nextSeqIdCursor = 0; 
        int page = 1, poolFetchedCount = 0;
        char seqIdBuf[24];

        while (hasMore && !reachedExisting) {
            std::string currentUrl = "https://" + hostName + (pool.isWeapon 
                ? "/api/record/weapon?lang=zh-cn&token=" + tokenStr + "&server_id=" + serverIdStr
                : "/api/record/char?lang=zh-cn&pool_type=" + pool.poolType + "&token=" + tokenStr + "&server_id=" + serverIdStr);
            if (page > 1 && nextSeqIdCursor > 0) {
                currentUrl += "&seq_id=";
                currentUrl += I64ToStr(nextSeqIdCursor, seqIdBuf);
            }

            std::string resStr = FetchURL(currentUrl);
            if (resStr.empty()) { printf("  [错误] 网络请求失败或 Token 已失效。\n"); break; }

            std::string_view resView(resStr);
            std::string_view codeStr = ExtractJsonValue(resView, "code", false);
            if (codeStr.empty()) { printf("  [错误] 接口返回了非 JSON 数据或格式异常。\n"); break; }
            if (codeStr != "0") {
                auto msgStr = ExtractJsonValue(resView, "msg", true);
                printf("  [提示] 接口返回信息: %.*s\n", (int)msgStr.size(), msgStr.data());
                break;
            }

            long long lastSeqParsed = 0;
            ForEachJsonObject(resView, "list", [&](std::string_view itemStr) {
                if (reachedExisting) return;
                std::string_view rawSeqIdStr = ExtractJsonValue(itemStr, "seqId", true);
                if (rawSeqIdStr.empty()) return;

                long long rawSeqId = 0;
                std::from_chars(rawSeqIdStr.data(), rawSeqIdStr.data() + rawSeqIdStr.size(), rawSeqId);
                lastSeqParsed = rawSeqId;
                long long safeUniqueId = pool.isWeapon ? -rawSeqId : rawSeqId;
                
                if (localIds.contains(safeUniqueId)) {
                    reachedExisting = true;
                    printf("  * 触达本地老记录 (ID: %lld)，停止追溯。\n", rawSeqId);
                    return;
                }
                if (sessionIds.contains(safeUniqueId)) {
                    printf("\n  [警告] 遇到重复数据 (ID: %lld)，防死循环中止。\n", rawSeqId);
                    hasMore = false; return;
                }

                UIGFItem uItem;
                uItem.uigf_gacha_type = ExtractJsonValue(itemStr, "poolId", true);
                char idBuf[24];
                uItem.id = I64ToStr(safeUniqueId, idBuf);
                uItem.parsed_id = safeUniqueId; 
                uItem.rank_type = ExtractJsonValue(itemStr, "rarity", false);
                uItem.poolName = ExtractJsonValue(itemStr, "poolName", true);
                
                if (pool.isWeapon) {
                    uItem.item_id = ExtractJsonValue(itemStr, "weaponId", true);
                    uItem.name = ExtractJsonValue(itemStr, "weaponName", true);
                    uItem.item_type = "Weapon";
                    uItem.weaponType = ExtractJsonValue(itemStr, "weaponType", true);
                } else {
                    uItem.item_id = ExtractJsonValue(itemStr, "charId", true);
                    uItem.name = ExtractJsonValue(itemStr, "charName", true);
                    uItem.item_type = "Character";
                }
                
                std::string_view tsStr = ExtractJsonValue(itemStr, "gachaTs", true);
                if (!tsStr.empty()) std::from_chars(tsStr.data(), tsStr.data() + tsStr.size(), uItem.parsed_ts);
                
                uItem.time = MsToTimeString(uItem.parsed_ts); 
                uItem.gachaTs = tsStr;
                uItem.isNew = (ExtractJsonValue(itemStr, "isNew", false) == "true");
                uItem.isFree = (ExtractJsonValue(itemStr, "isFree", false) == "true");

                sessionIds.insert(safeUniqueId);
                allRecords.push_back(std::move(uItem));
                poolFetchedCount++;
                printf("  获取到: %s (%s 星) [%s] - %s\n", allRecords.back().name.c_str(), allRecords.back().rank_type.c_str(), allRecords.back().poolName.c_str(), allRecords.back().time.c_str());
            });

            if (reachedExisting || !hasMore) break;
            nextSeqIdCursor = lastSeqParsed;
            hasMore = (ExtractJsonValue(resView, "hasMore", false) == "true");
            page++;
            usleep(300000); // 300ms, 替代 Sleep(300)
        }
        printf(">>> [%s] 抓取完成，本次新增拉取: %d 条。\n", pool.displayName.c_str(), poolFetchedCount);
        usleep(500000);
    }

    printf("\n========================================\n");
    printf("已完成全部抓取！总计新增拉取了 %zu 条记录。\n", sessionIds.size());

    std::ranges::sort(allRecords, [](const UIGFItem& a, const UIGFItem& b) {
        bool isWeaponA = a.parsed_id < 0, isWeaponB = b.parsed_id < 0;
        if (isWeaponA != isWeaponB) return isWeaponA < isWeaponB; 
        if (a.parsed_ts != b.parsed_ts) return a.parsed_ts < b.parsed_ts;
        return std::abs(a.parsed_id) < std::abs(b.parsed_id);
    });

    time_t rawtime; time(&rawtime);
    long long export_ts = (long long)rawtime;
    std::string export_time = MsToTimeString(export_ts * 1000);

    // POSIX 缓冲写入 (替代 Win32 CreateFile + WriteFile)
    int outFd = open(uigfFilename.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (outFd >= 0) {
        BufferedWriter w{outFd};
        char numBuf[24];
        
        w.Write("{\n    \"info\": {\n");
        w.Write("        \"uid\": \"0\",\n        \"lang\": \"zh-cn\",\n");
        w.Write("        \"export_time\": \""); w.Write(export_time); w.Write("\",\n");
        w.Write("        \"export_timestamp\": "); w.Write(I64ToStr(export_ts, numBuf)); w.Write(",\n");
        w.Write("        \"export_app\": \"Endfield Exporter\",\n        \"export_app_version\": \"v2.3.0\",\n        \"uigf_version\": \"v3.0\"\n    },\n");
        w.Write("    \"list\": [\n");

        for (size_t i = 0; i < allRecords.size(); ++i) {
            const auto& p = allRecords[i];
            w.Write("        {\n");
            w.WriteKV("uigf_gacha_type", p.uigf_gacha_type); w.Write(",\n");
            w.WriteKV("id", p.id); w.Write(",\n");
            w.WriteKV("item_id", p.item_id); w.Write(",\n");
            w.WriteKV("name", p.name); w.Write(",\n");
            w.WriteKV("item_type", p.item_type); w.Write(",\n");
            w.WriteKV("rank_type", p.rank_type); w.Write(",\n");
            w.WriteKV("time", p.time); w.Write(",\n");
            w.WriteKV("gachaTs", p.gachaTs); w.Write(",\n");
            if (!p.poolName.empty()) { w.WriteKV("poolName", p.poolName); w.Write(",\n"); }
            if (!p.weaponType.empty()) { w.WriteKV("weaponType", p.weaponType); w.Write(",\n"); }
            w.Write("            \"isNew\": "); w.Write(p.isNew ? "true" : "false"); w.Write(",\n");
            w.Write("            \"isFree\": "); w.Write(p.isFree ? "true" : "false"); w.Write("\n");
            w.Write("        }");
            if (i < allRecords.size() - 1) w.Write(",");
            w.Write("\n");
        }
        
        w.Write("    ]\n}\n");
        w.Flush();
        close(outFd);
        printf("已成功更新记录并保存至: %s\n", uigfFilename.c_str());
    } else {
        printf("文件写入失败！请检查目录权限。\n");
    }

    printf("按回车键退出...\n");
    getchar();
    return 0;
    
    } // @autoreleasepool
}
