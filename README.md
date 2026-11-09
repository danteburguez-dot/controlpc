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
| **`CONTROL-PC.bat`** | ⭐ **MENÚ MAESTRO — el ÚNICO `.bat`**: servidor [1], admin [2], login+QR [3], firewall [4], autoarranque [5], Tailscale [6], auditoría [7], hotspot [8] e **INSTALAR TODO [9]** (Python + las 12 librerías; todo fusionado adentro: ya no hay `.bat` separados) | ✅ la forma más cómoda de usar todo |
| `config.json` | guarda tu contraseña y ajustes (no se borra al actualizar) | no tocar |

> La contraseña la ves en la **consola** al arrancar, o con la opción **[3]**
> del `CONTROL-PC.bat` (con los
> QR para conectar el teléfono a un toque: el QR rápido lleva la clave dentro y
> cambia solo cuando la clave cambia).
> Windows te pedirá "Permitir acceso" la primera vez: acepta (con *redes privadas*).

## 🔥 El clásico primer tropiezo — el Firewall

Windows **bloquea** las conexiones entrantes por defecto. Si la APK te dice
*"No se pudo conectar: ... el Firewall de la PC tenga la regla Control PC"*:

1. Doble clic en **`CONTROL-PC.bat`** y elige la opción **[4] FIREWALL**.
2. Acepta la ventana amarilla de Windows (botón **Sí**).
3. Saldrá *"REGLA CREADA"* — ahora el teléfono entra sin problema.

(Solo una vez por PC. Crea la regla del puerto 8566 **y la de `python.exe`**
por si acaso; **esta es la razón número 1** por la que "no conecta" aún.)

## 🦇 Guía del MENÚ MAESTRO (`CONTROL-PC.bat` — todos adentro)

### ⭐ `CONTROL-PC.bat` — 🎛️ "CONTROL PC - MAESTRO" (todo en uno)
- Un solo `.bat` con **menú interactivo**:
  ```
  ============================================================
               CONTROL PC - MENU MAESTRO
  ============================================================
    [1] Abrir el servidor (normal)
    [2] Servidor como ADMINISTRADOR (permite [o] rechazar UAC desde telefono)
    [3] Login: ver contrasena / renovarla (Y/N) - con QR
    [4] FIREWALL: permitir el telefono (si no conecta, corre ESTO)
    [5] Autoarranque completo (server al encender la PC)
    [6] Tailscale: acceso desde CUALQUIER lugar del mundo
    [7] Auditoria de paquetes (ve que bloquea al telefono)
    [0] Salir
  ```
- Si prefieres los `.bat` individuales: siguen existiendo y funcionan igual.

- **Todas las funciones están fusionadas DENTRO del maestro**: ya no existen `.bat` separados.

### 🎛️ Qué hace cada opción del `CONTROL-PC.bat`

| Opción | Qué hace |
|---|---|
| **[1]** | 🖥️ **Servidor normal**: la primera vez instala las librerías y muestra IP + contraseña + los 2 QR; si se cae se reinicia solo cada 3 s; si ya corre otra instancia, sale limpio sin duplicar. |
| **[2]** | 🛡️ **Servidor ADMINISTRADOR**: como [1] pero elevado (necesario para 🚫 rechazar UAC desde el teléfono) y fija la regla del Firewall de una vez. |
| **[3]** | 🔑 **Login + QR**: contraseña actual, ciclo restante y **2 QR por cada red** activa (Wi-Fi, hotspot, VPN, Tailscale…). El QR **RÁPIDO lleva la clave dentro**; escribiendo **Y** renueva la clave y corta todas las sesiones. |
| **[4]** | 🔥 **Firewall**: crea la regla del puerto 8566 **y la regla de programa para `python.exe`** (una vez, acepta el permiso). |
| **[5]** | 📌 **Autoarranque completo**: tarea programada del servidor ADMINISTRADOR + respaldo de 60 s si el admin no pudiera arrancar. |
| **[6]** | 🌍 **Tailscale**: lo instala si falta, entra a tu cuenta y muestra la IP `100.x.y.z` + QR — acceso **desde cualquier lugar del mundo**. |
| **[7]** | 🕵️ **Auditoría de paquetes**: 90 s grabando los intentos de conexión del teléfono → deja el resultado en `servidor\eventos_8566.txt`. |
| **[8]** | 📶 **HOTSPOT** automático de Windows: el teléfono entra directo a la red de la PC **sin router**. |
| **[9]** | 📦 **INSTALAR TODO en una PC nueva**: instala **Python 3.12** — la estable que trae *todas* las librerías de Windows ya compiladas (evita el error de "Microsoft C++ Build Tools" con las Python recién salidas) — **+ las 12 librerías** de `requisitos.txt`, con reintentos solo de ruedas y comprobación de imports al final. Después, todas las opciones ([1]/[2]/[3]/[6]) usan ese Python automáticamente. |

