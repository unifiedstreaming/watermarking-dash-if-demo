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

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "{{TARGET_HOST}}";
    .port = "{{TARGET_PORT}}";
}

sub vcl_init{
  new db = kvstore.init();
  ## Set the default 2nd subdirectories of the know A/B variants
  ## Set a binary pattern mapping
  db.set(0, "default-blue", 30d);
  db.set(1, "default-green", 30d);

  # Example ABC pattern mapping
  db.set("a", "default-green", 30d);
  db.set("b", "default-blue", 30d);
  db.set("c", "default-green", 30d);
  db.set("d", "default-blue", 30d);
  db.set("e", "default-green", 30d);
  db.set("f", "default-blue", 30d);
  db.set("g", "default-green", 30d);
  db.set("h", "default-blue", 30d);
  db.set("i", "default-green", 30d);
  db.set("j", "default-blue", 30d);

  new jwt_reader = jwt.reader();
}

#include "/etc/varnish/develop/conf/jwt_verify.vcl";

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
sub get_wm_pattner_from_token {
  std.log("Enters get_wm_pattner_from_token() ");

  set req.http.url-token = urlplus.url_get(start_range=1, end_range=1);
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

  # TODO: Set a condition if the token is empty
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
  set req.http.url-token = urlplus.url_get(start_range=1, end_range=1);
  urlplus.url_delete_range(start_range=1, end_range=1);
  urlplus.write();
  std.log("NO token URL: " + req.url);
}

sub vcl_recv {
  std.log("Enters vcl_recv ");
  set req.ttl = 10s;
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
  # call verify_jwt;

  # URL example: /vod/${TOKEN}/request_file -> /vod/request_file
  # Remove TOKEN and extract wm pattern from TOKEN
  call get_wm_pattner_from_token;
  ## Because we do not want the player the full URLs of variant A/B,
  ## we need to append the path of variant A/B in the MPD.
  ## Provide one of the A/B variants to select an MPD
  # URL example: /vod/variant-a|variant-b/file
  set req.http.extension = urlplus.get_extension();
  std.log("req.http.extension: " + req.http.extension);

  if (req.http.extension ~ "mpd|dash") {
    urlplus.url_add("default-green", keep=1, position=1);
    # urplus.write() will automatically modify req.url
    urlplus.write();
    std.log("req.http.url-add: " + req.url);
  }
  ## Extract segment number and set it as HTTP request Header
  ## TODO: # Replace if conditions with urlplus.get_extension()
  elseif (req.http.extension ~ "m4s")
  {
    ## NOTE: This only applies to DASH SegmentNumber
    ## Example:
    # Capture the  segment number between after `-` and until the extension (`.`).
    # roll.ism/dash/Density_Pepijn_v3-origin04_combined-c-m1-pre-roll-video=2187000-321.m4s
    # In this case the value would be the string "321"
    set req.http.segment-number = regsub(req.url, ".*-([0-9]+).m4s", "\1");
    std.log("req.http.segment-number: " + req.http.segment-number);

    # Harcoded VM pattern at the momment ONLY for testing purposes.
    # set req.http.pattern = "abcdefghij";
    # set req.http.pattern = "0110111011";
    # set req.http.pattern = "0101010101";

    # Return Error if WM Pattern was not found
    if (!req.http.pattern)
    {
      return(synth(400, "WM Pattern not found in the request Header"));
    }

    # Requirements:
    # - The client must provide the segment id
    # - The client must provide the WM pattern
    # position = segment_number % wm_length
    set req.http.position = utils.mod(std.integer(req.http.segment-number, 0), str.len(req.http.pattern));
    std.log("req.http.position: " + req.http.position);
    ## variant = vm_pattern[position]
    set req.http.variant = str.substr(req.http.pattern, 1, std.integer(req.http.position, 0));
    std.log("req.http.variant: " + req.http.variant);

    ## Create a random selection of A/B variant (0/1)
    set req.http.random-a-b = req.http.variant;

    std.log("random A/B: " + req.http.random-a-b);
    set req.http.X-key = req.http.random-a-b;

    # Get the subdirectory of the random key int (0/1)
    call get_value_table;

    # Do not modify the URL if the random (0/1) mataches the incoming URL
    if (req.http.X-Foo != "")
    {
      std.log("random A/B: " + req.http.X-Foo);

      ## Use urlplus vmod to add the value from kvstore as a subdirectory
      ## in the incoming URL
      ## For example:
      # Incoming URL: /vod/roll.ism/dash/foo=10-132.m4s
      # to
      # Updated  URL: /vod/${kvstore-value}/roll.ism/dash/foo=10-132.m4s

      urlplus.url_add(req.http.X-Foo, keep=1, position=1);
      # urplus.write() will automatically modify req.url
      urlplus.write();
      std.log("req.http.url-add: " + req.url);
      set req.http.x-variant = req.http.X-Foo;
    }
  }
}

sub vcl_backend_fetch {
    std.log("**** Starts vcl_backend_fetch ****");
}



sub vcl_backend_response {
    std.log("Enters vcl_backend_response ");
    set beresp.ttl = 10s;
    set beresp.grace = 1s;
}

sub vcl_deliver {

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
    set resp.http.file = "watermarking_poc.vcl";

    # Copy the headers back to the client
    set resp.http.position = req.http.position;
    set resp.http.variant = req.http.variant;
    ## The subdirectory of the content from the selected variant
    set resp.http.x-variant = req.http.x-variant;
    set resp.http.jwt-json = req.http.jwt-json;
    set resp.http.jwt-json-url = req.http.jwt-json-url;
    set resp.http.pattern = req.http.pattern;
}
