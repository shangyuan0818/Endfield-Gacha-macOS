//
//  AnalyzerWrapper.h
//  Endfield-Gacha
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h> // 需要用到 NSImage

// 把分析结果打包成一个对象传给 Swift
@interface AnalysisResult : NSObject
@property (nonatomic, strong) NSString *textOutput;
@property (nonatomic, strong) NSImage *chartImage;
@end

@interface AnalyzerWrapper : NSObject
+ (AnalysisResult *)analyzeFile:(NSString *)filePath
                          chars:(NSString *)chars
                           pool:(NSString *)pool
                           weps:(NSString *)weps;
@end
