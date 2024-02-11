/*
  Generate JWT token to only MPEG-DASH MPD requests
*/


vcl 4.1;

import jwt;
import std;
import str;
import format;
import utils;
import urlplus; // Get extension file
import accounting;

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "{{TARGET_HOST}}";
    .port = "{{TARGET_PORT}}";
}


sub vcl_init {
  new jwt_writer = jwt.writer();
  new jwt_reader = jwt.reader();
}

# Include VCL function that verifies JWT token
include "/etc/varnish/jwt_verify.vcl";

sub add_jwt_payload {
  ## Generate and validate JWT token with a synthtic payload
  /*
  example_data = {
    "sub": "1234567890",
    "name": "John Doe",
    "iat": 1516239022
  }
  */
  /*
      ETSI TS 104 002 V1.1.1
      Table 1: Integer Claim key values for the WM token
      ====================================
      Claim label             Integer key
      ------------------------------------
      wmver-label             300
      wmvnd-label             301
      wmpatlen-label          302
      wmsegduration-label     303
      wmpattern-label         304
      wmid-label              305
      wmopid-label            306
      wmkeyver-label          3078
      ====================================
  */
  ## JWT token does not seem to accept integers as keys ... so we use strings
  ## for the momment

  # Selected WM pattern
  #set req.http.pattern = "0110111011";
  std.log("req.http.pattern: " + req.http.pattern );

  #--------------- Use format VMOD to build JSON payload----------------------#

  format.set({"{ "name":"%s","300":%d,"301":%d,"302":%d, "wmtoken-direct":{"304":%s}}"});

  # JWT name (only for identify each user)
  format.add_string("John Doe");
  # wmver-value
  format.add_int(1);
  # wmvnd-value
  format.add_int(1);
  # wmpatlen-value
  set req.http.wmpatlen-value = str.len(req.http.pattern);
  format.add_int(std.integer(req.http.wmpatlen-value, 0));
  # NO wmsegduration-label  was implemented
  # wmtoken-direct
  # wmpattern-value
  format.add_string(req.http.pattern);

  set req.http.json = format.get();
  jwt_writer.set_payload(req.http.json);

  #-------------------- Use JWT VMOD built in functions ----------------------#
  # Set the subject (sub)
  # jwt_writer.set_sub(req.method + " " + req.http.host + req.url);
  jwt_writer.set_sub(1234567890);

  # Set algorithm
  jwt_writer.set_alg("HS256");
  # Set the issuer (iss)
  jwt_writer.set_iss(server.identity);

  # Provide a synrthetic secret to later decode the JWT token
  set req.http.jwt = jwt_writer.generate("secret");
  if (jwt_writer.error()) {
    # Something went wrong generating the new token.
    return (synth(401,"Error creating JWT token"));
  }
  else
  {
    # Set the JWT topken as an Authorization header to validate it
    set req.http.Authorization = "Bearer " + req.http.jwt;
    set req.http.X-URL = "http://localhost/" + req.http.jwt + "/ingress.isml/.mpd";
    call verify_jwt; # Must include jwt_verify.vcl"
    return (synth(200,req.http.X-URL));
    # return (synth(200,{"
    #   <html>
    #     <head>
    #       <title>Watermarking token generator PoC</title>
    #     </head>
    #     <body>
    #       <h1>Watermarking PoC</h1>
    #       <p>
    #         <a href="https://www.w3schools.com/" target="_blank">Visit W3Schools!</a>
    #       </p>
    #     </body>
    #   </html>
    # "}));
  }
}

sub vcl_recv {
  std.log("***** Started vcl_recv *****");
  ## JWT token iana reference: https://www.iana.org/assignments/jwt/jwt.xhtml

  std.log("urlplus.get_extension(): " + urlplus.get_extension() );
  if (urlplus.get_extension() != "mpd")
  {
    return (synth(401,"MPD MPEG-DASH requests are only allowed"));
  }

  # We first set TTLs valid for most of the content we need to cache
  set req.http.X-Request-ID = utils.fast_random_int(999999999);

  call add_jwt_payload;

  # call verify_jwt;
}

sub vcl_synth {

    if (resp.status == 401)
    {
      set resp.http.Retry-After = "5";
      set resp.body = resp.reason + "(" + resp.status + ")";
      return (deliver);

    }
    elseif (resp.status == 200)
    {
      #set resp.http.Content-Type = "application/json";
      set resp.http.Retry-After = "5";
      #set resp.body = resp.reason + "(" + resp.status + ")";
      set resp.body = resp.reason;
      //set resp.body = "Hello World!";
      set resp.http.Authorization = req.http.Authorization;
      set resp.http.jwt-json = req.http.jwt-json;
      set resp.http.X-URL = req.http.X-URL;
      return (deliver);
    }

}

sub vcl_backend_response {
    std.log("Enters vcl_backend_response ");
    ## Caching will not work if there are different Authorization value
    ## per each request
    set beresp.ttl = 100s;
    set beresp.grace = 1s;
}

sub vcl_deliver {
    std.log("Enters vcl_deliver ");
  if (obj.hits > 0) {
      set resp.http.X-Cache = "HIT";
  } else {
      set resp.http.X-Cache = "MISS";
  }
  set resp.http.jwt-json = req.http.jwt-json;
  set resp.http.Authorization = req.http.Authorization;
  set resp.http.X-Request-ID = req.http.X-Request-ID;
  set resp.http.pattern = req.http.pattern;
  set resp.http.vcl-file =  "wmt_generator_server.vcl";
}