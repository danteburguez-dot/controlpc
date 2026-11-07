# Control PC — controla tu computadora desde el teléfono

> 🖥️➡️📱 Ve la pantalla de tu PC **en vivo** en tu teléfono y úsala con los dedos:
> ratón, teclado, atajos, e incluso revisa la salud del sistema desde cualquier lugar.
> Funciona **sin internet en casa** y **por internet** con Tailscale. 100% gratuito y local.

---

## 📥 ¿Qué descargar? — archivos para PC y teléfono

### 💻 Para la PC (Windows) — el servidor

1. Botón verde **Code → Download ZIP** (arriba) → descomprime.
2. Entra a la carpeta **`ControlPC\servidor\`**. Ahí están:

| Archivo | Qué hace | ¿Doble clic? |
|---|---|---|
| **`1-permitir_telefono.bat`** | 🔥 **CORRELO PRIMERO**: agrega la **regla del Firewall** para que el teléfono pueda entrar (sin esto, la APK dirá "No se pudo conectar") | ✅ una sola vez, acepta el permiso |
| `iniciar.bat` | **abre el servidor** (lo común) | ✅ primera vez instala librerías y muestra IP + contraseña + QR |
| `iniciar_admin.bat` | lo mismo pero como ADMINISTRADOR (permite 🚫 rechazar UAC desde el teléfono) | opcional |
| `login.bat` | muestra la contraseña actual + **2 QR**: uno que conecta el teléfono sin escribir nada (la clave va dentro del QR) y otro normal — con **Y** renueva la clave y el QR | cuando quieras |
| `autoinicio_todos.bat` | deja configurado que **arranque solo** al encender la PC | una sola vez |
| `activar_tailscale.bat` | instala/conecta **Tailscale** y te imprime la IP 100.x + QR para acceso **desde cualquier lugar del mundo** | una vez por PC |
| `config.json` | guarda tu contraseña y ajustes (no se borra al actualizar) | no tocar |

> La contraseña la ves en la **consola** al arrancar, o con `login.bat` (con los
> QR para conectar el teléfono a un toque: el QR rápido lleva la clave dentro y
> cambia solo cuando la clave cambia).
> Windows te pedirá "Permitir acceso" la primera vez: acepta (con *redes privadas*).

## 🔥 El clásico primer tropiezo — el Firewall

Windows **bloquea** las conexiones entrantes por defecto. Si la APK te dice
*"No se pudo conectar: ... el Firewall de la PC tenga la regla Control PC"*:

1. Doble clic en **`1-permitir_telefono.bat`**.
2. Acepta la ventana amarilla de Windows (botón **Sí**).
3. Saldrá *"REGLA CREADA"* — ahora el teléfono entra sin problema.

(Solo una vez por PC. Los `.bat` `iniciar_admin.bat` / `1-permitir_telefono.bat`
hacen esto solo; **esta es la razón número 1** por la que "no conecta" aún.)

## 🦇 Guía completa de los 5 archivos `.bat`

### 1️⃣ `iniciar.bat` — 🖥️ "Control PC - Servidor"
- Doble clic = abre el servidor.
- Muestra: dirección, contraseña, y los 2 QR (rápido y normal).
- La primera vez instala las librerías.
- Si el servidor se cae, se reinicia solo cada 3 s.
- Si ya hay otra instancia corriendo → sale limpio sin duplicar.

### 2️⃣ `iniciar_admin.bat` — 🛡️ "Control PC - Administrador"
- Igual que el 1️⃣ pero como ADMINISTRADOR (aceptas su ventana una vez).
- Fija la regla del Firewall de una vez para no volver a preguntar.
- Necesario para poder 🚫 Rechazar las ventanas UAC desde el teléfono.

### 3️⃣ `login.bat` — 🔑 "Control PC - Login (contrasena)"
- Pantalla de LOGIN: muestra la contraseña actual, el ciclo restante, y los
  **2 QR de conexión por cada red disponible** (Wi-Fi, hotspot de la PC, VPN,
  Tailscale...). El QR **RÁPIDO lleva la clave dentro**: escanéalo con la cámara
  y el teléfono entra sin escribir nada (ideal para tus equipos). El QR
  **NORMAL** pide la contraseña (ideal para otras personas viendo tu pantalla).
- Aquí abajo pregunta: `Quiere obtener una nueva contrasena? Y/N`
- **Y** → renueva la clave, corta TODAS las sesiones y re-muestra la nueva
  con su QR nuevo (los QR cambian solos: llevan la clave dentro).
- **N** → no toca nada.
- El banner al arrancar el servidor muestra la misma lista multi-red.

### 4️⃣ `autoinicio.bat` — 📌 "Control PC - Autoarranque simple"
- Crea acceso directo en el Inicio de Windows para que el servidor se abra
  al encender (silencioso/minimizado).
- Sin ventanas de contraseña, solo arranca.

### 5️⃣ `autoinicio_todos.bat` — 📌 "Control PC - Autoarranque completo" (recomendado)
- Todo lo del 4️⃣ + tarea programada del servidor ADMINISTRADOR (arranca
  elevado al iniciar sesión, sin preguntar).
- Configura también respaldo retardado si el admin no pudiera arrancar.
- Se ejecuta una sola vez; para revertir:
  `schtasks /Delete /TN "ControlPC Servidor Admin" /F` y borra el atajo
  en `shell:startup`.

### 6️⃣ `activar_tailscale.bat` — 🌍 "Control PC - Tailscale (cualquier lugar)"
- Instala Tailscale (gratis) si falta y abre tu navegador para el login de
  cuenta (Google/GitHub…).
- IMPORTANTE: en el teléfono instala la app Tailscale y entra con LA MISMA cuenta.
- Al terminar muestra la IP `100.x.y.z` de tu PC y un QR: escanéalo y conectas
  desde CUALQUIER red del mundo (incluso PC y teléfono en redes distintas, datos
  móviles, otro país). También accesible como `python servidor.py --tailscale`.

### 📱 Para el teléfono (Android)

| Opción | Cómo |
|---|---|
| **APK instalable (recomendada)** | En este repositorio entra a 🏷️ **Releases** → descarga **`app-release.apk`** (de la versión más alta: v1.4.0) → instálala (si Android pregunta, marca *"Permitir de esta fuente"*) |
| **App web (sin instalar)** | Abre en Chrome: `http://<IP-de-tu-PC>:8566/app/` y usa "Añadir a pantalla de inicio" |

