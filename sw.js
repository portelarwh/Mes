/* =============================================================================
   MES — service worker
   =============================================================================
   ⚠️  REGRA PERMANENTE: a cada versão publicada, suba o CACHE_NAME abaixo para
       o MESMO número do APP_VERSION do index.html. É a troca do nome do cache
       que dispara a instalação do novo worker e a limpeza do cache antigo — sem
       isso o aparelho instalado continua servindo a versão velha.

       index.html:  var APP_VERSION='X.Y.Z'  →  aqui:  CACHE_NAME='mes-vX.Y.Z'
   ========================================================================== */
const CACHE_NAME = 'mes-v2.6.0';

/* Caminhos SEMPRE relativos: o app é servido num subcaminho no GitHub Pages de
   projeto (usuario.github.io/Mes/), e qualquer '/algo' apontaria para a raiz do
   domínio, dando 404.
   Os ícones entram aqui porque o Android os busca na hora de instalar o app. */
const ASSETS = [
  './', './index.html', './manifest.json',
  './assets/icon-192.png', './assets/icon-512.png',
  './assets/icon-maskable-192.png', './assets/icon-maskable-512.png',
  './assets/apple-touch-icon.png',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
  );
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

/* o app pede a troca imediata quando detecta versão nova */
self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;

  /* Nada de outra origem passa por aqui. Sem esta linha as leituras da API do
     Supabase entrariam no cache e o app passaria a servir dado velho. */
  let sameOrigin = false;
  try { sameOrigin = new URL(req.url).origin === self.location.origin; } catch (e) {}
  if (!sameOrigin) return;

  /* Navegação: rede primeiro (sem cache do browser), atualizando a cópia
     offline. Só cai para o cache quando a rede falha. */
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req, { cache: 'no-store' });
        const cache = await caches.open(CACHE_NAME);
        cache.put('./index.html', fresh.clone()).catch(() => {});
        return fresh;
      } catch (e) {
        const cache = await caches.open(CACHE_NAME);
        return (await cache.match('./index.html')) || (await cache.match('./')) || Response.error();
      }
    })());
    return;
  }

  /* Demais assets: cache primeiro. */
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const hit = await cache.match(req);
    if (hit) return hit;
    try {
      const res = await fetch(req);
      if (res && res.ok) cache.put(req, res.clone()).catch(() => {});
      return res;
    } catch (e) {
      return Response.error();
    }
  })());
});
