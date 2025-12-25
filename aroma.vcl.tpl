sub vcl_recv { 
#FASTLY recv

  # Normally, you should consider requests other than GET and HEAD to be uncacheable
  # (to this we add the special FASTLYPURGE method)
  if (req.method != "HEAD" && req.method != "GET" && req.method != "FASTLYPURGE") {
    return(pass);
  }

  # If you are using image optimization, insert the code to enable it here
  # See https://www.fastly.com/documentation/reference/io/ for more information.
  if (client.socket.tcp_info) {
    declare local var.score FLOAT;
    set var.score = client.socket.tcpi_min_rtt;
    set var.score /= client.socket.tcpi_rtt;
    set req.http.X-Aroma-Score = var.score;
  }

  if (req.url == "/req.json") {
    if (client.socket.tcp_info) {
      set req.http.X-Protocol = "tcp";
    } else {
      set req.http.X-Protocol = "quic";
      set req.http.X-Quic-Smoothed = quic.rtt.smoothed;
      set req.http.X-Quic-Minimum = quic.rtt.minimum;
      set req.http.X-Quic-Variance = quic.rtt.variance;
    }
    error 601;
  }

  if (req.url == "/info") {
    error 602;
  }

  if (req.url == "/score") {
    error 604;
  }

  if (client.socket.tcp_info && (var.score < 0.1)) {
    error 603;
  }

  return(lookup);
}

sub vcl_hash {
  set req.hash += req.url;
  set req.hash += req.http.host;
  #FASTLY hash
  return(hash);
}

sub vcl_hit {
#FASTLY hit
  return(deliver);
}

sub vcl_miss {
#FASTLY miss
  return(fetch);
}

sub vcl_pass {
#FASTLY pass
  return(pass);
}

sub vcl_fetch {
#FASTLY fetch

  # Unset headers that reduce cacheability for images processed using the Fastly image optimizer
  if (req.http.X-Fastly-Imageopto-Api) {
    unset beresp.http.Set-Cookie;
    unset beresp.http.Vary;
  }

  # Log the number of restarts for debugging purposes
  if (req.restarts > 0) {
    set beresp.http.Fastly-Restarts = req.restarts;
  }

  # If the response is setting a cookie, make sure it is not cached
  if (beresp.http.Set-Cookie) {
    return(pass);
  }

  # By default we set a TTL based on the `Cache-Control` header but we don't parse additional directives
  # like `private` and `no-store`. Private in particular should be respected at the edge:
  if (beresp.http.Cache-Control ~ "(?:private|no-store)") {
    return(pass);
  }

  # If no TTL has been provided in the response headers, set a default
  if (!beresp.http.Expires && !beresp.http.Surrogate-Control ~ "max-age" && !beresp.http.Cache-Control ~ "(?:s-maxage|max-age)") {
    set beresp.ttl = 3600s;

    # Apply a longer default TTL for images processed using Image Optimizer
    if (req.http.X-Fastly-Imageopto-Api) {
      set beresp.ttl = 2592000s; # 30 days
      set beresp.http.Cache-Control = "max-age=2592000, public";
    }
  }

  return(deliver);
}

sub vcl_error {
#FASTLY error
  if (obj.status == 601) {
    set obj.status = 200;
    set obj.response = "OK";
    set obj.http.Content-Type = "application/json; charset=utf8";
    if (req.http.X-Protocol == "quic") {
      synthetic {"{
        "protocol": "quic",
        "min_rtt_us": "} + req.http.X-Quic-Minimum + {", 
        "rtt_us": "} + req.http.X-Quic-Smoothed + {", 
        "rttvar_us": "} + req.http.X-Quic-Variance + {"
      }"};
    } else {
      synthetic {"{
        "protocol": "tcp",
        "min_rtt_us": "} + client.socket.tcpi_min_rtt + {", 
        "rtt_us": "} + client.socket.tcpi_rtt + {", 
        "rttvar_us": "} + client.socket.tcpi_rttvar + {", 
        "advmss": "} + client.socket.tcpi_advmss + {", 
        "rcv_mss": "} + client.socket.tcpi_rcv_mss + {"
      }"};
    }
    return(deliver);
  }

  if (obj.status == 602) {
    set obj.status = 200;
    set obj.response = "OK";
    set obj.http.Content-Type = "text/html; charset=utf8";
    synthetic {"__HTML_CONTENT__"};
    return(deliver);
  }

  if (obj.status == 603) {
    set obj.status = 200;
    set obj.response = "OK";
    set obj.http.Content-Type = "text/html; charset=utf8";
    synthetic "<html><body><h1>Blocked (Proxy detected)</h1><h2>Score: " + req.http.X-Aroma-Score + "</h2><a href=%22/info%22>Request Info</a></body></html>";
    return(deliver);
  }

  if (obj.status == 604) {
    set obj.status = 200;
    set obj.response = "OK";
    set obj.http.Content-Type = "text/html; charset=utf8";
    synthetic "<html><body><h1>Score: " + req.http.X-Aroma-Score + "</h1><a href=%22/info%22>Request Info</a></body></html>";
    return(deliver);
  }

  return(deliver);
}

sub vcl_deliver {
#FASTLY deliver
  return(deliver);
}

sub vcl_log {
#FASTLY log
}

