// Service worker sencillo: guarda la interfaz para que la app cargue al instante.
const NOMBRE = "controlpc-v2";
const RECURSOS = [
  ".", "index.html", "estilos.css", "app.js", "manifest.json",
  "iconos/icon-192.png", "iconos/icon-512.png", "iconos/icon-maskable-512.png",
];

self.addEventListener("install", (ev) => {
  ev.waitUntil(caches.open(NOMBRE).then((c) => c.addAll(RECURSOS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (ev) => {
  ev.waitUntil(
    caches.keys().then((claves) =>
      Promise.all(claves.filter((k) => k !== NOMBRE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (ev) => {
  const req = ev.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;
  if (url.pathname.includes("/api/") || url.pathname.endsWith("/ws")) return;

  // Red primero: si hay conexión, siempre toma la versión nueva; la caché es respaldo sin conexión.
  ev.respondWith(
    fetch(req)
      .then((nueva) => {
        if (nueva && nueva.ok) {
          const copia = nueva.clone();
          caches.open(NOMBRE).then((c) => c.put(req, copia)).catch(() => {});
        }
        return nueva;
      })
      .catch(() => caches.match(req, { ignoreSearch: true }).then((c) => c || Response.error()))
  );
});
