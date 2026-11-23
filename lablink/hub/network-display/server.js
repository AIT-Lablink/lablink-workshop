const http = require("http");
const fs = require("fs");
const path = require("path");

const port = Number(process.env.PORT || 80);
const upstream = process.env.API_UPSTREAM || "http://uapiclient:7000";
const root = __dirname;

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
};

function serveStatic(req, res) {
  const pathname = req.url.split("?")[0];
  const rel = pathname === "/" ? "/index.html" : pathname;
  const file = path.normalize(path.join(root, rel));
  if (file !== root && !file.startsWith(root + path.sep)) {
    res.writeHead(403);
    res.end();
    return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    const type = types[path.extname(file)] || "application/octet-stream";
    res.writeHead(200, { "Content-Type": type });
    res.end(data);
  });
}

function proxy(req, res) {
  let target;
  try {
    target = new URL(req.url, upstream);
  } catch (err) {
    res.writeHead(502);
    res.end("Bad gateway");
    return;
  }
  const headers = Object.assign({}, req.headers, { host: target.host });
  const upstreamRequest = http.request(target, { method: req.method, headers }, (upstreamResponse) => {
    res.writeHead(upstreamResponse.statusCode, upstreamResponse.headers);
    upstreamResponse.pipe(res);
  });
  upstreamRequest.setTimeout(5000, () => upstreamRequest.destroy());
  upstreamRequest.on("error", () => {
    if (!res.headersSent) {
      res.writeHead(502);
    }
    res.end("Bad gateway");
  });
  req.on("aborted", () => upstreamRequest.destroy());
  req.pipe(upstreamRequest);
}

const server = http.createServer((req, res) => {
  const pathname = req.url.split("?")[0];
  if (pathname === "/simpledh" || pathname.startsWith("/simpledh/")) {
    proxy(req, res);
    return;
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405);
    res.end();
    return;
  }
  serveStatic(req, res);
});

server.listen(port, () => {
  console.log("display listening on " + port + ", API " + upstream);
});
