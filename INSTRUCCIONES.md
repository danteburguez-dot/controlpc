# Control PC — Instrucciones de uso

Aplicación que convierte tu PC en un **servidor de control remoto**: ves la pantalla
de la PC en tu teléfono y la controlas con los dedos, ves el estado del sistema
(CPU, RAM, batería, discos, red...) y envías teclado/atajos.

---

## 1. Arrancar el servidor en la PC

1. Doble clic en **`servidor\iniciar.bat`**.
   - La primera vez instala las librerías (unos 2 minutos) y luego queda corriendo.
2. Aparecerá una ventana con un **código QR y una dirección**, por ejemplo:

   ```
   Abre en el teléfono:  http://192.168.1.50:8566/app/   <- tu IP exacta la muestra la consola
   Contraseña:           ABCD2345                       <- ejemplo, la tuya será otra
   ```

3. **Puedes apuntar la cámara del teléfono al código QR** de la consola para abrir la app.

> Windows puede preguntar si quieres "permitir el acceso" — responde **Permitir**,
> y si preguntan por las redes, deja marcada la casilla de **redes privadas**.

## 2. Instalar la app en el teléfono

1. Abre la dirección (o el QR) en **Chrome** del teléfono, estando en el **mismo Wi-Fi** que la PC.
2. Escribe la **contraseña** y pulsa Conectar.
3. Menú ⋮ de Chrome → **"Añadir a pantalla de inicio"** (o "Instalar aplicación").
4. Ya tienes el icono **Control PC** en tu escritorio del teléfono, se abre en
   pantalla completa como una app normal.

## 3. Controles con los dedos

| Gesto | Acción |
|---|---|
| 👆 Toque | clic izquierdo |
| 👆👆 Doble toque | doble clic |
| ✊ Mantener 0,6 s | clic derecho (vibra) |
| 🖐️ Arrastrar 1 dedo | mover el ratón; si lo mantienes y mueves, arrastra ventanas |
| 🖱️ Botón "Puntero" (barra abajo) | modo libre: arrastrar solo MUEVE el ratón sin presionar, ideal para recorrer menús; los toques siguen haciendo clic |
| ☝️☝️ 2 dedos verticales | rueda del ratón (scroll) |
| 🤏 Pellizco 2 dedos | zoom de la vista (con zoom, 1 dedo desplaza la vista) |

> 🎯 La **flecha del ratón se ve en la imagen** del teléfono; se pone **roja** mientras
> mantienes el botón presionado (arrastre), así sabes exactamente dónde está y qué hace.

Barra inferior: **📊 Estado** (CPU/RAM/batería/discos/red/procesos),
**⌨️ Teclado** (escritura con ñ/á/é, F1-F12, flechas y atajos: Alt+Tab, Ctrl+Alt+Supr,
Win+D, Win+L, Win+E...), **⚙️ Ajustes** (calidad, fotogramas, monitor), zoom, 📷 captura
y ⛶ pantalla completa.

## 4. ¿Sin internet? — Conexión local

El sistema **no necesita internet para funcionar en casa**. Si tu router
se va de internet, la PC y el teléfono siguen conectados:

- **Mismo Wi-Fi**: conecta el teléfono al Wi-Fi del router aunque no tenga internet.
- **Hotspot de la PC**: en Windows: Configuración → Red e Internet →
  **Punto de acceso móvil** → actívalo y conecta el teléfono a esa red Wi-Fi.
  El servidor detecta esa nueva red automáticamente: mira en la app el panel
  📊 Estado → aparece la lista de **direcciones válidas** según tu conexión.

## 5. Fuera de casa — Acceso por internet (Tailscale)

1. Instala **Tailscale** gratis en la PC desde https://tailscale.com/download
   e inicia sesión con tu cuenta (Google, GitHub, etc.).
2. Instala la app de **Tailscale** en el teléfono e **inicia sesión con la MISMA cuenta**.
3. Listo. La PC tendrá una IP como `100.x.y.z`: la app la muestra en el panel
   📊 Estado (se ve una línea "Tailscale activo"), o revisa la red Tailscale.
4. Desde cualquier lugar del mundo (con datos móviles), abre
   `http://100.x.y.z:8566/app/` y controla tu PC igual que en casa.

> Tailscale crea un túnel cifrado entre tus equipos: **no hay que abrir puertos
> del router**, y es mucho más seguro que exponer la PC a internet directo.

## 6. Que el servidor arranque siempre (PC lista siempre que la necesites)

- Doble clic en **`servidor\autoinicio.bat`** una sola vez: crea un acceso directo
  en el inicio de Windows. Cada vez que enciendas o reinicies la PC, el servidor
  ya estará esperándote (queda minimizado).
- Si el servidor llegara a cerrarse, `iniciar.bat` lo reinicia automáticamente cada 3 s.

## 7. Seguridad

- La **contraseña** es obligatoria y se guarda en `servidor\config.json`.
  Puedes cambiarla editando ese archivo y reiniciando `iniciar.bat`.
- **Doble clic en `login.bat`** para ver la contraseña actual en pantalla;
  si abajo respondes **Y** a *"Quiere obtener una nueva contraseña? Y/N"* se
  renueva al instante y se cortan todas las sesiones (los teléfonos vuelven
  a pedir la clave con la nueva).
- Cada **90 días** cambia sola (te aparece una ventana en la PC con la nueva).
- Cada sesión dura 90 días; después pide la clave de nuevo.
- Limite antifuerza bruta: 8 intentos fallidos por minuto.

## 8. Términos de la APK nativa

Opcional. Tienes dos maneras de compilarla (ver `apk-flutter\README-APK.md`):

- **GitHub Actions**: subes el proyecto a GitHub y ahí se compila gratis (recomendado).
- **Flutter local**: instalas Flutter + Android SDK (varios GB) y compilas.

La APK nativa guarda la IP/contraseña en el teléfono y arranca directo, sin navegador.

## 9. Problemas frecuentes

| Problema | Solución |
|---|---|
| El teléfono no encuentra la app | Verifica que PC y teléfono estén en la **misma** red Wi-Fi (o hotspot de la PC) y mira la IP en la consola del servidor. |
| "No se pudo contactar al servidor" | El firewall de Windows bloqueó el puerto: en la ventana de permiso de Windows acepta "Redes privadas y públicas", o abre el puerto 8566 en el firewall. |
| Película/imagen congelada | La calidad "máxima" requiere mucho: baja la calidad en ⚙️ Ajustes, o revisa la potencia Wi-Fi. |
| No aparece la opción "Instalar aplicación" en Chrome | Solo está disponible con HTTPS. Aun así puedes **Añadir a pantalla de inicio** (funciona igual, no es "app instalada"), o usa la APK nativa. |
| No quiero que la PC se controle | Borra `servidor\autoinicio.bat` atajo del inicio y no ejecutes `iniciar.bat`. |
| ¿La PC queda lenta? | La captura usa pocos recursos; si quieres cierras `python.exe` cuando no lo uses (o no lo pongas en autoinicio). |
