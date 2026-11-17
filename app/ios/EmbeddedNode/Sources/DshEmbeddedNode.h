#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// NodeMobile owns one V8 runtime per application process. A probe is started
// once; repeated taps observe that same run instead of initializing V8 twice.
@interface DshEmbeddedNode : NSObject
+ (BOOL)startProbeAtPath:(NSString *)script
             reportPath:(NSString *)report
             completion:(void (^)(int))completion;
@end
NS_ASSUME_NONNULL_END
