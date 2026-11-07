// Control PC — cliente del teléfono (PWA)
/* eslint-disable no-console */
"use strict";

/* ============ utilidades ============ */
const $ = (id) => document.getElementById(id);
const limite = (v, a, b) => Math.max(a, Math.min(b, v));

const S = {
  ws: null,
  conectado: false,
  img: null,          // ImageBitmap del último fotograma
  iw: 0, ih: 0,       // dimensiones de la imagen
  z: 1,               // zoom local
  panx: 0, pany: 0,   // desplazamiento local (px CSS)
  g: null,            // geometría calculada {s, ox, oy, z, oxz, oyz}
  gest2: null,        // estado del gesto con dos dedos
  enVuelo: 0,         // decodificaciones de imagen en curso (se limitan a 2)
  casosCerrados: [],  // momentos de cierres de WS para detectar sesión caducada
};

/* ============ vistas ============ */
function mostrarAcceso() {
  $("vista-principal").hidden = true;
  $("vista-acceso").hidden = false;
  desconectar();
}

function mostrarPrincipal() {
  $("vista-acceso").hidden = true;
  $("vista-principal").hidden = false;
}

/* ======== volumen y sonido ======== */
let volumenArrastrando = false;
let mudoActual = false;

async function enviarVolumen(nivel, mudo) {
  const cuerpo = {};
  if (nivel !== undefined && nivel !== null) cuerpo.nivel = nivel;
  if (mudo !== undefined && mudo !== null) cuerpo.mudo = mudo;
  try {
    const r = await fetch("/api/volumen", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(cuerpo),
    });
    aplicarVolumenUI(await r.json());
  } catch (e) {}
}

function aplicarVolumenUI(v) {
  if (!v) return;
  $("slider-volumen").disabled = !v.soportado;
  if (!volumenArrastrando && v.nivel !== null && v.nivel !== undefined) {
    $("slider-volumen").value = v.nivel;
  }
  $("valor-volumen").textContent = v.nivel === null ? "–" : v.nivel + "%";
  mudoActual = !!v.mudo;
  $("btn-mudo").textContent = mudoActual ? "🔊" : "🔇";
  $("boton-volumen").textContent = mudoActual ? "🔇" : "🔊";
}

$("slider-volumen").addEventListener("input", () => {
  $("valor-volumen").textContent = $("slider-volumen").value + "%";
});
$("slider-volumen").addEventListener("change", () => {
  enviarVolumen(Number($("slider-volumen").value));
});
$("slider-volumen").addEventListener("pointerdown", () => { volumenArrastrando = true; });
window.addEventListener("pointerup", () => { volumenArrastrando = false; });
$("btn-mudo").onclick = () => enviarVolumen(null, !mudoActual);

/* sonido en vivo (loopback WASAPI -> WebSocket -> AudioWorklet) */
let ctxA = null, wsA = null, nodoA = null, escuchando = false;
const CODIGO_REPRODUCTOR = `
class Reproductor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.cap = 65536;
    this.mask = this.cap - 1;
    this.buf = new Float32Array(this.cap);
    this.leer = 0;
    this.escribir = 0;
    this.port.onmessage = (e) => this.entrar(new Float32Array(e.data));
  }
  entrar(f) {
    const mask = this.mask;
    for (let i = 0; i < f.length; i++) {
      if (this.escribir - this.leer >= this.cap) this.leer++;
      this.buf[this.escribir & mask] = f[i];
      this.escribir++;
    }
  }
  process(inputs, outputs) {
    const out = outputs[0][0];
    const mask = this.mask;
    for (let i = 0; i < out.length; i++) {
      if (this.escribir === this.leer) out[i] = 0;
      else { out[i] = this.buf[this.leer & mask]; this.leer++; }
    }
    return true;
  }
}
registerProcessor("reproductor", Reproductor);`;

