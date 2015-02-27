#pragma once
#import <rx/rx.h>
#import <rx/status.hh>
#import <json11/json11.hh>
#import <map>
namespace dbxapi {

using json11::Json;
using rx::Status;
using std::string;

enum StatusCode : Status::Code {
  StatusCodeNotConnected = 1,       // No route to host
  StatusCodeTimeout,                // Idle timeout (not API timeout)
  StatusCodeAPIRequestError,        // HTTP equiv. 4xx
  StatusCodeAPIRequestUnauthorized, // Bad or expired access_token. Need to reauthenticate.
  StatusCodeAPIRequestRateLimit,    // Request rate limited. Status.message() = seconds to wait.
  StatusCodeAPIServerError,         // HTTP equiv. 5xx
  StatusCodeResponseError,          // Invalid HTTP message, broken pipe, etc
  StatusCodeConnectionError,        // SSL failure, TCP handshake failure, etc
};

using Params = std::map<string,string>;

// GET an arbitrary API endpoint
void GET(const string& path, const Params&, rx::func<void(Status, Json)>);
void GET_raw(const string& path, const Params&, rx::func<void(Status, string)>);

// POST to an arbitrary API endpoint with params as form-url-encoded data.
void POST(const string& path, const Params&, rx::func<void(Status, Json)>);
void POST_raw(const string& path, const Params&, rx::func<void(Status, string)>);


// Retrieve change delta.
// API endpoint equivalent: POST /delta
void delta_get(
  const string& access_token,
  const string& path_prefix,
  const string& cursor,
  rx::func<void(Status, Json)> cb);

// Wait for changes.
// API endpoint equivalent: GET /longpoll_delta
void delta_wait(
  const string& access_token,
  const string& cursor,
  rx::func<void(Status, Json)> cb);

} // namespace
