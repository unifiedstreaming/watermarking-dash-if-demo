# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide for a comprehensive documentation
# at https://www.varnish-cache.org/docs/.

# Marker to tell the VCL compiler that this VCL has been written with the
# 4.0 or 4.1 syntax.

vcl 4.1;

import utils;
import std;
import kvstore;
import str;
import urlplus;
import json;
import jwt;

include "/etc/varnish/accounting_metrics.vcl";

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "live-origin-a";
    .port = "80";
}

backend backend-b {
    .host = "live-origin-b";
    .port = "80";
}

sub vcl_init
{
  new db = kvstore.init();
  ## Set the default 2nd subdirectories of the know A/B variants
  db.set(0, "ingress-a", 30d);
  db.set(1, "ingress-b", 30d);

  new jwt_reader = jwt.reader();
  call accounting_vcl_init;
}

sub verify_jwt {
  # Considering that the Authorization Token comes as a virutal path
  set req.http.Authorization = urlplus.url_get(start_range=0, end_range=0);
  # remove trailing slash
  set req.http.Authorization = regsub(req.http.Authorization, "^\/(.*)$", "\1");
  set req.http.Authorization = "Bearer " + req.http.Authorization;
  std.log("req.http.Authorization: " + req.http.Authorization);
  # Verify that the token was correctly generated
  set req.http.bearer = regsub(req.http.Authorization,"^Bearer (.+)$","\1");
  std.log("req.http.bearer: " + req.http.bearer);

  if (!jwt_reader.parse(regsub(req.http.Authorization,"^Bearer (.+)$","\1"))) {
      return (synth(401, "Invalid token: Parsing"));
  }

  if(!jwt_reader.set_key("secret") || !jwt_reader.verify("HS256")) {
    return (synth(401, "Invalid token: Secret key or algorithm"));
  }
  set req.http.jwt-json = jwt_reader.get_payload();
}

sub get_value_table {
  std.log("**** Enters get_value_table ****");

  std.log("req.http.X-key: " + req.http.X-key);
  set req.http.X-Foo = db.get(req.http.X-key, "");

  if (req.http.X-Foo != "") {
      std.log("Found a key-value in db: " + req.http.X-Foo);
  }else
  {
      std.log("No value found for key: " + req.http.X-key);
  }
}

// Returns string req.http.jwt-json that needs to be used in delivery subroutine
// Sets the req.http.patthern in the form of 0/1 string.
sub get_wm_pattner_from_token {
  std.log("Enters get_wm_pattner_from_token() ");

  set req.http.url-token = urlplus.url_get(start_range=0, end_range=0);
  std.log("req.http.url-token: " + req.http.url-token);
  # Remove the leading slash when getting the token
  set req.http.url-token = regsub(req.http.url-token, "/(.*)", "\1");
  std.log("req.http.url-token: " + req.http.url-token);

  # Verify that the JWT token from the URL is valid
  if (!jwt_reader.parse(req.http.url-token)) {
      return (synth(401, "Invalid token: Parsing"));
  }

  if(!jwt_reader.set_key("secret") || !jwt_reader.verify("HS256")) {
    return (synth(401, "Invalid token: Secret key or algorithm"));
  }

  set req.http.jwt-json-url = jwt_reader.get_payload();

  json.parse(req.http.jwt-json-url);
  if (json.is_valid())
  {
    std.log("**** JSON parsing of WM Token is valid ****");
    set req.http.wmtoken-direct = json.get("wmtoken-direct");
    json.parse(req.http.wmtoken-direct);
    if (json.is_valid())
    {
      std.log("**** JSON parsing of WM pattern is valid ****");
      set req.http.pattern = json.get("304");

    }
    else {
      return (synth(401, "Invalid JSON parsing of the WM pattern"));
    }

  }
  else {
    return (synth(401, "Invalid JSON parsing of the WM token"));

  }
  std.log("req.http.pattern: " + req.http.pattern);
  set req.http.url-token = urlplus.url_get(start_range=0, end_range=0);
  urlplus.url_delete_range(start_range=0, end_range=0);
  urlplus.write();
  std.log("URL without WM Token: " + req.url);
}