async function encenderSonido() {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  try {
    wsA = new WebSocket(`${proto}://${location.host}/ws-audio`);
    wsA.binaryType = "arraybuffer";
    const meta = await new Promise((res) => {
      wsA.onmessage = (ev) => {
        if (typeof ev.data === "string") return res(JSON.parse(ev.data));
      };
      wsA.onerror = () => res({ sr: 0, error: "no se pudo conectar" });
      setTimeout(() => res({ sr: 0, error: "sin respuesta del servidor" }), 5000);
    });
    if (meta.error || !meta.sr) {
      $("nota-audio").textContent = "❌ " + (meta.error || "audio no disponible");
      apagarSonido();
      return;
    }
    if (!ctxA) ctxA = new AudioContext({ latencyHint: "interactive" });
    if (!nodoA) {
      const url = URL.createObjectURL(new Blob([CODIGO_REPRODUCTOR], { type: "text/javascript" }));
      await ctxA.audioWorklet.addModule(url);
      URL.revokeObjectURL(url);
      nodoA = new AudioWorkletNode(ctxA, "reproductor");
      nodoA.connect(ctxA.destination);
    }
    wsA.onmessage = (ev) => {
      if (typeof ev.data === "string") return;
      try {
        const i16 = new Int16Array(ev.data);
        const f = new Float32Array(i16.length);
        for (let i = 0; i < i16.length; i++) f[i] = i16[i] / 32768;
        nodoA.port.postMessage(f.buffer, [f.buffer]);
      } catch (e) {}
    };
    await ctxA.resume();
    escuchando = true;
    $("btn-sonido").textContent = "⏸ Detener sonido";
    $("estado-audio").textContent = "escuchando · " + meta.sr + " Hz";
    $("nota-audio").textContent = "Sonido de la PC al instante (una fracción de segundo de demora es normal).";
  } catch (e) {
    $("nota-audio").textContent = "❌ No se pudo abrir el sonido: " + (e.message || e);
    apagarSonido();
  }
}

function apagarSonido() {
  escuchando = false;
  try { if (wsA) wsA.close(); } catch (e) {}
  wsA = null;
  $("btn-sonido").textContent = "▶ Escuchar el sonido de la PC";
  $("estado-audio").textContent = "apagado";
}
$("btn-sonido").onclick = () => { if (escuchando) apagarSonido(); else encenderSonido(); };
document.addEventListener("visibilitychange", () => {
  if (document.hidden && escuchando) apagarSonido();
});

/* ======== avisos ======== */
let ultimoAvisoId = 0;

function tiempoHace(s) {
  if (s < 60) return s + " s";
  if (s < 3600) return Math.floor(s / 60) + " min";
  return Math.floor(s / 3600) + " h";
}

function toastAviso(a) {
  const d = document.createElement("div");
  d.className = "aviso-flotante " + a.nivel;
  d.innerHTML = `<div class="aviso-texto">${a.texto}</div>${a.seguridad ? `
    <div class="aviso-botones">
      <button data-acc="permitir">✅ Permitir</button>
      <button data-acc="rechazar">🚫 Rechazar</button>
    </div>` : ""}`;
  d.querySelectorAll("[data-acc]").forEach((b) => {
    b.onclick = () => accionSeguridad(b.dataset.acc, d);
  });
  $("avisos-flotantes").appendChild(d);
  navigator.vibrate && navigator.vibrate(a.nivel === "peligro" ? [60, 40, 60] : 25);
  setTimeout(() => d.remove(), a.seguridad ? 25000 : 7000);
}

function bloqueAvisos(lista) {
  const items = lista.slice(0, 12).map((a) =>
    `<div class="aviso-linea"><b>${a.nivel === "peligro" ? "🔴" : a.nivel === "advertencia" ? "🟡" : "🔵"}</b>
      <span>${a.texto}</span><span class="texto-gris">hace ${tiempoHace(a.hace)}</span></div>`).join("");
  $("bloque-avisos").innerHTML = `<div class="subtitulo">Avisos</div><div class="tarjeta-grupo">${items || "—"}</div>`;
}

function conectarAviso(mensaje) {
  $("avisos-flotantes") /* por si se llama fuera de un toast */;
  const d = document.createElement("div");
  d.className = "aviso-flotante info";
  d.innerHTML = `<div class="aviso-texto">${mensaje}</div>`;
  $("avisos-flotantes").appendChild(d);
  setTimeout(() => d.remove(), 5000);
}

async function accionSeguridad(accion, elemento) {
  try {
    const r = await fetch("/api/seguridad-accion", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ accion }),
    });
    const d = await r.json();
    let mensaje;
    if (d.ok && accion === "rechazar") mensaje = "🚫 Ventana rechazada desde el teléfono";
    else if (d.ok) mensaje = "✅ " + (d.mensaje || "Modo silencioso aplicado");
    else if (d.error === "requiere-admin") mensaje = "⚠️ Corre el servidor con iniciar_admin.bat para poder rechazar";
    else if (d.pendiente) mensaje = "📝 Autoriza la ventana de Windows en la PC";
    else mensaje = "⚠️ No se pudo: " + (d.error || "?");
    const t = elemento.querySelector(".aviso-texto");
    if (t) t.innerHTML = mensaje;
    elemento.querySelectorAll(".aviso-botones").forEach((b) => b.remove());
    setTimeout(() => elemento.remove(), 4000);
    obtenerEstado();
  } catch (e) {}
}