- Los modos especiales `--loginqr`, `--tailscale` y `--rotar` de `servidor.py` son los que el maestro ejecuta internamente.

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
│   ├── CONTROL-PC.bat          ← PC: ⭐ MENÚ MAESTRO (el único .bat: enciende TODO)
│   ├── servidor.py             ← motor del servidor
│   └── estatico/               ← interfaz web del teléfono
├── pruebas_apk.py              ← 20 pruebas automáticas (20/20 = todo sano)
├── apk-flutter/                ← código de la APK (solo si quieres recompilar)
└── .github/workflows/apk.yml   ← GitHub compila la APK gratis
```

## 🚀 Inicio rápido (3 pasos)

### �viamente 1) En la PC (Windows)
- Requisito: [Python 3.10+](https://www.python.org/downloads/) (marca *"Add python.exe to PATH"*).
- Doble clic en `servidor\CONTROL-PC.bat` → opción **[1]** — la primera vez instala las librerías.
- Acepta el permiso del **Firewall de Windows** que aparecerá (casilla de *redes privadas* marcada).
- Aparecerá una ventana con código QR, la **dirección** y la **contraseña aleatoria**:

```
Abre en el teléfono:  http://192.168.1.50:8566/app/   <- TU IP exacta se muestra ahí
Contraseña:           ABCD2345                        <- ejemplo, la tuya será otra
```

### ⭐ 2) Conecta el teléfono — **TALSICALE (la forma RECOMENDADA)**

> 🌍 **La mejor forma de conectar SIEMPRE funciona, en cualquier red y a cualquier distancia.**
> Sin importar el router, pensado para que el "Wi-Fi de casa no aparezca" o "aísla los aparatos"
> — con Tailscale no importa: el録túnel cifrado conecta PC y teléfono directamente. Una vez
> instalado y conectado, ya nunca dejes de usarlo ni configuras nada.

1. **En la PC**: doble clic en **`CONTROL-PC.bat`** (menú maestro) → opción **[6] Tailscale** → instala y abre el login → entra con tu cuenta (Google/GitHub).
2. **En el teléfono**: instala la app **"Tailscale"** desde la Play Store → abre e inicia con **la MISMA cuenta** → activa el botón **"Connected"**.
3. Abre la APK "Control PC" (o la web) y escribe la **IP 100.x.y.z de tu PC** (imprimida en pantalla) + la contraseña → **Conectar** ✅

> 💡 Con Tailscale: puedes estar en otro país, con datos móviles, en el wi-fi de la madre,
> en un avión — la conexión SIEMPRE funciona. Sin depender del router ni del firewall.

** Alternativa rápida (misma red Wi-Fi, sin instalar nada):**
- Con **Chrome**, estando en el **mismo Wi-Fi**, abre la dirección (o escanea el QR).
- Escribe la contraseña que apareció en la PC y pulsa Conectar.
- Menú ⋮ → **Añadir a pantalla de inicio** → tendrá el icono como una app.

### 3) Úsala
Toca la pantalla, mueve el ratón, escribe, desliza, abre `cualquier cosa`. 🎉

> �摄像机 Nota: si tu router **aisla los aparatos** entre sí (a veces configurado por el ISP), la
> conexión por el Wi-Fi de casa puede fallar con "No route to host" — usa el **hotspot de la PC**
> (Configuración → Punto de acceso móvil) o **Tailscale** que es la vía recomendada.

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

## 🔀 ¿Qué IP pongo según dónde esté? (tabla de modos)

La **misma PC** se anuncia con distinta dirección según por dónde hables con ella.
**⭐ TAILSCALE es la forma recomendada** — funciona en cualquier red del mundo (datos móviles, wi-fi ajeno, otra ciudad).

| El teléfono está en… | IP que pones en la APK/web | Recomendación |
|---|---|---|
| 🌍 **Cualquier red / país / datos móviles** | `100.x.y.z` (**Tailscale** activo en ambos) | ⭐ **RECOMENDADA** |
| 📶 El **hotspot de la PC** (Punto de acceso móvil de Windows) | `192.168.137.1` (fijo de Windows) | ✅ garantizado si el router aísla |
| 🏠 El Wi-Fi de la casa (el mismo que la PC) | `192.168.100.x` (la IP exacta imprime la consola) | ⚠️ puede fallar si el router aísla |

> 💡 Las apps teléfonos a veces **bloquean el Wi-Fi local** de fábrica (aislamiento de aparatos):
> si el Wi-Fi de casa te falla, usa el **hotspot de la PC** (el camino garantizado) o Tailscale.

## 🌍 Desde cualquier lugar del mundo — col conectar la pantalla de la PC (nivel de TAILSCALE)

**Esto es lo mejor de Control PC: cambia de país, red o ciudad y tu teléfono alcanza la pantalla/lOS APPS de tu PC con el túnel externo de Tailscale.**

> IMPORTANTE: prue una vez y listo. Tailscale queda cifrado y cargado para SIEMPRE en los dos aparatos. Es gratis para uso personal y NO requiere anular ninguna seguridad del router.

### 🖥️ PASO 1 — En la PC

1. Descarga e instala Tailscale (gratuito):
   - La forma más fácil: doble clic en **`CONTROL-PC.bat`** → opción **[6] Tailscale**.
   - Manual en terminal: **`winget install -e --id Tailscale.Tailscale`**
   - O desde https://tailscale.com/download
2. Haz el login (se abre tu navegador):
   ```
   "C:\Program Files\Tailscale\tailscale.exe" up
   → entra con tu cuenta de Google/GitHub/Apple y acepta
   ```
3. Verifica la dirección IP de tu PC:
   ```
   "C:\Program Files\Tailscale\tailscale.exe" ip -4
   → devolverá una IP tipo: 100.126.1.3
   ```
   Esta IP es fija: NO cambia nunca (es la dirección permanente de la PC en la red Tailscale).

### 📱 PASO 2 — En el teléfono

1. Descarga la app **Tailscale** en la Play Store (búsqueda: "Tailscale", icono de biblioteca con candado).
2. Ábrelo y haz el mismo login: entra con la MISMA cuenta que usó la PC (un solo toca + autorización).
3. Activa el botón **"Connected"** (Toggle ON) en la app.
4. Verás en la lista de dispositivos tu PC y tu teléfono juntos (dos nombres).

### 📲 PASO 3 — Ver la pantalla de la PC desde el teléfono (desde dónde sea)

Con el servidor Control PC **abierto en la PC** (doble clic en `iniciar` o autoarranque activo):

1. Abre la APK de tu teléfono "Control PC".
2. En la pantalla de acceso escribe:
   - **Dirección IP**: `100.x.y.z` ← la IP Tailscale que imprimió tu PC (ej: `100.126.1.3`)
   - **Puerto**: `8566`
   - **Contraseña**: la vigente del servidor (aparece en la consola de la PC o en la opción [3] del maestro)
3. Conectar → la pantalla de tu PC se ve en el teléfono en vivo.
4. Para pantalla completa (solo la PC acostado sin botones): pestaña Pantalla → botón **⛶**.

### ¿Por qué funciona el cambio de red?

- El teléfono puede estar en **cualquier red/distintos nacionales**: 4G, 5G, Wi-Fi ajeno (hotel, casa amiga, aeropuerto), otra ciudad/country.
- El teléfono NO debe estar en el mismo Wi-Fi que la PC: envía via el túnel Tailscale que manda el vídeo en cifrado extremo a extremo (WireGuard).
- NO hay que abrir puertos del router ni tocar configuración de ninguna red.

### 🩺 Comprobar el túnel desde la PC:

```
"C:\Program Files\Tailscale\tailscale.exe" status        → de listar 2+ equipos con estado "active"
"C:\Program Files\Tailscale\tailscale.exe" ping 100.x.y.z → debe decir "pong"
"C:\Program Files\Tailscale\tailscale.exe" netcheck      → calidad y tipo del túnel
```

Si solo aparece tu PC: el teléfono aún no entró a la red Tailscale (app no instalada o cuenta diferente).

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

### Comandos de mantenimiento del servidor (modos extra)

| Comando | Qué hace |
|---|---|
| `python servidor.py --loginqr` | imprime la contraseña + los QR de TODAS las redes activas (el que usan las opciones [3] del menú) |
| `python servidor.py --rotar` | renueva la contraseña AHORA cfa corte de sesiones (como la opción "Y" del login) |
| `python servidor.py --tailscale` | muestra la IP 100.x.y.z de Tailscale + QR (acceso mundial) |
| `python servidor.py --prueba` | test rápido de módulos, pantallas y captura |

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
  arrancar la PC con el autoarranque) y las sesiones anteriores se invalidan: vuelve a escribir
  la clave en el teléfono. El panel 📊 Estado mostra cuántos días de ciclo quedan.
- Puedes cambiar la contraseña cuando quieras editando `servidor/config.json` y reiniciar
  el servidor. Borrar esos archivos no rompe nada: se regeneran automáticamente.

- Sin HTTPS por defecto: úsalo **en redes de confianza**. Para acceso remoto,
  Tailscale cifra todo el camino (equivalente/versión superior a HTTPS doméstico).
- Para exponer directo a internet (nada recomendado) necesitarías un túnel con HTTPS
  (Cloudflare Tunnel / cert + `cert.pem`/`clave.pem` — el servidor los usa si existen).

## 🛠️ Solución de problemas

| Problema | Solución |
|---|---|
| El teléfono no conecta | **Causa nº 1: el Firewall** → maestro **[4]** (una vez, acepta el permiso). Luego: misma red (o hotspot), y la IP exacta que imprime la consola. |
| La APK no conecta aunque todo esté bien | Corre `pruebas_apk.py` (20/20) y **usa la V 1.8+**: en pantalla muestra el **error EXACTO con dos fases** (TCP cruda + HTTP) — copia esa línea y resolvemos al instante. |
| Facebook / aislamiento de red | El ROUTER puede aislar teléfono↔PC: usa el **hotspot de la PC** (IP `192.168.137.1`) o Tailscale. |
| Firewall bloquea | Maestro **[4]** lo agrega por ti (con nombre "Control PC", puerto 8566 + regla de `python.exe`). |
| Video lento | Baja calidad/frames en ⚙️ Ajustes; usa 5 GHz, o Tailscale. |
| Cursor invisible | Ya no pasa: la flecha se dibuja en el video. Actualiza la página. |
| Instalar "app" en Chrome sin HTTPS | Chrome solo ofrece *Añadir a pantalla de inicio* (que funciona); la APK nativa es la experiencia instalada. |
| Pantalla negra en UAC/Bloqueo | Windows protege esas pantallas; ningún software normal puede verlas. Desbloquea físicamente y vuelve a tomar control. Ctrl+Alt+Supr sí llega al usuario de la sesión. |
| Arranque automático al encender la PC | Maestro **[5]** una vez (tarea administrador + respaldo). Renovación de contraseña/ciclo: maestro **[3]**. |
| La APK dice "clave incorrecta" | Usa el ojo 👁 para ver lo que escribiste; la vigente la imprime el servidor o el maestro **[3]**. |

## 🗂️ Estructura

```
ControlPC/
├── servidor/              servidor Python (Windows)
│   ├── CONTROL-PC.bat     ⭐ MENÚ MAESTRO — el único .bat (opciones 1–9, [9] = INSTALAR TODO)
│   ├── regla_firewall.ps1  helper del Firewall
│   ├── servidor.py        todo el servidor (captura + eventos + estado + audio + avisos)
│   ├── requisitos.txt     librerías a instalar
│   └── estatico/          la PWA del teléfono (HTML/JS/CSS)
├── pruebas_apk.py         🧪 20 pruebas automáticas (todo verde = sano)
├── apk-flutter/           proyecto APK nativo (opcional)
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
  la opción **[2]** del maestro). Nota de Windows: la ventana de UAC en sí no se puede clicar
  remotamente (escritorio seguro); por eso "rechazar" la mata y "permitir" la evita a futuro.
