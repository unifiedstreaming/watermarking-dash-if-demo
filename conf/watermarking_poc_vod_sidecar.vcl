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
import http;
import xbody;
import urlplus; // Seems to work only with req.rul
import str;

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "{{TARGET_HOST}}";
    .port = "{{TARGET_PORT}}";
}

sub vcl_init
{
  new db = kvstore.init();
  ## Set the default 2nd subdirectories of the know A/B variants
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
}

// Returns the value req.http.X-key form the table based on req.http.X-key
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
  // return req.http.X-Foo or ""
}

sub vcl_recv {
  std.log("**** Starts vcl_recv ****");
  set req.ttl = 10s;
  set req.grace = 0s;
  set req.http.X-Request-ID = utils.fast_random_int(999999999);

  # Harcoded VM pattern at the momment ONLY for testing purposes.
  # set req.http.pattern = "0110111011";
  # set req.http.pattern = "1111111111";
  # set req.http.pattern = "0101010101";
  set req.http.pattern = "1010101010";

  std.log("req.http.pattern: " + req.http.pattern);
  if (!req.http.pattern)
  {
    return(synth(400, "WM Pattern not found in the request Header"));
  }

  // Store Varnish's local (backend) address for later use
  set req.http.X-host-url = http.varnish_url("/");
  std.log("req.restarts: " + req.restarts);
  std.log("req.http.x-state: " + req.http.x-state);
  std.log("req.url: " + req.url);

  if (req.restarts == 0){
    set req.http.init-url = req.url;
    # Provide a default variant A for first request
    if (urlplus.get_extension() ~ "mpd|dash|m4s|m3u8" && req.url !~ "default-green"
      && req.url ~ "vod"
    ) {
      urlplus.url_add("default-green", keep=1, position=1);
      urlplus.write();
      std.log("req.http.url-add: " + req.url);
    }
    else {
      set req.http.x-state = "valid";
    }
  }
  elseif (req.restarts == 1 && req.http.x-state == "backend_check")
  {
    std.log("**** Get side-car file ****");
    std.log("req.http.side-car-url: " + req.http.side-car-url);
    set req.url = req.http.side-car-url;
  }
  elseif (req.restarts == 2 && req.http.x-state == "set_position")
  {
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
    }
    else
    {
      return(synth(400, "WM position cannot be lower than -1"));
    }

    std.log("req.http.variant: " + req.http.variant);
    std.log("req.url: " + req.url);
    # Get the subdirectory of the random key int (0/1)
    set req.http.X-key = req.http.variant;
    call get_value_table;
    if (req.http.X-Foo != "" && req.http.variant != "")
    {
      std.log("req.http.init-url: " + req.http.init-url);
      std.log("Choosen A/B: " + req.http.X-Foo);

      ## Use urlplus vmod to add the value from kvstore as a subdirectory
      ## in the incoming URL
      ## For example:
      # Incoming URL: /vod/roll.ism/dash/foo=10-132.m4s
      # to
      # Updated  URL: /vod/${kvstore-value}/roll.ism/dash/foo=10-132.m4s
      set req.url = req.http.init-url;
      urlplus.url_add(req.http.X-Foo, keep=1, position=1);
      # urplus.write() will automatically modify req.url
      urlplus.write();
      std.log("req.http.url-add: " + req.url);
      set req.http.x-variant = req.http.X-Foo;
      set req.http.x-state = "valid";
    }
  }

  std.log("**** Ends vcl_recv ****");
}

sub vcl_backend_fetch {
  std.log("**** Starts vcl_backend_fetch ****");
  std.log("bereq.url: " + bereq.url);
  std.log("bereq.method: " + bereq.method);
  std.log("**** Ends vcl_backend_fetch ****");
}

sub vcl_backend_response {
  std.log("**** Starts vcl_backend_response ****");
    set beresp.ttl = 10s;
    set beresp.grace = 0s;
    std.log("urlplus.get_extension(): " + urlplus.get_extension());
    if (urlplus.get_extension() ==  "json"){
        std.log("Is a json file");
        xbody.capture("name", "(.*)", "\1"); # capture all
        xbody.capture("position", ".*\x22position\x22:([0-9]+|-[0-9]+)", "\1");
        set beresp.http.x-state = "set_position";
    }

    # TODO: It should have a flag to enable or disable side car file
    std.log("beresp.http.Content-Type: " + beresp.http.Content-Type);
    if (bereq.url !~ "WMPaceInfo" && beresp.http.Content-Type ~ "video/mp4"
      && bereq.http.x-state != "valid")
    {
        // Rename the URL to th epath of the side-car
        if (urlplus.get_extension() == "m4s")
        {
          std.log("Tyring to replace .m4s to .json extension");
          set bereq.http.X-side-car = regsub(bereq.url, "(.*).m4s$", "\1.json");

        }
        elseif (urlplus.get_extension() == "dash")
        {
          std.log("Tyring to replace .dash to .json extension");
          set bereq.http.X-side-car = regsub(bereq.url, "(.*).dash$", "\1.json");

        }

        std.log("bereq.url: " + bereq.url);
        std.log("bereq.http.X-side-car: " + bereq.http.X-side-car);
        # Insert the WMPaceinfo virtual path WMPaceInfo in the second position
        # (/vod)(/2nd position)(rest of the URL).
        set bereq.http.X-side-car = regsub(bereq.http.X-side-car, "(\/.*?\/)(.*.json$)", "\1WMPaceInfo/\2");
        # std.log("bereq.http.X-side-car: " + bereq.http.X-side-car);
        # Add the host address that was saved
        # To use http.req_set-url it requires the full url including the host
        # address.
        set bereq.http.X-side-car = regsub(bereq.http.X-host-url, "/$", bereq.http.X-side-car);
        std.log("bereq.http.X-side-car: " + bereq.http.X-side-car);

        # We generate a prefetch subrequest in the background of the side-car
        # http.init(0);
        # http.req_copy_headers(0);
        # http.req_set_url(0, bereq.http.X-side-car);
        # http.req_send_and_finish(0);
        set beresp.http.x-state = "backend_check";
        set beresp.http.side-car-url = bereq.http.X-side-car;
    }
  std.log("**** Ends vcl_backend_response ****");
}

sub vcl_deliver {
  std.log("**** Starts vcl_deliver ****");
    # Check the values from the side-car file as a separate file
  std.log("resp.http.x-state: " + resp.http.x-state);

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
  std.log("Name: " + xbody.get("name"));
  std.log("Position: " + xbody.get("position"));
  set resp.http.wm-position = xbody.get("position");
  std.log("Capture JSON: " + xbody.get_all());

  # First mak sure that the state is valid to not loop infinietely
  if (req.http.x-state == "valid")
  {
    set resp.http.x-state = "valid";
  }

  std.log("resp.http.x-state: " + resp.http.x-state);
  if (resp.http.x-state == "backend_check")
  {
    set req.http.x-state = resp.http.x-state;
    set req.http.side-car-url = resp.http.side-car-url;
    return (restart);
  }
  elseif(resp.http.x-state == "set_position")
  {
    set req.http.x-state = resp.http.x-state;
    std.log("vcl_deliver Position: " + xbody.get("position"));
    set req.http.position = xbody.get("position");
    return (restart);
  }

  unset resp.http.Cache-Control;
  set resp.http.file = "watermarking_poc_vod_sidecar.vcl";
  std.log("**** Ends vcl_deliver ****");

}