function procesarAvisos(datos) {
  const lista = datos.avisos || [];
  if (!lista.length) { bloqueAvisos([]); return; }
  const maxId = lista.reduce((m, a) => Math.max(m, a.id), 0);
  if (ultimoAvisoId === 0) { ultimoAvisoId = maxId; bloqueAvisos(lista); return; }
  if (maxId > ultimoAvisoId) {
    lista.filter((a) => a.id > ultimoAvisoId).forEach(toastAviso);
    ultimoAvisoId = maxId;
  }
  bloqueAvisos(lista);
}

/* ======== UAC ======== */
$("btn-uac").onclick = async () => {
  const silencioso = $("estado-uac").textContent.indexOf("silencioso") >= 0;
  const nuevo = silencioso ? "aviso" : "silencioso";
  const seguir = confirm(nuevo === "silencioso"
    ? "Windows dejará de preguntar los permisos de administración en la PC (menos seguro; se puede revertir aquí mismo). ¿Seguro?"
    : "¿Volver a que Windows pregunte los permisos de administración?");
  if (!seguir) return;
  try {
    const r = await fetch("/api/uac", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ modo: nuevo }),
    });
    const d = await r.json();
    if (d.ok && d.pendiente) alert("Windows abrirá una ventana EN TU PC: autorizala para aplicar el cambio.");
    obtenerEstado();
  } catch (e) {}
};

$("btn-prueba-aviso").onclick = async () => {
  try {
    await fetch("/api/aviso", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ texto: "🔔 ¡Aviso de prueba desde los ajustes!" }),
    });
    obtenerEstado();
  } catch (e) {}
};

/* ============ acceso ============ */
async function entrar() {
  const clave = $("campo-clave").value.trim();
  if (!clave) return;
  $("btn-entrar").disabled = true;
  $("error-acceso").hidden = true;
  try {
    const r = await fetch("/api/acceso", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ contrasena: clave }),
    });
    if (r.ok) {
      $("campo-clave").value = "";
      mostrarPrincipal();
      conectar();
    } else {
      $("error-acceso").hidden = false;
      $("error-acceso").textContent =
        r.status === 429 ? "Demasiados intentos, espera un minuto" : "Contraseña incorrecta";
      navigator.vibrate && navigator.vibrate(80);
    }
  } catch (e) {
    $("error-acceso").hidden = false;
    $("error-acceso").textContent = "No se pudo contactar al servidor (¿conectado al mismo Wi-Fi?)";
  }
  $("btn-entrar").disabled = false;
}

async function cerrarSesion() {
  try { await fetch("/api/salir"); } catch (e) {}
  mostrarAcceso();
}

/* ============ conexión (WebSocket) ============ */
function conectar() {
  if (S.ws && (S.ws.readyState === 0 || S.ws.readyState === 1)) return;
  obtenerEstado(); // actualiza estado aunque el WS falle
  const proto = location.protocol === "https:" ? "wss" : "ws";
  const ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.binaryType = "arraybuffer";
  S.ws = ws;

  ws.onopen = () => {
    S.conectado = true;
    ponerEstado("verde", "Conectado");
    ocultarFuera();
    recalcular(true);
    enviarConfig();
  };
  ws.onmessage = (ev) => {
    if (typeof ev.data === "string") {
      const m = JSON.parse(ev.data);
      if (m.t === "pong") {
        $("texto-ping").textContent = `${Math.max(1, Math.round(performance.now() - m.ts))} ms`;
      } else if (m.t === "error") {
        mostrarAcceso();
      }
    } else {
      // fotograma JPEG: se decodifican como máximo 2; el resto se descarta
      // para dibujar SIEMPRE el fotograma más nuevo (latencia mínima)
      if (S.enVuelo >= 2) return;
      S.enVuelo++;
      const blob = new Blob([ev.data], { type: "image/jpeg" });
      createImageBitmap(blob).then((bmp) => {
        S.enVuelo--;
        const cambio = bmp.width !== S.iw || bmp.height !== S.ih;
        if (S.img) S.img.close && S.img.close();
        S.img = bmp;
        S.iw = bmp.width;
        S.ih = bmp.height;
        if (cambio) { S.z = 1; S.panx = 0; S.pany = 0; }
      }).catch(() => { S.enVuelo--; });
    }
  };
  ws.onclose = (ev) => {
    S.conectado = false;
    S.ws = null;
    ponerEstado(ev.code === 4401 ? "rojo" : "amarillo", "Reintentando…");
    mostrarFuera();
    // si la sesión caducó (faltan 401 consecutivos), pide clave de nuevo
    S.casosCerrados.push(Date.now());
    S.casosCerrados = S.casosCerrados.filter((t) => Date.now() - t < 20000);
    if (ev.code === 4401 || S.casosCerrados.length >= 3) {
      mostrarAcceso();
      S.casosCerrados = [];
    }
    conectar2();
  };
  ws.onerror = () => { try { ws.close(); } catch (e) {} };
}

