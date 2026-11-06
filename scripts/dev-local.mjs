import { createServer as createHttpServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, extname, join, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const siteRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const exclusiveRoot = join(siteRoot, 'exclusive');
const requireExclusive = createRequire(join(exclusiveRoot, 'package.json'));
const { createServer: createViteServer } = await import(pathToFileURL(requireExclusive.resolve('vite')).href);
const mode = process.argv[2] === '--official' ? 'official' : 'development';
if (process.argv.length > 2 && process.argv[2] !== '--official') throw new Error('Modo desconhecido.');
const port = Number(process.env.CITYPARK_PORT || (mode === 'official' ? 5175 : 5173));
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('CITYPARK_PORT inválida.');

const mimeTypes = {
  '.css': 'text/css', '.html': 'text/html', '.ico': 'image/x-icon',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.js': 'text/javascript',
  '.json': 'application/json', '.mp4': 'video/mp4', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff': 'font/woff',
  '.woff2': 'font/woff2', '.xml': 'application/xml', '.txt': 'text/plain'
};

let vite;
const server = createHttpServer(async (request, response) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  } catch {
    response.writeHead(400).end();
    return;
  }
  if (pathname === '/exclusive') {
    response.writeHead(308, { Location: '/exclusive/' }).end();
    return;
  }
  if (pathname.startsWith('/exclusive/')) {
    vite.middlewares(request, response);
    return;
  }
  if (!['GET', 'HEAD'].includes(request.method)) {
    response.writeHead(405).end();
    return;
  }
  if (pathname.split('/').some(part => part.startsWith('.'))) {
    response.writeHead(404).end();
    return;
  }
  const candidate = resolve(siteRoot, `.${pathname}`);
  if (candidate !== siteRoot && !candidate.startsWith(siteRoot + sep)) {
    response.writeHead(403).end();
    return;
  }
  try {
    const info = await stat(candidate);
    const file = info.isDirectory() ? join(candidate, 'index.html') : candidate;
    const data = await readFile(file);
    response.writeHead(200, { 'Content-Type': `${mimeTypes[extname(file).toLowerCase()] || 'application/octet-stream'}; charset=utf-8` });
    response.end(request.method === 'HEAD' ? undefined : data);
  } catch (error) {
    response.writeHead(error.code === 'ENOENT' || error.code === 'EISDIR' ? 404 : 500).end();
  }
});

vite = await createViteServer({
  root: exclusiveRoot,
  mode,
  configFile: join(exclusiveRoot, 'vite.config.mjs'),
  server: { middlewareMode: true, hmr: { server } }
});
server.listen(port, '127.0.0.1', () => {
  console.log(`CityPark: http://127.0.0.1:${port}/`);
  console.log(`Exclusive: http://127.0.0.1:${port}/exclusive/`);
});
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, async () => {
    server.close();
    await vite.close();
    process.exit(0);
  });
}