sub vcl_recv {
  std.log("Enters vcl_recv ");
  set req.grace = 0s;
  set req.http.X-Request-ID = utils.fast_random_int(999999999);


  # Hack: Only forward GET and HEAD requests to the backend, otherwise
  # return an empty body with 202 status code. This mittigattes
  # requests with OPTIONS method going to the backend.
  if (req.method != "GET" && req.method != "HEAD") {
    return (synth(202));
  }

  std.log("req.http.User-Agent: " + req.http.User-Agent);
  set req.http.extension = urlplus.get_extension();
  std.log("req.http.extension: " + req.http.extension);

  # Return error if the jwt token is not found.
  # See jwt_verify.vcl.
  call verify_jwt;
  call get_wm_pattner_from_token;
  std.log("req.http.pattern: " + req.http.pattern);

  # URL example: /vod/${TOKEN}/request_file -> /vod/request_file
  # Remove TOKEN and extract wm pattern from TOKEN
  # call get_wm_pattern_from_token;
  ## Because we do not want the player the full URLs of variant A/B,
  ## we need to append the path of variant A/B in the MPD.
  ## Provide one of the A/B variants to select an MPD
  # URL example: /vod/variant-a|variant-b/file
  set req.http.extension = urlplus.get_extension();
  std.log("req.http.extension: " + req.http.extension);

  if (req.http.extension ~ "mpd") {
    urlplus.url_add("ingress-a", keep=1, position=0);
    # urplus.write() will automatically modify req.url
    urlplus.write();
    std.log("req.http.url-add: " + req.url);
  }
  ## Extract segment number and set it as HTTP request Header
  ## TODO: # Replace if conditions with urlplus.get_extension()
  elseif (req.http.extension ~ "m4s|dash")
  {
    ## NOTE: This only applies to DASH SegmentNumber
    ## Example:
    # Capture the  segment number between after `-` and until the extension (`.`).
    # roll.ism/dash/Density_Pepijn_v3-origin04_combined-c-m1-pre-roll-video=2187000-321.m4s
    # In this case the value would be the string "321"
    if (req.http.extension ~ "m4s"){
      set req.http.segment-number = regsub(req.url, ".*-([0-9]+).m4s", "\1");
      # Requirements:
      # - The client must provide the segment id
      # - The client must provide the WM pattern
      # position = segment_number % wm_length
      # set req.http.position = utils.mod(std.integer(req.http.segment-number, 0), str.len(req.http.pattern));
      set  req.http.position = req.http.segment-number;
      std.log("req.http.position: " + req.http.position);
      ## variant = vm_pattern[position]
      # set req.http.variant = str.substr(req.http.pattern, 1, std.integer(req.http.position, 0));
      # std.log("req.http.variant: " + req.http.variant);
    }
    elseif (req.http.extension ~ "dash"){
      set req.http.init-segment = regsub(req.url, ".*([0-9]+).dash", "\1");
      if (req.http.init-segment != ""){
        set req.http.position = -1;
        std.log("req.http.position: " + req.http.position);
      }
      else{
        return(synth(400, "Init segment not matched with regex."));
      }
    }
    std.log("req.http.segment-number: " + req.http.segment-number);
    std.log("req.http.init-segment: " + req.http.init-segment);

    # Harcoded VM pattern at the momment ONLY for testing purposes.
    # set req.http.pattern = "abcdefghij";
    # set req.http.pattern = "0110111011";
    # set req.http.pattern = "0101010101";
    # set req.http.pattern = "1010101010";

    # Return Error if WM Pattern was not found
    if (!req.http.pattern)
    {
      return(synth(400, "WM Pattern not found in the request Header"));
    }


    # Assing the correct Variant A/B
    std.log("Assing the correct Variant A/B");
    std.log("req.http.pattern: " + req.http.pattern);
    std.log("req.http.position: " + req.http.position);

    if (std.integer(req.http.position, -2) == -1 )
    {
      std.log("Segment does not require Watermark. Providing variant A ...");
      # Set the position in terms of the lenght of the WM pattern
      set req.http.variant = 0;
    }
    elseif (std.integer(req.http.position, -2) >= 0 )
    {
      # Set the position in terms of the lenght of the WM pattern
      set req.http.position-wm = utils.mod(std.integer(req.http.position, 0), str.len(req.http.pattern));
      set req.http.variant = str.substr(req.http.pattern, 1, std.integer(req.http.position-wm, 0));
      std.log("*** Applying Watermarking based on pattern position with MOD function ***");
      std.log("req.http.position-wm: " + req.http.position-wm);
      std.log("req.http.variant: " + req.http.variant);

    }
    else
    {
      return(synth(400, "WM position cannot be lower than -1"));
    }

    std.log("req.http.variant: " + req.http.variant);
    std.log("req.url: " + req.url);

    ## Create a random selection of A/B variant (0/1)
    set req.http.random-a-b = req.http.variant;
    set req.http.X-key = req.http.variant;

    # Get the subdirectory of the random key int (0/1)
    call get_value_table;

    # Do not modify the URL if the random (0/1) mataches the incoming URL
    if (req.http.X-Foo != "")
    {
      std.log("Choosen A/B: " + req.http.X-Foo);
      ## Use urlplus vmod to add the value from kvstore as a subdirectory
      ## in the incoming URL
      ## For example:
      # Incoming URL: /vod/roll.ism/dash/foo=10-132.m4s
      # to
      # Updated  URL: /vod/${kvstore-value}/roll.ism/dash/foo=10-132.m4s

      urlplus.url_add(req.http.X-Foo, keep=1, position=0);
      # urplus.write() will automatically modify req.url
      urlplus.write();

      std.log("req.http.host: " + req.http.host);
      std.log("req.url: " + req.url);
      if (req.http.X-Foo == "ingress-a") {
        set req.backend_hint = default;
      }
      elseif (req.http.X-Foo == "ingress-b") {
        set req.backend_hint = backend-b;
      }else {
        std.log("No value found for key: " + req.http.X-Foo);
        return(synth(400, "No backend found for req.http.X-Foo"));
      }

      std.log("req.http.url-add: " + req.url);
      set req.http.x-variant = req.http.X-Foo;
    }
  }
  call accounting_vcl_recv;
}