function conectar2() {
  if ($("vista-principal").hidden) return;
  clearTimeout(conectar2.t);
  conectar2.t = setTimeout(() => {
    if ($("vista-principal").hidden) return;
    if (!S.ws) conectar();
  }, 3000);
}

function desconectar() {
  if (S.ws) { const w = S.ws; S.ws = null; try { w.onclose = null; w.close(); } catch (e) {} }
  ponerEstado("amarillo", "Desconectado");
}

function enviar(o) {
  if (S.ws && S.ws.readyState === 1) S.ws.send(JSON.stringify(o));
}

function ponerEstado(color, texto) {
  const p = $("punto-estado");
  p.className = "punto " + color;
  $("texto-estado").textContent = texto;
}

function mostrarFuera() { $("mensaje-fuera").hidden = false; }
function ocultarFuera() { $("mensaje-fuera").hidden = true; }

/* ping constante */
setInterval(() => { if (S.conectado) enviar({ t: "ping", ts: performance.now() }); }, 4000);

/* ============ ajustes enviados ============ */
const ANCHO_CALIDAD = { 0: 960, 1: 1280, 2: 1600, 3: 1920 };
const Q_CALIDAD = { 0: 45, 1: 55, 2: 68, 3: 78 };

function enviarConfig() {
  const nivel = Number($("sel-calidad").value) || 1;
  enviar({
    t: "cfg",
    ancho_maximo: ANCHO_CALIDAD[nivel],
    calidad_jpeg: Q_CALIDAD[nivel],
    fps: Number($("sel-fps").value),
    pantalla: Number($("sel-pantalla").value),
  });
}

/* ============ dibujo ============ */
const lienzo = $("lienzo");
const ctx = lienzo.getContext("2d");

function geometria() {
  const cw = lienzo.clientWidth, ch = lienzo.clientHeight;
  if (!S.iw || !S.ih) { S.g = null; return; }
  const s = Math.min(cw / S.iw, ch / S.ih);
  const ox = (cw - S.iw * s) / 2;
  const oy = (ch - S.ih * s) / 2;
  const lim = (S.iw * s) * (S.z - 1) / 2;
  const panx = limite(S.panx, -lim, Math.max(0, lim));
  const pany = limite(S.pany, -(S.ih * s) * (S.z - 1) / 2, Math.max(0, (S.ih * s) * (S.z - 1) / 2));
  S.panx = panx;
  S.pany = pany;
  S.g = {
    s, z: S.z,
    oxz: ox - lim + panx,
    oyz: oy - (S.ih * s) * (S.z - 1) / 2 + pany,
  };
}

function recalcular(mantener) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
  const w = lienzo.clientWidth, h = lienzo.clientHeight;
  if (lienzo.width !== Math.round(w * dpr) || lienzo.height !== Math.round(h * dpr)) {
    lienzo.width = Math.round(w * dpr);
    lienzo.height = Math.round(h * dpr);
  }
}

function dibujar() {
  requestAnimationFrame(dibujar);
  const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = "#05070c";
  ctx.fillRect(0, 0, lienzo.clientWidth, lienzo.clientHeight);
  geometria();
  if (S.img && S.g) {
    ctx.save();
    ctx.translate(S.g.oxz, S.g.oyz);
    ctx.scale(S.g.s * S.g.z, S.g.s * S.g.z);
    ctx.imageSmoothingEnabled = S.g.s * S.g.z < 1.5;
    ctx.drawImage(S.img, 0, 0);
    ctx.restore();
  }
}
requestAnimationFrame(dibujar);

/* despeja el aviso de conexión cuando ya hay fotogramas */
setInterval(() => { if (S.img) ocultarFuera(); }, 800);