> En la APK escribe la IP de tu PC y la contraseña que muestra su consola. Listo.
>
> 💡 **La APK es amable**: el campo **Dirección IP acepta lo que pegues**
> (`http://192.168.100.27:8566/app/`, `ip:puerto` o solo la IP — se limpia solo),
> la contraseña tiene un **ojo 👁 para ver lo que escribiste**, y los errores
> avisan diferente si falló la **clave** (campo rojo) que la **conexión**
> (que te recuerda el `.bat` del Firewall).

### 🧾 Archivos que verás en el ZIP (referencia rápida)

```
ControlPC/
├── servidor/
│   ├── 1-permitir_telefono.bat ← 🔥 PC: correlo PRIMERO (permite el teléfono en el Firewall)
│   ├── iniciar.bat             ← PC: doble clic aquí
│   ├── iniciar_admin.bat       ← PC: versión administrador
│   ├── login.bat               ← PC: ver/renovar contraseña (Y/N) + QRs por red
│   ├── activar_tailscale.bat   ← PC: acceso desde cualquier lugar del mundo
│   ├── autoinicio_todos.bat    ← PC: autoarranque completo
│   ├── servidor.py             ← motor del servidor
│   └── estatico/               ← interfaz web del teléfono
├── pruebas_apk.py              ← 20 pruebas automáticas (20/20 = todo sano)
├── apk-flutter/                ← código de la APK (solo si quieres recompilar)
└── .github/workflows/apk.yml   ← GitHub compila la APK gratis
```

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
  `psutil`, `pyautogui`, `qrcode`, `numpy`, `soundcard`, `pycaw`, `comtypes`, `pywin32`
  (`requisitos.txt`, se instalan solas con el .bat).
