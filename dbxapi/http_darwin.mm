#import "http_darwin.h"

//#define NSDBG(...) NSLog(__VA_ARGS__)
#define NSDBG(...) ((void)0)


static NSString * const kEscapeURIComponent = @":/?&=;+!@#$()',*";
static NSString * const kEscapeURIPath = @":?&=;+!@#$()',*";

//static NSString* decode_uri_component(NSString *string, NSStringEncoding encoding=NSUTF8StringEncoding) {
//  static NSString * const kQSEscapeExcludedCharacters = @"[].";
//	return (__bridge_transfer  NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)string, (__bridge CFStringRef)kQSEscapeExcludedCharacters, (__bridge CFStringRef)kQSEscapeCharacters, CFStringConvertNSStringEncodingToEncoding(encoding));
//}

NSString* encode_uri_component(NSString *string, NSStringEncoding encoding) {
	return (__bridge_transfer  NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)string, NULL, (__bridge CFStringRef)kEscapeURIComponent, CFStringConvertNSStringEncodingToEncoding(encoding));
}

NSString* encode_uri_path(NSString *string, NSStringEncoding encoding) {
  return (__bridge_transfer  NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)string, NULL, (__bridge CFStringRef)kEscapeURIPath, CFStringConvertNSStringEncodingToEncoding(encoding));
}

NSError* RXHTTPRequestCanceledError = nil;
NSInteger RXHTTPRequestCanceledErrorCode = 1;

static void __attribute__((constructor)) __init() {
  RXHTTPRequestCanceledError = [NSError errorWithDomain:@"RXHTTP" code:RXHTTPRequestCanceledErrorCode userInfo:@{NSLocalizedDescriptionKey:@"request was canceled"}];
}


@interface RXHTTPRequest ()
@property (copy) RXHTTPRequestContinuation callback;
@end


@implementation NSDictionary (RXHTTP_Additions)
- (NSString*)URIQueryString {
  NSMutableString* s = [NSMutableString new];
  __block int c = 0;
  [self enumerateKeysAndObjectsUsingBlock:^(NSString* key, id value, BOOL *stop) {
    if ([value isEqual:[NSNull null]]) {
      if (c++) {
        [s appendString:@"&"];
      }
      [s appendString:encode_uri_component(key)];
    } else {
      [s appendFormat:(c++ ? @"&%@=%@" : @"%@=%@"),
       encode_uri_component(key), encode_uri_component([value description])];
    }
  }];
  return s;
}
@end


@implementation RXHTTPRequest {
  NSHTTPURLResponse* _response;
  NSMutableData* _data;
  NSURLConnection* _connection;
  RXHTTPRequest* _selfRef;
}

@synthesize callback = _callback;

- (id)initWithURLRequest:(NSURLRequest*)urlRequest {
  if (!(self = [super init])) return nil;
  _connection = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self startImmediately:NO];
  return self;
}

-(void)dealloc {
  NSDBG(@"%@%@ _connection=%p", self, NSStringFromSelector(_cmd), _connection);
  if (_connection != nil) {
    [self cancel];
  }
}

- (void)callCallbackWithError:(NSError*)error {
  NSDBG(@"%@%@ error=%@", self, NSStringFromSelector(_cmd), error);
  assert(_callback != nil);
  _callback(error, _data, _response);
  _data = nil;
  _response = nil;
  _connection = nil;
  _selfRef = nil;
}

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response {
  _data = [[NSMutableData alloc] init]; // _data being an ivar
  _response = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)response : nil;
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data {
  NSDBG(@"%@%@ connection=%@ data=%@", self, NSStringFromSelector(_cmd), connection, data);
  [_data appendData:data];
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)error {
  NSDBG(@"%@%@ connection=%@ error=%@", self, NSStringFromSelector(_cmd), connection, error);
  [self callCallbackWithError:error];
}

- (void)connectionDidFinishLoading:(NSURLConnection*)connection {
  NSDBG(@"%@%@ connection=%@", self, NSStringFromSelector(_cmd), connection);
  [self callCallbackWithError:nil];
}