window.addEventListener("resize", () => recalcular(false));
new ResizeObserver(() => recalcular(false)).observe($("host-lienzo"));

/* ============ coordenadas ============ */
function aImagen(ev) {
  const g = S.g;
  if (!g) return null;
  const r = lienzo.getBoundingClientRect();
  const x = (ev.clientX - r.left - g.oxz) / (g.s * g.z);
  const y = (ev.clientY - r.top - g.oyz) / (g.s * g.z);
  return { x: x / S.iw, y: y / S.ih, dentro: x >= 0 && y >= 0 && x <= S.iw && y <= S.ih };
}

/* ============ gestos ============ */
const punteros = new Map();
let primario = null;
let posTocar = null;        // posición (imagen) donde se tocó por primera vez
let acumulado = 0;          // distancia recorrida en px CSS
let pulsado = false;        // se envió "pulsar" (arrastre en curso)
let modoLargo = false;      // pulsación larga (clic derecho) activa
let temporizadorLargo = null;
let modoPunteroLibre = false; // arrastre solo mueve el ratón (hover), sin presionar
let arrastreLibre = false;    // el arrastre actual fue libre (no clic al soltar)

function cancelarLargo() {
  clearTimeout(temporizadorLargo);
  temporizadorLargo = null;
}

function abajo(ev) {
  ev.preventDefault();
  try { lienzo.setPointerCapture(ev.pointerId); } catch (e) {}
  punteros.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });

  if (punteros.size === 1) {
    primario = ev.pointerId;
    acumulado = 0;
    pulsado = false;
    modoLargo = false;
    arrastreLibre = false;
    const p = aImagen(ev);
    posTocar = p;
    if (p) enviar({ t: "mover", x: p.x, y: p.y }); // posiciona el cursor
    temporizadorLargo = setTimeout(() => {
      modoLargo = true;
      pulsado = true;
      navigator.vibrate && navigator.vibrate(40);
      const p2 = aImagen({ clientX: punteros.get(ev.pointerId).x, clientY: punteros.get(ev.pointerId).y });
      if (p2) enviar({ t: "pulsar", x: p2.x, y: p2.y, b: "der" });
    }, 600);
  } else if (punteros.size === 2) {
    cancelarLargo();
    soltarPendiente(); // cierra lo que el primer dedo hubiera abierto
    empezarGesto2();
  } else {
    cancelarLargo();
    S.gest2 = null;
  }
}

function mover(ev) {
  if (!punteros.has(ev.pointerId)) return;
  ev.preventDefault();
  const prev = punteros.get(ev.pointerId);
  const dx = ev.clientX - prev.x, dy = ev.clientY - prev.y;
  prev.x = ev.clientX; prev.y = ev.clientY;

  if (punteros.size === 1 && ev.pointerId === primario) {
    acumulado += Math.abs(dx) + Math.abs(dy);
    const p = aImagen(ev);
    if (!p) return;

    // cruza el umbral de arrastre
    if (acumulado > 14 && !pulsado && !modoLargo) {
      cancelarLargo();
      if (S.z > 1) {
        // con zoom: arrastrar desplaza la vista
        S.panx -= dx / (S.g.s * S.g.z);
        S.pany -= dy / (S.g.s * S.g.z);
        geometria();
        return;
      }
      if (!modoPunteroLibre) {
        pulsado = true;
        enviar({ t: "pulsar", x: posTocar ? posTocar.x : p.x, y: posTocar ? posTocar.y : p.y, b: "izq" });
      } else {
        arrastreLibre = true; // modo puntero: solo mueve, sin presionar
      }
    }

    if (S.gest2) return;
    enviar({ t: "mover", x: p.x, y: p.y });
  } else if (punteros.size === 2) {
    actualizarGesto2();
  }
}

function arriba(ev) {
  if (!punteros.has(ev.pointerId)) return;
  punteros.delete(ev.pointerId);
  try { lienzo.releasePointerCapture(ev.pointerId); } catch (e) {}

  if (punteros.size === 1) {
    // vuelve a control primario con el dedo restante
    primario = [...punteros.keys()][0];
    acumulado = 0;
    posTocar = null;
    S.gest2 = null;
    return;
  }
  if (punteros.size >= 2) { actualizarGesto2(); return; }

  cancelarLargo();
  if (S.gest2) { S.gest2 = null; return; }
  enviarPendiente();
  // toques rápidos originan clic en el servidor
  if (!ev.fueGesto) {}
}
// cierre del punto primario: soltar botón o generar clic simple
function enviarPendiente() {
  if (pulsado) {
    enviar({ t: "soltar", b: modoLargo ? "der" : "izq" });
    pulsado = false;
    modoLargo = false;
  } else if (posTocar && !arrastreLibre) {
    enviar({ t: "clic", x: posTocar.x, y: posTocar.y, b: "izq" });
  }
  arrastreLibre = false;
  posTocar = null;
}
function soltarPendiente() {
  if (pulsado) { enviar({ t: "soltar", b: modoLargo ? "der" : "izq" }); pulsado = false; modoLargo = false; }
  arrastreLibre = false;
}

