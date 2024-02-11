import accounting;

sub accounting_vcl_init {
  accounting.create_namespace("tenant1");
  accounting.create_namespace("tenant2");
  accounting.create_namespace("generic");
}


sub accounting_vcl_recv {
  std.log("Starting accounting");
  if (req.url ~ "ingress-a") {
    accounting.set_namespace("tenant1");
    std.log("accounting for ingress-a");
  }elsif (req.url ~ "ingress-b"){
    accounting.set_namespace("tenant2");
    std.log("accounting for ingress-a");
  }else {
    accounting.set_namespace("generic");
    std.log("accounting for generic");
  }
}


sub accounting_vcl_backend_response {
  std.log("beresp.http.Content-Type: " + beresp.http.Content-Type);
  if (beresp.http.Content-Type == "application/dash+xml"){
      accounting.add_keys("mpd");
      std.log("accounting.add_keys(mpd)");
  }elseif (beresp.http.Content-Type == "video/mp4"){
      accounting.add_keys("videomp4");
      std.log("accounting.add_keys(videomp4)");
  }elseif (beresp.http.Content-Type == "application/json"){
      accounting.add_keys("json");
      std.log("accounting.add_keys(json)");
  }
  else{
      accounting.add_keys("generic");
      std.log("accounting.add_keys(generic)");
  }
}