- (void)send {
  NSDBG(@"%@%@", self, NSStringFromSelector(_cmd));
  assert(_selfRef == nil);
  _selfRef = self;
  [_connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
  [_connection start];
}

- (void)cancel {
  NSDBG(@"%@%@", self, NSStringFromSelector(_cmd));
  if (_connection) {
    [_connection cancel];
    [self callCallbackWithError:RXHTTPRequestCanceledError];
  } else if (_selfRef != nil) {
    _selfRef = nil;
  }
}

//- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
//
//- (NSInputStream *)connection:(NSURLConnection *)connection needNewBodyStream:(NSURLRequest *)request;
//- (void)connection:(NSURLConnection *)connection   didSendBodyData:(NSInteger)bytesWritten
// totalBytesWritten:(NSInteger)totalBytesWritten
//totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite;
//
//- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse;
//


#if 0
#define kMultipartBoundary \
  "--magiclolcatZEiWPyIPjLf9CbWdoChgHhHiM8aFPsKTUqMlePxBRMvgd"

static NSData* multipart_encode(NSDictionary* params) {
  NSMutableData* data = [NSMutableData new];
  
  auto append = [&data](const char* pch) {
    [data appendBytes:(const void *)pch length:strlen(pch)];
  };

  [params enumerateKeysAndObjectsUsingBlock:^(NSString* key, id obj, BOOL *stop) {
    NSData* value;
    if ([obj isKindOfClass:[NSData class]]) {
      value = obj;
    } else if ([obj isEqual:[NSNull null]]) {
      value = [NSData data];
    } else {
      value = [[obj description] dataUsingEncoding:NSUTF8StringEncoding];
    }
    
    append(kMultipartBoundary);
    append("\r\n");
    
    append("Content-Disposition: form-data; name=\"");
    append([key stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""].UTF8String);
    append("\"\r\n");
    
    //append([NSString stringWithFormat:@"Content-Length: %lu\r\n", (unsigned long)value.length].UTF8String);
    
    // append("Content-Type: text/plain\r\n");
    // append("Content-Transfer-Encoding: binary\r\n");
    
    append("\r\n");
    [data appendData:value];
    append("\r\n");
  }];
  
  append(kMultipartBoundary "--\r\n\r\n");
  
  return data;
}
#endif


+ (RXHTTPRequest*)POST:(NSString*)url formParams:(NSDictionary*)params callback:(RXHTTPRequestContinuation)cb {
  NSMutableURLRequest* urlreq = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:1e10];
  urlreq.HTTPMethod = @"POST";
  urlreq.HTTPShouldHandleCookies = NO;

//  NSData* body = multipart_encode(params);
//  urlreq.HTTPBody = body;
//  [urlreq setValue:[NSString stringWithUTF8String:("multipart/form-data; boundary=" kMultipartBoundary)] forHTTPHeaderField:@"Content-Type"];
//  [urlreq setValue:[NSString stringWithFormat:@"%lu", (unsigned long)body.length] forHTTPHeaderField:@"Content-Length"];

  NSData* body = [params.URIQueryString dataUsingEncoding:NSUTF8StringEncoding];
  urlreq.HTTPBody = body;
  [urlreq setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
  [urlreq setValue:[NSString stringWithFormat:@"%lu", (unsigned long)body.length] forHTTPHeaderField:@"Content-Length"];
  
  RXHTTPRequest* req = [[RXHTTPRequest alloc] initWithURLRequest:urlreq];
  req.callback = cb;
  [req send];
  return req;
}

+ (RXHTTPRequest*)GET:(NSString*)url callback:(RXHTTPRequestContinuation)cb {
  // cachePolicy:(NSURLRequestCachePolicy)cachePolicy timeoutInterval:(NSTimeInterval)timeoutInterval;
  RXHTTPRequest* req = [[RXHTTPRequest alloc] initWithURLRequest:[[NSURLRequest alloc] initWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:1e10]];
  req.callback = cb;
  [req send];
  return req;
}

+ (RXHTTPRequest*)GET:(NSString*)url params:(NSDictionary*)params callback:(RXHTTPRequestContinuation)cb {
  return [RXHTTPRequest GET:[url stringByAppendingFormat:@"?%@", params.URIQueryString] callback:cb];
}

@end