/* -------- dos dedos: scroll y zoom -------- */
function empezarGesto2() {
  const [a, b] = [...punteros.values()];
  S.gest2 = {
    d0: Math.hypot(a.x - b.x, a.y - b.y) || 1,
    z0: S.z,
    ax: (a.x + b.x) / 2, ay: (a.y + b.y) / 2,
    modo: null,      // 'pinz' | 'desliza' | 'pan'
    acc: 0,
  };
}

function actualizarGesto2() {
  const g2 = S.gest2;
  if (!g2 || punteros.size < 2) return;
  const [a, b] = [...punteros.values()];
  const d = Math.hypot(a.x - b.x, a.y - b.y) || 1;
  const ax = (a.x + b.x) / 2, ay = (a.y + b.y) / 2;
  const pinch = (d - g2.d0) / 2;
  const dax = ax - g2.ax, day = ay - g2.ay;

  if (!g2.modo) {
    if (Math.abs(pinch) > 18) g2.modo = "pinz";
    else if (Math.abs(dax) > 18 && S.z > 1) g2.modo = "pan";
    else if (Math.abs(day) > 12) g2.modo = "desliza";
  }

  if (g2.modo === "pinz") {
    const nz = limite(g2.z0 * (d / g2.d0), 1, 12);
    S.z = nz;
    if (nz <= 1.001) { S.z = 1; S.panx = 0; S.pany = 0; }
    geometria();
  } else if (g2.modo === "pan") {
    S.panx -= dax / (S.g.s * S.g.z);
    S.pany -= day / (S.g.s * S.g.z);
    geometria();
  } else if (g2.modo === "desliza") {
    g2.acc += day;
    const paso = Math.trunc(g2.acc / 40);
    if (paso) {
      g2.acc -= paso * 40;
      enviar({ t: "deslizar", dy: paso * 40 });
    }
  } else {
    g2.acc += 0;
  }
  g2.ax = ax; g2.ay = ay;
  g2.d0 = d;
  // recoloca z0/d0 para seguir de cerca la evolución del gesto
  g2.z0 = S.z;
}

lienzo.addEventListener("pointerdown", abajo, { passive: false });
lienzo.addEventListener("pointermove", mover, { passive: false });
lienzo.addEventListener("pointerup", arriba);
lienzo.addEventListener("pointercancel", arriba);
lienzo.addEventListener("lostpointercapture", (ev) => { if (!punteros.has(ev.pointerId)) return; }, { passive: true });
lienzo.addEventListener("contextmenu", (e) => e.preventDefault());

/* iOS: pellizco nativo fuera */
document.addEventListener("gesturestart", (e) => e.preventDefault());

/* el rueda del ratón físico en PC de escritorio para pruebas */
lienzo.addEventListener("wheel", (ev) => {
  if (ev.ctrlKey) { ev.preventDefault(); S.z = limite(S.z * (ev.deltaY < 0 ? 1.15 : 0.87), 1, 12); geometria(); return; }
  enviar({ t: "deslizar", dy: limite(ev.deltaY, -400, 400) });
}, { passive: true });

/* ============ paneles ============ */
function activarPanel(id, boton) {
  const ids = ["panel-estado", "panel-config", "panel-teclado", "panel-volumen"];
  document.querySelectorAll(".opcion").forEach((b) => b.classList.remove("activa"));
  let abierto = false;
  ids.forEach((i) => {
    if (i === id && $(i).hidden) { $(i).hidden = false; abierto = true; }
    else $(i).hidden = true;
  });
  if (abierto && boton) boton.classList.add("activa");
}

$("boton-estado").onclick = (e) => activarPanel("panel-estado", e.currentTarget);
$("boton-config").onclick = (e) => activarPanel("panel-config", e.currentTarget);
$("boton-teclado").onclick = (e) => activarPanel("panel-teclado", e.currentTarget);
$("boton-volumen").onclick = (e) => activarPanel("panel-volumen", e.currentTarget);
document.querySelectorAll(".cerrar").forEach((b) => {
  b.onclick = (e) => { activarPanel(null, null); };
});
function activarPanelNulo() { activarPanel(null, null); }

