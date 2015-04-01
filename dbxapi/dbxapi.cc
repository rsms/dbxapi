#import "dbxapi.hh"
namespace dbxapi {

Config config{
  .apiURL = "https://api.dropbox.com/1",
  .apiNotifyURL = "https://api-notify.dropbox.com/1",
};


static auto wrapJsonCallback(rx::func<void(Status, Json)> cb) {
  return [cb](Status st, string data) {
    if (!st.ok()) {
      cb(st, nullptr);
    } else {
      string err;
      auto json = Json::parse(data, err);
      if (json != nullptr && json["error"] != nullptr) {
        // Some API endpoints will happily return an error with a "OK" protocol status code  :-/
        cb(Status{json["error"].string_value()}, std::move(json));
      } else {
        // JSON parsing might have failed, otherwise we're a go  :-)
        cb((json == nullptr ? Status{err} : Status::OK()), std::move(json));
      }
    }
  };
}


void GET(const string& path, const Params& params, rx::func<void(Status, Json)> cb) {
  return GET_raw(path, params, wrapJsonCallback(cb));
}


void POST(const string& path, const Params& params, rx::func<void(Status, Json)> cb) {
  return POST_raw(path, params, wrapJsonCallback(cb));
}


void delta_get(
   const string& access_token,
   const string& path_prefix,
   const string& cursor,
   rx::func<void(Status, Json)> cb)
{
  Params params{
    {"access_token", access_token},
    {"path_prefix",  path_prefix},
  };
  if (!cursor.empty()) {
    params.emplace("cursor", cursor);
  }
  POST("/delta", params, cb);
}


void delta_wait(
    const string& access_token,
    const string& cursor,
    rx::func<void(Status, Json)> cb)
{
  assert(!cursor.empty());
  GET("/longpoll_delta", {
    {"access_token", access_token},
    {"cursor",       cursor},
    {"timeout",      "480"},
  }, cb);
}


} // namespace