- Teléfono: navegador moderno (Chrome/Edge/Brave). Toque y vibración opcionales.
- APK: Android 8+.

## 🧪 ¿Quieres verificar tu instalación? — 20 pruebas automáticas

En la raíz del proyecto vive `pruebas_apk.py`: simula una APK Android de punta
a punta contra tu servidor y valida además el archivo `.apk` descargado
(zip intacto, firma Android v2, plugin de audio dentro). Con el servidor
abierto corre:

```
python pruebas_apk.py
```

 dovrebbe decir **20/20 TODO VERDE**. Es también el diagnóstico recomendado
si algo falla después de actualizar (te dice exactamente qué pieza falló).

## 🛠️ Solución de problemas

| Problema | Solución |
|---|---|
| El teléfono no conecta | **Causa nº 1: el Firewall** → corre `1-permitir_telefono.bat` (una vez, acepta el permiso). Luego: misma red (o hotspot), y la IP exacta que imprime la consola. |
| Firewall bloquea | `1-permitir_telefono.bat` lo agrega por ti (con nombre "Control PC", puerto 8566). |
| Video lento | Baja calidad/frames en ⚙️ Ajustes; usa 5 GHz, o Tailscale. |
| Cursor invisible | Ya no pasa: la flecha se dibuja en el video. Actualiza la página. |
| Instalar "app" en Chrome sin HTTPS | Chrome solo ofrece *Añadir a pantalla de inicio* (que funciona); la APK nativa es la experiencia instalada. |
| Pantalla negra en UAC/Bloqueo | Windows protege esas pantallas; ningún software normal puede verlas. Desbloquea físicamente y vuelve a tomar control. Ctrl+Alt+Supr sí llega al usuario de la sesión. |
| Arranque automático al encender la PC | Ejecuta `servidor\autoinicio_todos.bat` una vez (tarea administrador + respaldo). Renovación de contraseña/ciclo: `login.bat`. |
| La APK dice "clave incorrecta" | Usa el ojo 👁 para ver lo que escribiste; la vigente la imprime el servidor o `login.bat`. |

## 🗂️ Estructura

```
ControlPC/
├── servidor/          servidor Python (Windows)
│   ├── iniciar.bat      arranca el servidor (con auto-reinicio)
│   ├── iniciar_admin.bat  igual, pero como ADMINISTRADOR
│   ├── login.bat        ver la contraseña y renovarla cuando quiras (Y/N)
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

## ⬇ Actualizaciones automáticas

- Cada servidor (y cada app) revisa si salió una versión nueva.
- En la **PC** aparece una ventana: *"¿Descargar y actualizar automáticamente?"* —
  al aceptar descarga, reemplaza el programa **conservando** tu `config.json`,
  sesiones, certificados y los `.bat`, y se reinicia sola con la versión nueva.
  Desde el teléfono también puedes dispararla (panel Aplicación → "🚀 Actualizar la PC").
- En la **APK**: la pestaña Estado muestra "⬇ Instalar la versión V X ahora" que
  descarga el archivo con barra de progreso y abre el instalador de Android.
  Primera vez marca "Permitir de esta fuente" (Android lo pide una sola vez).
- Con visitantes que activan el teléfono: si el servidor está desactualizado,
  la notificación 🔔 en el teléfono avisa igualmente.

## 🤝 Contribuir

Ideas que serían bienvenidas: captura con la API `DXGI`, transmitir sonido,
muchos más atajos del teclado, cliente para iOS con TouchID, modo oscuro/claro…
Abre un *issue* o manda un *pull request* 🚀

## 📜 Licencia

MIT — libres de usar, copiar y modificar. Ver [`LICENSE`](LICENSE).