/* zoom botones */
$("boton-zoom-mas").onclick = () => { S.z = limite(S.z * 1.6, 1, 12); geometria(); };
$("boton-zoom-menos").onclick = () => { S.z = limite(S.z / 1.6, 1, 12); if (S.z < 1.02) { S.z = 1; S.panx = 0; S.pany = 0; } geometria(); };
$("boton-zoom-reset").onclick = () => { S.z = 1; S.panx = 0; S.pany = 0; geometria(); };

/* modo puntero libre: arrastrar solo mueve el ratón, sin presionar */
$("boton-puntero").onclick = () => {
  modoPunteroLibre = !modoPunteroLibre;
  $("boton-puntero").classList.toggle("activa", modoPunteroLibre);
};

/* pantalla completa */
$("boton-completa").onclick = () => {
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  else document.documentElement.requestFullscreen().catch(() => {});
};

/* captura */
$("boton-captura").onclick = async () => {
  try {
    const r = await fetch("/api/captura");
    if (!r.ok) return;
    const url = URL.createObjectURL(await r.blob());
    const a = document.createElement("a");
    a.href = url;
    a.download = "captura-pc.jpg";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  } catch (e) {}
};

/* reconectar */
$("btn-reconectar").onclick = () => {
  desconectar();
  activarPanelNulo();
  setTimeout(conectar, 400);
};

/* cerrar sesión */
$("boton-salir").onclick = cerrarSesion;
$("btn-cerrar-sesion").onclick = cerrarSesion;

/* ajustes */
$("sel-calidad").onchange = enviarConfig;
$("sel-pantalla").onchange = enviarConfig;
$("sel-fps").oninput = () => { $("valor-fps").textContent = $("sel-fps").value; };
$("sel-fps").onchange = enviarConfig;

/* acceso */
$("btn-entrar").onclick = entrar;
$("campo-clave").addEventListener("keydown", (e) => { if (e.key === "Enter") entrar(); });

/* ============ estado del sistema ============ */
function barra(pct) {
  const p = limite(pct, 0, 100);
  const clase = p > 88 ? "peligro" : p > 70 ? "aviso" : "";
  return `<div class="barra"><i class="${clase}" style="width:${p}%"></i></div>`;
}
function gb(n) { return n >= 100 ? `${Math.round(n)} GB` : `${n} GB`; }
function segsAHora(s) {
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return h > 24 ? `${Math.floor(h / 24)} días ${h % 24} h` : `${h} h ${m} min`;
}

async function obtenerEstado() {
  if ($("vista-principal").hidden) return;
  try {
    const r = await fetch("/api/estado");
    if (r.status === 401) { mostrarAcceso(); return; }
    const d = await r.json();
    renderEstado(d);
  } catch (e) {
    $("texto-estado").textContent = "PC no responde";
    $("punto-estado").className = "punto rojo";
  }
}
setInterval(obtenerEstado, 2500);
setInterval(() => { if ($("vista-principal").hidden && S.ws === null && S.img) mostrarPrincipal(); }, 15000);

