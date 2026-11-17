#import "DshEmbeddedNode.h"
#include <NodeMobile/NodeMobile.h>
#include <cstring>
#include <vector>

@implementation DshEmbeddedNode
+ (BOOL)startProbeAtPath:(NSString *)script reportPath:(NSString *)report completion:(void (^)(int))completion {
  static BOOL started = NO;
  @synchronized(self) {
    if (started) return NO;
    started = YES;
  }
  NSThread *thread = [[NSThread alloc] initWithBlock:^{
    @autoreleasepool {
      NSArray<NSString *> *arguments = @[@"node", script, report];
      size_t bytes = 0;
      for (NSString *argument in arguments) bytes += strlen(argument.UTF8String) + 1;
      std::vector<char> storage(bytes);
      std::vector<char *> argv(arguments.count + 1, nullptr);
      char *position = storage.data();
      for (NSUInteger index = 0; index < arguments.count; ++index) {
        const char *value = arguments[index].UTF8String;
        size_t length = strlen(value) + 1;
        memcpy(position, value, length);
        argv[index] = position;
        position += length;
      }
      // node_start blocks this dedicated thread; it never execs a subprocess.
      const int code = node_start((int)arguments.count, argv.data());
      dispatch_async(dispatch_get_main_queue(), ^{ completion(code); });
    }
  }];
  thread.name = @"dsh.ios.embedded-node";
  thread.stackSize = 4 * 1024 * 1024;
  [thread start];
  return YES;
}
@end
