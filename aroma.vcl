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
    synthetic {"<!DOCTYPE html>
<html>
<head>
  <title>Aroma</title>
  <style>
    body { font-family: sans-serif; padding: 20px; line-height: 1.6; }
    .box { background: #f0f0f0; padding: 15px; margin-bottom: 20px; border-radius: 8px; }
    h3 { margin-top: 0; }
    .metric { display: flex; justify-content: space-between; border-bottom: 1px solid #ccc; padding: 5px 0; }
    .val { font-weight: bold; font-family: monospace; }
  </style>
</head>
<body>
  <h2>Aroma</h2>
  <div id='results'>Running measurement...</div>

  <script>
    const endpoint = '/req.json';
    const numMeasurements = 10;
    let measurements = [];

    async function runMeasurements() {
      const resultsDiv = document.getElementById('results');
      
      for (let i = 0; i < numMeasurements; i++) {
        resultsDiv.innerHTML = `Running measurement ${i + 1} / ${numMeasurements}...`;
        
        const currentEndpoint = `${endpoint}`;
        
        try {
          const response = await fetch(currentEndpoint);
          const serverData = await response.json();
          
          // Get the precise network timing
          const fullUrl = new URL(currentEndpoint, window.location.href).href;
          const entries = performance.getEntriesByName(fullUrl);
          const entry = entries[entries.length - 1];

          if (entry) {
            measurements.push({
              entry: entry,
              serverData: serverData
            });
          }
        } catch (e) {
          console.error("Measurement failed", e);
        }
        
        // Small delay between requests
        await new Promise(r => setTimeout(r, 100));
      }

      calculateAndDisplayResults();
    }

    function calculateAndDisplayResults() {
      if (measurements.length === 0) {
        document.getElementById('results').innerHTML = "Error: No measurements collected.";
        return;
      }

      // Helper function to calculate trimmed average
      // Sorts array, removes highest and lowest (if possible), then averages
      function getTrimmedAverage(values) {
        if (values.length < 3) {
          // Can't drop 2 items if we don't have at least 3, return simple average
          const sum = values.reduce((a, b) => a + b, 0);
          return sum / values.length;
        }
        
        // Sort numerically
        values.sort((a, b) => a - b);
        
        // Remove first (lowest) and last (highest)
        const trimmed = values.slice(1, -1);
        
        const sum = trimmed.reduce((a, b) => a + b, 0);
        return sum / trimmed.length;
      }

      // Collect values arrays
      const serverRtts = [];
      const serverMinRtts = [];
      const clientTcps = [];
      const clientTlsOverheads = [];
      const httpRtts = [];
      const durations = [];
      
      const lastData = measurements[measurements.length - 1].serverData;
      const protocol = lastData.protocol || 'tcp';

      measurements.forEach(m => {
        const entry = m.entry;
        const sData = m.serverData;

        // Server metrics
        serverRtts.push(parseFloat(sData.rtt_us || 0));
        serverMinRtts.push(parseFloat(sData.min_rtt_us || 0));

        // Client metrics
        const clientTcp = entry.connectEnd - entry.connectStart;
        const clientTls = entry.secureConnectionStart > 0 ? (entry.requestStart - entry.secureConnectionStart) : 0;
        const httpRtt = entry.responseStart - entry.requestStart;

        clientTcps.push(clientTcp);
        clientTlsOverheads.push(clientTls);
        httpRtts.push(httpRtt);
        durations.push(entry.duration);
      });

      // Calculate Averages (trimmed)
      const avgServerRtt = (getTrimmedAverage(serverRtts) / 1000).toFixed(2);
      const avgServerMinRtt = (getTrimmedAverage(serverMinRtts) / 1000).toFixed(2);
      const avgClientTcp = getTrimmedAverage(clientTcps).toFixed(2);
      const avgClientTls = getTrimmedAverage(clientTlsOverheads).toFixed(2);
      const avgHttpRtt = getTrimmedAverage(httpRtts).toFixed(2);
      const avgDuration = getTrimmedAverage(durations).toFixed(2);

      lowestHttpRtt = Math.min(...httpRtts).toFixed(2);
      highestServerRtt = (Math.max(...serverRtts) / 1000).toFixed(2);

      const count = measurements.length;
      const protocolLabel = protocol === 'quic' ? 'QUIC' : 'TCP';
      
      // Determine how many were used
      const usedCount = count >= 3 ? count - 2 : count;

      // Proxy Detection Logic
      const isProxy1 = parseFloat(lowestHttpRtt) > (2 * parseFloat(highestServerRtt));
      const isProxy2 = parseFloat(avgServerRtt) > (10 * parseFloat(avgServerMinRtt));
      const isProxy = isProxy1 || isProxy2;
      
      let proxyMsg = "";
      if (isProxy) {
          proxyMsg = `
          <div class='box' style='background: #ffebee; border: 1px solid #ef9a9a;'>
            <h3 style='color: #c62828; margin-top: 0;'>Proxy Detected</h3>
            ${isProxy1 ? `<div class='metric' style='border-bottom: 0;'><span>High TTFB relative to RTT:</span> <span class='val'>${avgHttpRtt}ms > 2x ${avgServerRtt}ms</span></div>` : ''}
            ${isProxy2 ? `<div class='metric' style='border-bottom: 0;'><span>High RTT variance:</span> <span class='val'>${avgServerRtt}ms > 10x ${avgServerMinRtt}ms</span></div>` : ''}
          </div>`;
      }

      const html = `
        ${proxyMsg}
        <div class='box'>
          <h3>Layer 4: ${protocolLabel} (Trimmed Average of ${usedCount})</h3>
          <div class='metric'><span>Highest Server RTT:</span> <span class='val'>${highestServerRtt} ms</span></div>
          <div class='metric'><span>Server internal RTT estimate:</span> <span class='val'>${avgServerRtt} ms</span></div>
          <div class='metric'><span>Server min RTT estimate:</span> <span class='val'>${avgServerMinRtt} ms</span></div>
          <div class='metric'><span>Client measured Handshake:</span> <span class='val'>${avgClientTcp} ms</span></div>
        </div>

        <div class='box'>
          <h3>Layer 7: HTTP (Trimmed Average of ${usedCount})</h3>
          <div class='metric'><span>Lowest HTTP RTT:</span> <span class='val'>${lowestHttpRtt} ms</span></div>
          <div class='metric'><span>Real HTTP RTT (TTFB):</span> <span class='val'>${avgHttpRtt} ms</span></div>
          <div class='metric'><span>TLS Overhead:</span> <span class='val'>${avgClientTls} ms</span></div>
          <div class='metric'><span>Total Fetch Duration:</span> <span class='val'>${avgDuration} ms</span></div>
        </div>
        
        <small>Note: Highest and lowest values discarded. If Client Handshake average is low, connections were reused.</small>
      `;

      document.getElementById('results').innerHTML = html;
    }

    runMeasurements();
  </script>
</body>
</html>
"};
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