- **Hotspot automático**: el servidor enciende el hotspot de Windows al arrancar
  (via WinRT) y muestra el SSID/clave del punto de acceso en pantalla — el teléfono
  se conecta directo a la PC **sin depender del router** (útil si tu router aísla
  los aparatos o tienes otro tipo de red).
- **Login con QR por cada red**: la opción **[3]** del maestro imprime los QR para cada red activa
  (Wi-Fi de casa, hotspot, VPN, Tailscale…) y el QR RÁPIDO lleva la clave dentro.
- **Menú maestro `CONTROL-PC.bat`**: un solo `.bat` interactivo con todas las
  opciones (servidor, admin, login, firewall, autoarranque, Tailscale, auditoría).
- **Rotación automática de clave**: cada 90 días la contraseña se renueva sola
  y aparecen la nueva en pantalla (consola + ventana de Windows). El maestro **[3]**
  te la imprime siempre y también la renueva a mano con **Y**.

## ⬇ Actualizaciones automáticas

- Cada servidor (y cada app) revisa si salió una versión nueva.
- En la **PC** aparece una ventana: *"¿Descargar y actualizar automáticamente?"* —
  al aceptar descarga, reemplaza el programa **conservando** tu `config.json`,
  sesiones y certificados, y se reinicia sola con la versión nueva.
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

