/*
* Make sure to initialize jwt.reader() before calling this function.
* E.g.,:
sub vcl_init {
  new jwt_writer = jwt.writer();
  new jwt_reader = jwt.reader();
}
*/

sub verify_jwt {
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