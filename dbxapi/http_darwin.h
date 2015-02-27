#include <Foundation/Foundation.h>

NSString* encode_uri_component(NSString *string, NSStringEncoding encoding=NSUTF8StringEncoding);
NSString* encode_uri_path(NSString *string, NSStringEncoding encoding=NSUTF8StringEncoding);

typedef void(^RXHTTPRequestContinuation)(NSError*,NSData*,NSHTTPURLResponse*);

extern NSError* RXHTTPRequestCanceledError;
extern NSInteger RXHTTPRequestCanceledErrorCode;

@interface RXHTTPRequest : NSObject

+ (RXHTTPRequest*)GET:(NSString*)url callback:(RXHTTPRequestContinuation)cb;
+ (RXHTTPRequest*)GET:(NSString*)url params:(NSDictionary*)params callback:(RXHTTPRequestContinuation)cb;
+ (RXHTTPRequest*)POST:(NSString*)url formParams:(NSDictionary*)params callback:(RXHTTPRequestContinuation)cb;

- (void)cancel;

@end

@interface NSDictionary (RXHTTP_Additions)
@property (readonly) NSString* URIQueryString;
  // Returns a string suitable for appending to a URL.
  // I.e. @{@"a": @"Adam?", @"b": @"Bob/Bobby"} -> @"a=Adam%3F&b=Bob%2FBobby"
@end