function renderEstado(d) {
  procesarAvisos(d);
  if (d.volumen) aplicarVolumenUI(d.volumen);
  if (d.uac) {
    const silencioso = d.uac.modo === "silencioso";
    $("estado-uac").textContent = silencioso ? "modo silencioso ✓" : "preguntando (UAC activo)";
    $("btn-uac").textContent = silencioso ? "🔊 Volver a pedir permisos" : "🔒 Dejar de preguntar";
  }
  const bateria = d.bateria
    ? `<div class="linea"><span>Batería</span><span>${d.bateria.pct}% ${d.bateria.enchufado ? "⚡" : "🔋"}</span></div>`
    : "";
  const discos = (d.discos || []).map((dd) =>
    `<div class="linea"><span>Disco ${dd.montaje}</span><span>${dd.pct}% usado · ${gb(dd.libre_gb)} libres</span></div>`
  ).join("");
  const procs = (d.procesos || []).map((p) =>
    `<li><span>${p.nombre}</span><span class="texto-gris">${p.cpu.toFixed(1)}%</span></li>`
  ).join("");

  $("cuerpo-estado").innerHTML = `
    <div class="fila-estado"><span class="etiqueta">CPU</span>${barra(d.cpu)}<span class="dato">${d.cpu}%</span></div>
    <div class="fila-estado"><span class="etiqueta">RAM</span>${barra(d.ram_pct)}<span class="dato">${d.ram_pct}%</span></div>
    <div class="subtitulo">Detalles</div>
    <div class="tarjeta-grupo">
      <div class="linea"><span>RAM usada</span><span>${gb(d.ram_usada_gb)} de ${gb(d.ram_total_gb)}</span></div>
      ${bateria}
      ${discos}
      <div class="linea"><span>Red ahora</span><span>↓${d.red_baja_kbps} kB/s · ↑${d.red_sube_kbps} kB/s</span></div>
      <div class="linea"><span>Total red</span><span>↓${d.red_total_baja_gb} GB · ↑${d.red_total_sube_gb} GB</span></div>
      <div class="linea"><span>Encendido</span><span>${segsAHora(d.encendido_s)}</span></div>
      <div class="linea"><span>Equipo</span><span>${d.host || "?"}</span></div>
      <div class="linea"><span>Servidor</span><span>${d.privilegio === "administrador" ? "administrador ✓ (puede rechazar UAC)" : "usuario normal"}</span></div>
      <div class="linea"><span>Sistema</span><span class="texto-gris">${(d.os || "").slice(0, 28)}</span></div>
    </div>
    <div class="subtitulo">Procesos más pesados</div>
    <div class="tarjeta-grupo"><ol class="procesos">${procs || "<li><span class='texto-gris'>—</span></li>"}</ol></div>
  `;

  const urls = (d.ips || [])
    .map((i) => `<b>http://${i.ip}:${d.puerto}/app/</b> <span class="texto-gris">(${i.nombre})</span>`)
    .join("<br>");
  const tsNota = d.tailscale
    ? '<br><b>✅ Tailscale activo</b>: usa la dirección 100.x.y.z que aparece arriba para conectarte desde fuera de casa.'
    : '<br><span class="texto-gris">💡 Instala Tailscale en la PC y el teléfono para acceder desde cualquier lugar (ver instrucciones).</span>';
  $("info-acceso").innerHTML =
    `<div class="subtitulo">Direcciones para conectar desde otra red</div>${urls}${tsNota}`;
}

/* ============ teclado ============ */
const MODS_ACTIVOS = new Set();
document.querySelectorAll(".chip").forEach((chip) => {
  chip.onclick = () => {
    const m = chip.dataset.mod;
    if (MODS_ACTIVOS.has(m)) MODS_ACTIVOS.delete(m);
    else MODS_ACTIVOS.add(m);
    chip.classList.toggle("activa", MODS_ACTIVOS.has(m));
  };
});

function comboActual() { return [...MODS_ACTIVOS]; }
function limpiarMods() { MODS_ACTIVOS.clear(); document.querySelectorAll(".chip").forEach((c) => c.classList.remove("activa")); }

document.querySelectorAll("[data-k]").forEach((b) => {
  b.onclick = () => {
    enviar({ t: "teclas", mods: comboActual(), k: b.dataset.k });
    if (comboActual().length) limpiarMods();
  };
});
document.querySelectorAll("[data-combo]").forEach((b) => {
  b.onclick = () => {
    const partes = b.dataset.combo.split("+");
    const k = partes.pop();
    enviar({ t: "teclas", mods: [...comboActual(), ...partes], k });
    if (comboActual().length) limpiarMods();
  };
});

/* fila F1..F12 */
const fila = $("fila-funciones");
for (let i = 1; i <= 12; i++) {
  const b = document.createElement("button");
  b.textContent = "F" + i;
  b.dataset.k = "f" + i;
  b.onclick = () => {
    enviar({ t: "teclas", mods: comboActual(), k: "f" + i });
    if (comboActual().length) limpiarMods();
  };
  fila.appendChild(b);
}

function enviarTexto() {
  const campo = $("campo-texto");
  const s = campo.value;
  if (s.length) {
    enviar({ t: "texto", s });
    campo.value = "";
    campo.focus();
  }
}
$("btn-enviar-texto").onclick = enviarTexto;
$("campo-texto").addEventListener("keydown", (e) => {
  if (e.key === "Enter") { e.preventDefault(); enviarTexto(); }
});

/* ============ arranque ============ */
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}

(async () => {
  // si la cookie sigue válida, entra directo
  try {
    const r = await fetch("/api/estado");
    if (r.ok) { mostrarPrincipal(); conectar(); }
  } catch (e) { /* sin conexión: queda la pantalla de acceso */ }
})();
