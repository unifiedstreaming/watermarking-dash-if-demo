vcl 4.1;

import std;
import utils;

backend default {
    .host = "live-origin-a";
    .port = "80";
}

backend media {
    .host = "live-origin-b";
    .port = "80";
}

sub vcl_recv {
    # Hack: Only forward GET and HEAD requests to the backend, otherwise
    # return an empty body with 202 status code. This mitigates
    # requests with OPTIONS method going to the backend.
    if (req.method != "GET" && req.method != "HEAD") {
        return (synth(202));
    }

    set req.ttl = 10s;
    set req.grace = 0s;

    # Randomly switch between A(default)/B(media)
    set req.http.random-a-b = utils.fast_random_int(2);

    if (req.http.random-a-b == "0")
    {
        set req.backend_hint = default;
    }
    elseif (req.http.random-a-b == "1")
    {
        set req.backend_hint = media;
    }
    else{
        return (synth(400,"Random backend was not correctly generated"));
    }

}
sub vcl_backend_response {
    std.log("Enters vcl_backend_response ");
    set beresp.do_stream = true;
    set beresp.grace = 0s;
}

sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    if(obj.ttl){
        # Show the seconds left the object ttl. Left = ttl - age
        std.log("obj.ttl: " + obj.ttl);
        set resp.http.ttl = obj.ttl;
    }
    set resp.http.file = "example_two_backends.vcl";
    set resp.http.random-a-b = req.http.random-a-b;
    unset resp.http.Cache-Control;
}