## 🖥️📱 Comparación de versiones — de la primera hasta la actual

> ¡El proyecto ha evolucionado mucho! Esta tabla muestra qué tenías en cada
> versión y qué funciones hay disponibles en la **versión actual (V 1.13)**.

### 📅 Línea de versiones (orden cronológico)

| Versión | Fecha aprox | Qué cambió | ¿Funciona de un lugar remoto? | ¿Firefox/aparato? |
|---|---|---|---|---|
| **V 1.0.0** | Nov 7 más temprano | Servidor base + app web PWA (solo Chrome, sin instalacion) — pantalla, ratón táctil básico, teclado, estado CPU/RAM | ❌ Solo red local | ✅ Web |
| **V 1.0.4** | Nov 7 (la primera APK publicada) | Primera APK Flutter compilada — pantalla, estado básico, teclado | ❌ No conectaba (sin permiso INTERNET) | ✅ APK |
| **V 1.2.0** | Nov 7 mejorado | FLECHA DEL RATÓN visible + roja al presionar, sesiones persistentes, pantalla en vivo mejorada | ❌ No conectaba | ✅ APK |
| **V 1.3.0** | Nov 8 | Ojo 👁 para ver lo que escribiste, errores claros (401 vs conexión), QR login multi-red | ❌ No conectaba | ✅ APK |
| **V 1.4.0** | Nov 8 | Campo IP inteligente — acepta `ip:puerto` o el enlace completo pegado | ❌ No conectaba | ✅ APK |
| **V 1.5.0** | Nov 8 | NetworkSecurityConfig de Android — HTTP claro oficial | ❌ No conectaba | ✅ APK |
| **V 1.6.0** | Nov 8 | 🔥 **Permiso INTERNET en el manifest** (el bug más grande: sin él, Android bloqueaba TODOS los sockets) | ⚠️ alcanzaba el servidor | ✅ APK |
| **V 1.7.0** | Nov 8 | 🔥 **Cleartext multi-línea + completo** (el bloque restante: HTTP permitido) | ✅ ¡PRIMERA que conectó! | ✅ APK |
| **V 1.8.0** | Nov 8 | 🩺 **Autodiagnóstico en pantalla** (TCP cruda + HTTP muestra el error REAL del sistema Android o de red) · 🎛️ **MENÚ MAESTRO** · 🕵️ auditoría de paquetes · 📶 hotspot automático vía WinRT | ✅ | ✅ APK |
| **V 1.9.0** | Nov 8 | 🔊 **Audio GLOBAL persistente** (el sonido sigue corriendo si cambias de pestaña) · ⌨️ **teclado físico del teléfono** (Bluetooth/USB) ESCRIBE en la PC: letras, Shift/Ctrl/Alt/Win, Enter, esc, Tab, Supr, F1–12, flechas, Ñ, acentos… | ✅ | ✅ APK |
| **V 1.10.0** | Nov 8 | 📱⛶ **MODO PANTALLA COMPLETA** horizontal: se oculta TODO y quedas SOLO viendo la pantalla de la PC con wakelock (la pantalla no se apaga), el botón de atrás bloqueado, y un botón ✕ flotante minúscula para salir · 🔊 indicador sonando si el audio está activo | ✅ | ✅ APK |
| **V 1.11.0** | Nov 8 | 🖼️ pantalla completa con `fit completo`: la pantalla de la PC SIEMPRE cabe entera en el teléfono (antes se recortaban los bordes) | ✅ | ✅ APK |
| **V 1.12.0** | Nov 8 | 🎛️ **RUEDITA DE SCROLL flotante** (el `ruedita central`): botón 🖱 en la barra → aparece una ruedita al costado de la pantalla; deslízala con un dedo para subir/bajar la PC (también en pantalla completa) | ✅ | ✅ APK |
| **V 1.13.0** | Nov 8 | 🎙️ **MICRÓFONO del teléfono → la PC**: tu voz llega por los altavoces de tu PC · 📷 **CÁMARA del teléfono vista en la PC**: se abre una ventana "Cámara del teléfono" en tu PC (cámara trasera o frontal) | ✅ | ✅ APK |

