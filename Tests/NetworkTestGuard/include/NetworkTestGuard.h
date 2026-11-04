#import <Foundation/Foundation.h>
@interface GravityTestNetworkGuard : NSURLProtocol
+ (NSArray<NSString *> *)violations;
@end
