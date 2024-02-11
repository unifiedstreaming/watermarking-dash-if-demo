vcl 4.1;

import std;
import utils;
import urlplus;

include "/etc/varnish/accounting_metrics.vcl";


backend default {
    .host = "{{TARGET_HOST}}";
    .port = "{{TARGET_PORT}}";
}

sub vcl_init {
  call accounting_vcl_init;
}


sub vcl_recv {
    # Hack: Only forward GET and HEAD requests to the backend, otherwise
    # return an empty body with 202 status code. This mitigates
    # requests with OPTIONS method going to the backend.
    if (req.method != "GET" &&  req.method != "HEAD") {
        return (synth(202));
    }


    if (urlplus.get_extension() ~ "mpd|dash|m4s|xml|json") {
        urlplus.url_add("ingress-a", keep=1, position=0);
        # urplus.write() will automatically modify req.url
        urlplus.write();
        std.log("req.http.url-add: " + req.url);
    }
    call accounting_vcl_recv;


}
sub vcl_backend_response {
    std.log("Enters vcl_backend_response ");
    set beresp.grace = 0s;
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

    call accounting_vcl_backend_response;

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
    set resp.http.file = "watermarking_live_setup_1.vcl";
    unset resp.http.Cache-Control;
}
