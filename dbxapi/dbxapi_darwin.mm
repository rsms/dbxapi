#import <json11/json11.hh>
#import "dbxapi.hh"
#import "http_darwin.h"
#import <iostream>
#import <Foundation/Foundation.h>

//#define DBXAPI_DEBUG 1

#ifndef DBXAPI_DEBUG
#define DBXAPI_DEBUG 0
#endif

namespace dbxapi {

using std::clog;
using std::endl;


static Status StatusFromNSError(NSError* error) {
  NSInteger c = error.code;
  if (error.domain == NSURLErrorDomain || [error.domain isEqualToString:NSURLErrorDomain]) {
    switch (c) {
    case kCFURLErrorCannotFindHost:
    case kCFURLErrorCannotConnectToHost:
    case kCFURLErrorNetworkConnectionLost:
    case kCFURLErrorDNSLookupFailed:
    case kCFURLErrorNotConnectedToInternet:
    case kCFURLErrorInternationalRoamingOff:
    case kCFURLErrorCallIsActive:
    case kCFURLErrorDataNotAllowed:
      return Status{StatusCodeNotConnected, error.localizedDescription.UTF8String};

    case kCFURLErrorTimedOut:
      return Status{StatusCodeTimeout, error.localizedDescription.UTF8String};

    case kCFURLErrorRedirectToNonExistentLocation:
    case kCFURLErrorBadServerResponse:
    case kCFURLErrorCannotDecodeRawData:
    case kCFURLErrorCannotDecodeContentData:
    case kCFURLErrorCannotParseResponse:
      return Status{StatusCodeResponseError, error.localizedDescription.UTF8String};

    case kCFURLErrorSecureConnectionFailed:
    case kCFURLErrorServerCertificateHasBadDate:
    case kCFURLErrorServerCertificateUntrusted:
    case kCFURLErrorServerCertificateHasUnknownRoot:
    case kCFURLErrorServerCertificateNotYetValid:
    case kCFURLErrorClientCertificateRejected:
    case kCFURLErrorClientCertificateRequired:
    case kCFURLErrorCannotLoadFromNetwork:
      return Status{StatusCodeConnectionError, error.localizedDescription.UTF8String};
    }
  }
  return Status{[NSString stringWithFormat:@"%@ (underlying error code: %ld)", error.localizedDescription, (long)c].UTF8String};
}


static void dbx_parse_api_response(
  NSError* error,
  NSData* data,
  NSHTTPURLResponse* res,
  rx::func<void(Status, string)> cb)
{
  if (error) {
    auto st = StatusFromNSError(error);
    cb(st, string{});

  } else if (res.statusCode == 429 || res.statusCode == 503) {
    // Rate limit
    NSObject* retryAfter = res.allHeaderFields[@"Retry-After"];
    cb(Status{StatusCodeAPIRequestRateLimit, retryAfter.description.UTF8String}, string{});

  } else {
    string datastr{(const char*)data.bytes, data.length};
    if (res.statusCode < 200 || res.statusCode > 299) {
      // protocol error  :-(
      Status::Code c =
        res.statusCode == 401 ? StatusCodeAPIRequestUnauthorized :
        res.statusCode >= 400 && res.statusCode < 500 ? StatusCodeAPIRequestError :
        res.statusCode >= 500 && res.statusCode < 600 ? StatusCodeAPIServerError :
        0;
      string err;
      auto json = Json::parse(datastr, err);
      if (json.is_null() || !json["error"].is_string()) {
        cb(Status{c, datastr}, string{});
      } else {
        cb(Status{c, json["error"].string_value()}, string{});
      }

    } else {
      // probably successful  :-S
      cb(Status::OK(), std::move(datastr));
    }
  }
}


static NSDictionary* NSDictionaryFromParams(const Params& params) {
  auto* nsparams = [NSMutableDictionary new];
  for (auto& p : params) {
    auto* k = [[NSString alloc] initWithBytes:(const void*)p.first.data() length:p.first.size() encoding:NSUTF8StringEncoding];
    auto* v = [[NSString alloc] initWithBytes:(const void*)p.second.data() length:p.second.size() encoding:NSUTF8StringEncoding];
    nsparams[k] = v;
  }
  return nsparams;
}


static NSString* urlForPath(const string& path) {
  auto nspath = encode_uri_path([[NSString alloc] initWithBytesNoCopy:(void*)path.data() length:path.size() encoding:NSUTF8StringEncoding freeWhenDone:NO]);
  return [NSString stringWithFormat:@"%s%@", (path == "/longpoll_delta" ? config.apiNotifyURL : config.apiURL).c_str(), nspath];
}


void GET_raw(const string& path, const Params& params, rx::func<void(Status, string)> cb) {
  auto url = urlForPath(path);
  auto nsparams = NSDictionaryFromParams(params);
  #if DBXAPI_DEBUG
  clog << "[dbxapi] request GET " << url.UTF8String << " params="
       << nsparams.description.UTF8String
       << endl;
  #endif
  [RXHTTPRequest GET:url
              params:nsparams
            callback:^(NSError* error, NSData* data, NSHTTPURLResponse* res)
  {
    #if DBXAPI_DEBUG
    auto* dataAsString = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    clog << "[dbxapi] response GET " << url.UTF8String << " params="
         << nsparams.description.UTF8String << "\n"
         << "  error: " << (error ? error.description.UTF8String : "nil") << "\n"
         << "  data:  "
         << (data ? (dataAsString ? dataAsString.description : data.description).UTF8String : "nil") << "\n"
         << "  res:   " << (res == nil ? "nil" : res.description.UTF8String)
         << endl;
    #endif
    dbx_parse_api_response(error, data, res, std::move(cb));
  }];
}


void POST_raw(const string& path, const Params& params, rx::func<void(Status, string)> cb) {
  auto url = urlForPath(path);
  auto nsparams = NSDictionaryFromParams(params);
  #if DBXAPI_DEBUG
  clog << "[dbxapi] request POST " << url.UTF8String << " params="
       << nsparams.description.UTF8String
       << endl;
  #endif
  [RXHTTPRequest POST:url
           formParams:nsparams
             callback:^(NSError* error, NSData* data, NSHTTPURLResponse* res)
  {
    #if DBXAPI_DEBUG
    auto* dataAsString = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    clog << "[dbxapi] response POST " << url.UTF8String << " params="
         << nsparams.description.UTF8String << "\n"
         << "  error: " << (error ? error.description.UTF8String : "nil") << "\n"
         << "  data:  "
         << (data ? (dataAsString ? dataAsString.description : data.description).UTF8String : "nil") << "\n"
         << "  res:   " << (res == nil ? "nil" : res.description.UTF8String)
         << endl;
    #endif
    dbx_parse_api_response(error, data, res, std::move(cb));
  }];
}


} // namespace
