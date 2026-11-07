# Cómo compilar la APK "Control PC"

Tienes **dos maneras**. La primera no necesita instalar nada en tu PC.

## Opción A — GitHub Actions (recomendada, gratis)

1. Sube la carpeta `ControlPC` a un repositorio de GitHub.
2. Entra a tu repo → pestaña **Actions** → workflow **"APK"** → botón **Run workflow**.
   Si marcas la casilla *"Publicar en Releases"*, la APK queda también en la
   pestaña **Releases** para descarga pública de cualquier persona.
   Al terminar, descarga el artefacto **controlpc-apk** (es `app-release.apk`).
4. Cópiala a tu teléfono, ábrela y permite "instalar apps de fuentes desconocidas".

> La APK nativa guarda la conexión (IP/puerto/token) y no necesita reabrir el navegador.

## Opción B — Compilar en tu propia PC

1. Instala Flutter: https://docs.flutter.dev/get-started/install/windows
   (incluye JDK y Android SDK en su instalador)
2. Abre una consola en `ControlPC/apk-flutter` y ejecuta:
   ```bat
   flutter create . --org com.controlpc.app --project-name controlpc --platforms=android
   flutter pub get
   flutter build apk --release
   ```
3. La APK queda en: `build\app\outputs\flutter-apk\app-release.apk`

## Modificar la app

El código está en `apk-flutter/lib/main.dart`. Lo básico ya funciona:

- **Pantalla**: video en vivo, toque = clic, arrastre = mover ratón (pulsa al arrastrar), pulsación larga = clic derecho, InteractiveViewer = zoom.
- **Estado**: CPU, RAM, batería, discos, red, procesos, tiempo encendido.
- **Teclado**: campo de texto (soporta ñ/á/é vía portapapeles) y chips de atajos (Alt+Tab, Win+D, Ctrl+Alt+Supr…).

Si cambias el puerto o agregas funciones al servidor, revisa los eventos en
`servidor/servidor.py` (función `manejar_entrada`): el cliente y servidor hablan JSON.
