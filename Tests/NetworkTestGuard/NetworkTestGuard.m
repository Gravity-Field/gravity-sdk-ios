#import "NetworkTestGuard.h"
#import <objc/runtime.h>

static NSURLSessionConfiguration *(*originalDefault)(id, SEL);
static NSURLSessionConfiguration *(*originalEphemeral)(id, SEL);
static NSURLSessionConfiguration *guardConfiguration(NSURLSessionConfiguration *configuration) {
    configuration.protocolClasses = [@[GravityTestNetworkGuard.class] arrayByAddingObjectsFromArray:configuration.protocolClasses ?: @[]];
    return configuration;
}
static NSURLSessionConfiguration *guardDefault(id receiver, SEL selector) { return guardConfiguration(originalDefault(receiver, selector)); }
static NSURLSessionConfiguration *guardEphemeral(id receiver, SEL selector) { return guardConfiguration(originalEphemeral(receiver, selector)); }
@implementation GravityTestNetworkGuard
+ (void)load {
    [NSURLProtocol registerClass:self];
    // URLSession(config:) does not consistently use globally registered protocols.
    // This swizzle exists only in the test dependency, never in the SDK product.
    Method method = class_getClassMethod(NSURLSessionConfiguration.class, @selector(defaultSessionConfiguration));
    originalDefault = (void *)method_setImplementation(method, (IMP)guardDefault);
    method = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
    originalEphemeral = (void *)method_setImplementation(method, (IMP)guardEphemeral);
}
+ (NSMutableArray<NSString *> *)records {
    static NSMutableArray *records;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ records = [NSMutableArray new]; });
    return records;
}
+ (NSArray<NSString *> *)violations { @synchronized(self) { return [[self records] copy]; } }
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *host = request.URL.host.lowercaseString;
    return host.length > 0 && ![@[@"localhost", @"127.0.0.1", @"::1", @"[::1]"] containsObject:host];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    @synchronized([self class]) { [[[self class] records] addObject:self.request.URL.host ?: @"unknown"]; }
    NSLog(@"TEST NETWORK GUARD blocked non-local host: %@", self.request.URL.host);
    NSData *payload = self.request.HTTPBody;
    if (!payload && self.request.HTTPBodyStream) {
        NSInputStream *stream = self.request.HTTPBodyStream;
        [stream open];
        NSMutableData *data = [NSMutableData new];
        uint8_t buffer[4096];
        NSInteger count;
        while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0) { [data appendBytes:buffer length:(NSUInteger)count]; }
        [stream close];
        payload = data;
    }
    id json = payload ? [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil] : nil;
    NSString *message = [json isKindOfClass:NSDictionary.class] && [json[@"message"] isKindOfClass:NSString.class] ? json[@"message"] : @"";
    [NSNotificationCenter.defaultCenter postNotificationName:@"GravityTestNetworkGuardBlocked" object:self.request.URL.host userInfo:@{@"message": message}];
    // Diagnostics are captured successfully to avoid recursive/retry noise; nothing leaves this protocol.
    if ([self.request.URL.host isEqualToString:@"sdk-sentry.gravityfield.ai"]) {
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:nil headerFields:nil];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
        [self.client URLProtocolDidFinishLoading:self];
    } else {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
    }
}
- (void)stopLoading {}
@end
