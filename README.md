# Control PC — controla tu computadora desde el teléfono

> 🖥️➡️📱 Ve la pantalla de tu PC **en vivo** en tu teléfono y úsala con los dedos:
> ratón, teclado, atajos, e incluso revisa la salud del sistema desde cualquier lugar.
> Funciona **sin internet en casa** y **por internet** con Tailscale. 100% gratuito y local.

---

## 📥 ¿Qué descargo?

| Deseo | Cómo |
|---|---|
| **Controlar mi PC desde el teléfono** | Descarga todo el código (botón verde *Code* → *Download ZIP*, o `git clone`), descomprime, ve a `ControlPC/servidor` y ejecuta `iniciar.bat` |
| **APK nativa de Android** | Pestaña **Releases** de este repositorio (si está publicada) o compílala gratis con GitHub Actions (sección APK más abajo) |

## 🚀 Inicio rápido (3 pasos)

> 🔒 **Importante:** cada quien controla **su propia computadora**. Cuando ejecutes
> el servidor, verás **TU IP y TU contraseña**. No existe un servidor central:
> tu teléfono se conecta directamente a tu PC, y nadie más puede verla sin tu
> contraseña y sin tu IP exacta.

### 1) En la PC (Windows)
- Requisito: [Python 3.10+](https://www.python.org/downloads/) (marca *"Add python.exe to PATH"*).
- Doble clic en `servidor\iniciar.bat` — la primera vez instala las librerías.
- Acepta el permiso del **Firewall de Windows** que aparecerá (casilla de *redes privadas* marcada).
- Aparecerá una ventana con código QR, la **dirección** y la **contraseña aleatoria**:

```
Abre en el teléfono:  http://192.168.1.50:8566/app/   <- TU IP exacta se muestra ahí
Contraseña:           ABCD2345                        <- ejemplo, la tuya será otra
```

### 2) En el teléfono
- Con **Chrome**, estando en el **mismo Wi-Fi**, abre la dirección (o escanea el QR).
- Escribe la contraseña que apareció en la PC y pulsa Conectar.
- Menú ⋮ → **Añadir a pantalla de inicio** → tendrá el icono como una app.

### 3) Úsala
Toca la pantalla, mueve el ratón, escribe, desliza, abre `cualquier cosa`. 🎉

## 🧭 Controles táctiles

| Gesto | Acción |
|---|---|
| 👆 Toque | clic izquierdo |
| 👆👆 Doble toque | doble clic |
| ✊ Mantener 0,6 s | clic derecho (vibra el teléfono) |
| 🖐️ Arrastrar 1 dedo | mover el ratón; si lo mantienes y mueves, **arrastra ventanas** |
| 🖱️ Botón "Puntero" (barra) | modo libre: el arrastre solo MUEVE el ratón sin presionar, para recorrer menús |
| ☝️☝️ 2 dedos ↑↓ | rueda del ratón (scroll) |
| 🤏 Pellizco | zoom de la vista (con zoom, 1 dedo desplaza la vista) |

Extras en la app: **📊 Estado** (CPU, RAM, batería, discos, red, procesos y tiempo encendido),
**⌨️ Teclado** (soporta **ñ/á/é**, F1–F12, flechas, y atajos: Alt+Tab, Ctrl+Alt+Supr,
Win+D/E/R/L, Alt+F4, admin. de tareas...), **⚙️ Ajustes** (calidad/FPS/monitor),
📷 captura de pantalla y ⛶ pantalla completa.

> 🎯 La **flecha del ratón se dibuja en el video** para que siempre sepas dónde está;
> se vuelve **roja** cuando el botón está presionado.

## 📶 ¿Sin internet? — Uso en LAN pura

El servidor **no necesita internet**: solo que la PC y el teléfono estén en la misma red.

- Puedes usar el Wi-Fi del router aunque no tenga internet.
- O sin router: activa **Punto de acceso móvil** en Windows (Configuración → Red e Internet)
  y conecta el teléfono a esa red. La app detecta la nueva IP automáticamente y te la muestra
  en el panel 📊 Estado → "Direcciones para conectar".

## 🌍 Desde cualquier lugar del mundo — Tailscale

1. Instala [Tailscale](https://tailscale.com/download) en la PC y en el teléfono (gratis).
2. Inicia sesión con **la misma cuenta** en ambos.
3. La PC recibirá una IP del tipo `100.x.y.z` (la app la lista en panel Estado).
4. Desde cualquier sitio: abre `http://100.x.y.z:8566/app/` — cifrado extremo a extremo,
   **sin abrir puertos del router**.

## 📦 APK nativa (opcional)

Dos caminos para generar la `app-release.apk`:

**A — Con GitHub gratis (recomendado):**
1. Sube este proyecto a tu GitHub (*New repository → Upload files* o `git push`).
2. Pestaña **Actions** → workflow **"APK"** → **Run workflow**.
   - Si marcas la casilla *"Publicar en Releases"*, la APK aparecerá en la pestaña **Releases**
     para que cualquiera la descargue sin cuenta de GitHub.
3. Instala la APK en el teléfono (permite *fuentes desconocidas*).

**B — En tu PC con Flutter:**
```bat
cd apk-flutter
flutter create . --org com.controlpc.app --project-name controlpc --platforms=android
flutter pub get
flutter build apk --release
```
La APK queda en `apk-flutter\build\app\outputs\flutter-apk\app-release.apk`.
Más detalles en [`apk-flutter/README-APK.md`](apk-flutter/README-APK.md).

## ⚙️ ¿Cómo funciona por dentro?

```
   TELEFONO (PWA / APK)                 PC (Windows, Python)
 ┌─────────────────────────┐        ┌──────────────────────────────────┐
 │ <canvas> dibuja JPEGs    │  WS ─▶ │ servidor.py + uvicorn (puerto…)  │
 │ capturas: 10-30 fps      │ ◀─ WS  │  • mss: captura la pantalla      │
 │ gestos → JSON de eventos │        │  • Pillow: escala + JPEG + flecha│
 │ /api/estado → tarjetas   │ HTTP ▶ │  • psutil: CPU/RAM/discos/red    │
 │ login (cookie 90 días)   │        │  • pyautogui: ratón/teclado real │
 └─────────────────────────┘        └──────────────────────────────────┘
```

- **Un único WebSocket** (`/ws`) lleva el video y los comandos en dos direcciones.
- El teléfono manda eventos JSON y la PC los ejecuta: `mover`, `pulsar`, `soltar`,
  `clic`, `deslizar` (rueda), `texto` (con ñ/á/é → portapapeles), `teclas` (combos),
  `cfg` (calidad en vivo).
- Las sesiones usan **cookie `httpOnly` + token aleatorio**, guardadas en el disco,
  para que al reiniciar la PC **no pida la contraseña de nuevo**.
- El hilo de *estado* sondea el sistema cada 2,5 s y expone `/api/estado`.

### Archivos que genera
| Archivo | Qué es |
|---|---|
| `servidor/config.json` | puerto, contraseña (se crea sola la primera vez) |
| `servidor/sesiones.json` | sesiones activas (no las publiques) |

⚠️ Ambos están en `.gitignore`: **nunca se suben al repositorio** con tu contraseña.

## 🔒 Seguridad y privacidad

### ¿Puede alguien ver mi PC por usar este programa? **No.**

- **No hay servidor central:** el programa corre **en tu propia PC** y solo sirve *tu* pantalla.
  Cada quien se conecta a la **suya**; los datos de una PC no están en ningún lugar de la nube.
- No se envía ningún dato a terceros: no hay analítica, ni registro remoto, ni "llamadas a casa".
- Tu pantalla solo llega a quien abra la dirección `http://<TU-IP>:8566/app/` y **también** tenga
  tu contraseña (se genera aleatoria al primer arranque, distinta en cada PC).
- Tu IP de red local (`192.168.x.x`) **no es alcanzable desde internet** — solo tu teléfono
  en la misma red puede conectarse. Para acceder desde fuera de casa se usa **Tailscale**,
  que solo autoriza a los dispositivos de tu propia cuenta que TÚ apruebes.
- Existen límites antifuerza bruta (bloqueo tras 8 intentos fallidos por minuto).
- **Ciclo de 90 días:** por seguridad la contraseña se **renueva automáticamente** cada 90 días.
  Al hacerlo, la clave nueva se muestra en la PC (consola + ventana emergente, también al
  arrancar con `autoinicio.bat`) y las sesiones anteriores se invalidan: vuelve a escribir
  la clave en el teléfono. El panel 📊 Estado mostra cuántos días de ciclo quedan.
- Puedes cambiar la contraseña cuando quieras editando `servidor/config.json` y reiniciar
  el servidor. Borrar esos archivos no rompe nada: se regeneran automáticamente.

- Sin HTTPS por defecto: úsalo **en redes de confianza**. Para acceso remoto,
  Tailscale cifra todo el camino (equivalente/versión superior a HTTPS doméstico).
- Para exponer directo a internet (nada recomendado) necesitarías un túnel con HTTPS
  (Cloudflare Tunnel / cert + `cert.pem`/`clave.pem` — el servidor los usa si existen).

## 🧩 Requisitos

- PC: **Windows 10/11**, Python 3.10+ — librerías: `fastapi`, `uvicorn`, `mss`, `Pillow`,
  `psutil`, `pyautogui`, `qrcode` (`requisitos.txt`, se instalan solas con el .bat).
- Teléfono: navegador moderno (Chrome/Edge/Brave). Toque y vibración opcionales.
- APK: Android 8+.

## 🛠️ Solución de problemas

| Problema | Solución |
|---|---|
| El teléfono no conecta | Verifica misma red (o hotspot) y la IP exacta que imprime la consola. |
| Firewall bloquea | Permite "redes privadas" en la ventana de Windows, o abre el puerto elegido (8566) en el Firewall. |
| Video lento | Baja calidad/frames en ⚙️ Ajustes; usa 5 GHz, o Tailscale. |
| Cursor invisible | Ya no pasa: la flecha se dibuja en el video. Actualiza la página. |
| Instalar "app" en Chrome sin HTTPS | Chrome solo ofrece *Añadir a pantalla de inicio* (que funciona); la APK nativa es la experiencia instalada. |
| Pantalla negra en UAC/Bloqueo | Windows protege esas pantallas; ningún software normal puede verlas. Desbloquea físicamente y vuelve a tomar control. C:*Ctrl+Alt+Supr* sí llega al usuario de la sesión. |
| Arranque automático al encender la PC | Ejecuta `servidor\autoinicio.bat` una vez (crea acceso directo en shell:startup). |

## 🗂️ Estructura

```
ControlPC/
├── servidor/          servidor Python (Windows)
│   ├── iniciar.bat      arranca el servidor (con auto-reinicio)
│   ├── iniciar_admin.bat  igual, pero como ADMINISTRADOR
│   ├── autoinicio.bat   tarea simple al encender la PC
│   ├── autoinicio_todos.bat  configura TODO el autoarranque
│   ├── servidor.py      todo el servidor (captura + eventos + estado + audio + avisos)
│   ├── requisitos.txt   librerías a instalar
│   └── estatico/        la PWA del teléfono (HTML/JS/CSS)
├── apk-flutter/       proyecto APK nativo (opcional)
└── .github/workflows/apk.yml   compila la APK en GitHub gratis
```

## 🔔 Novedades incluidas

- **Avisos del sistema en el teléfono**: batería baja/cargando, RAM al límite,
  disco casi lleno, CPU sostenida alta y conexión/desconexión del teléfono
  aparecen como notificaciones flotantes en la app (con lista en el panel 📊).
- **Audio en vivo de la PC**: botón 🔊 junto al estado → *"Escuchar el sonido de la PC"*
  (captura loopback, ~48 kHz) más control de volumen y silencio.
- **Ventanas de seguridad (UAC)**: cuando aparece una ventana de permisos en la PC,
  el teléfono recibe una notificación con **✅ Permitir** (activa el modo silencioso,
  los avisos dejan de molestar) y **🚫 Rechazar** (cierra la ventana, requiere
  `iniciar_admin.bat`). Nota de Windows: la ventana de UAC en sí no se puede clicar
  remotamente (escritorio seguro); por eso "rechazar" la mata y "permitir" la evita a futuro.

## 🤝 Contribuir

Ideas que serían bienvenidas: captura con la API `DXGI`, transmitir sonido,
muchos más atajos del teclado, cliente para iOS con TouchID, modo oscuro/claro…
Abre un *issue* o manda un *pull request* 🚀

## 📜 Licencia

MIT — libres de usar, copiar y modificar. Ver [`LICENSE`](LICENSE).