sub vcl_backend_fetch {
    std.log("**** Starts vcl_backend_fetch ****");
}



sub vcl_backend_response {
  std.log("Enters vcl_backend_response ");
  set beresp.grace = 0s;

  call accounting_vcl_backend_response;
  # std.log("beresp.http.Content-Type: " + beresp.http.Content-Type);
  # if (beresp.http.Content-Type == "application/dash+xml"){
  #     accounting.add_keys("mpd");
  #     std.log("accounting.add_keys(mpd)");
  # }elseif (beresp.http.Content-Type == "video/mp4"){
  #     accounting.add_keys("videomp4");
  #     std.log("accounting.add_keys(videomp4)");
  # }elseif (beresp.http.Content-Type == "application/json"){
  #     accounting.add_keys("json");
  #     std.log("accounting.add_keys(json)");
  # }
  # else{
  #     accounting.add_keys("generic");
  #     std.log("accounting.add_keys(generic)");
  # }
  std.log("**** Ends vcl_backend_response ****");
}

sub vcl_deliver {
    std.log("Enters vcl_deliver ");

    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    set resp.http.X-Request-ID = req.http.X-Request-ID;

    if(obj.ttl){
        # Show the seconds left the object ttl. Left = ttl - age
        std.log("obj.ttl: " + obj.ttl);
        set resp.http.ttl = obj.ttl;
    }
    unset resp.http.Cache-Control;
    set resp.http.file = "watermarking_live_setup_3.vcl";

    # Copy the headers back to the client
    set resp.http.position = req.http.position;
    set resp.http.variant = req.http.variant;
    ## The subdirectory of the content from the selected variant
    set resp.http.x-variant = req.http.x-variant;
    set resp.http.jwt-json = req.http.jwt-json;
    set resp.http.jwt-json-url = req.http.jwt-json-url;
    set resp.http.pattern = req.http.pattern;
    set resp.http.position-wm = req.http.position-wm;
    std.log("Ends vcl_deliver ");

}
