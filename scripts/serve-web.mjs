import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '../web');
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};
const port = Number(process.env.PORT || 3000);
http
  .createServer(async (request, response) => {
    try {
      const name = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      const file = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
      if (!file.startsWith(root + path.sep)) {
        response.writeHead(403).end('Forbidden');
        return;
      }
      const data = await readFile(file);
      response
        .writeHead(200, {
          'Content-Type': types[path.extname(file)] || 'application/octet-stream',
          'Cache-Control': 'no-cache',
          'X-Content-Type-Options': 'nosniff',
        })
        .end(data);
    } catch {
      response.writeHead(404).end('Not found');
    }
  })
  .listen(port, '0.0.0.0', () => console.log(`Snow Ops web server listening on port ${port}`));