### ✅ Comparación de funciones — qué hace cada versión

| Función | V 1.0 | V 1.2 | V 1.4 | V 1.7 | **V 1.13 (ACTUAL)** |
|---|---|---|---|---|---|
| Pantalla en la PC en el teléfono | ✅ web | ✅ APK | ✅ | ✅ | ✅ **pantalla completa y SIEMPRE completa (no se corta)** |
| Ratón táctil (toque/arrastrar) | ✅ | ✅ | ✅ | ✅ | ✅ + flecha visible + roja al presionar |
| Teclado en pantalla | ✅ básico | ✅ | ✅ | ✅ | ✅ ñ/acentos/F1–12/combos |
| Teclado FÍSICO conectado al teléfono | ❌ | ❌ | ❌ | ❌ | ✅ |
| Estado del sistema (CPU/RAM/etc) | ✅ | ✅ | ✅ | ✅ | ✅ + menú de ojos + 22 pruebas |
| Sonido de la PC en el teléfono | ❌ | ❌ | ❌ | ❌ | ✅ con volumen + silencio |
| El sonido sigue al cambiar de pestaña | ❌ | ❌ | ❌ | ❌ | ✅ |
| Avisos automáticos del sistema | ❌ | ❌ | ❌ | ❌ | ✅ |
| Ventanas UAC desde el teléfono | ❌ | ❌ | ❌ | ❌ | ✅ con ✅/🚫 |
| Pantalla completa horizontal | ❌ | ❌ | ❌ | ❌ | ✅ + wakelock |
| Ruedita de scroll en pantalla | ❌ | ❌ | ❌ | ❌ | ✅ flotante (subir/bajar con un dedo) |
| Micrófono del teléfono en la PC | ❌ | ❌ | ❌ | ❌ | ✅ tu voz por los altavoces de la PC |
| Cámara del teléfono en la PC | ❌ | ❌ | ❌ | ❌ | ✅ ventana "Cámara del teléfono" |
| Flecha del ratón visible | ❌ | ✅ | ✅ | ✅ | ✅ + roja al presionar |
| Contraseña con ojo 👁 | ❌ | ❌ | ✅ | ✅ | ✅ |
| Hotspot automático | ❌ | ❌ | ❌ | ❌ | ✅ |
| Tailscale documentado | parcial | parcial | parcial | ✅ | ✅ completo |
| Auto-actualización | ❌ | ✅ | ✅ | ✅ | ✅ |
| Menú maestro `.bat` | ❌ | ❌ | ❌ | ✅ | ✅ |
| Conecta desde Tailscale (cualquier país) | ❌ | ❌ | ❌ | ⚠️ solo web | ✅ APK |
| Sesiones con renovación de 90d | ❌ | ✅ | ✅ | ✅ | ✅ |

> 🍰 **Consejo**: si instalaste una versión vieja, la APK te avisa con la notificación
> 🔔 y con el boton "⬇ Instalar la versión V 1.13 ahora" en la pestaña Estado.
> Tu instalación vieja conserva todo (config, sesiones) sin pérdida.

## 📜 Licencia

MIT — libres de usar, copiar y modificar. Ver [`LICENSE`](LICENSE).

