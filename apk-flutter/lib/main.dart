// Control PC — APK nativa (Flutter) V 1.2
// Pantalla en vivo con gestos, estado con avisos ✅/🚫, volumen + sonido en
// vivo de la PC, teclado/atajos y aviso de nueva versión con descarga.
// Genera la estructura de Android con "flutter create ." (ver README-APK.md).

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "dart:typed_data";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_pcm_sound/flutter_pcm_sound.dart";
import "package:http/http.dart" as http;
import "package:open_filex/open_filex.dart";
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";
import "package:web_socket_channel/web_socket_channel.dart";

const String VERSION_APP = "1.5";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const ControlPCApp());
}

// ------------------------------------------------------------------ base ---

class Conexion {
  final String host;
  final int puerto;
  final String token;

  Conexion({required this.host, required this.puerto, required this.token});

  String get base => "http://$host:$puerto";
  Uri get urlWsVideo => Uri.parse("ws://$host:$puerto/ws?sesion=$token");
  Uri get urlWsAudio => Uri.parse("ws://$host:$puerto/ws-audio?sesion=$token");

  static const clavePrefs = "conexion_guardada";
}

Future<Map<String, dynamic>?> apiGet(Conexion c, String ruta) async {
  try {
    final r = await http.get(
      Uri.parse("${c.base}$ruta"),
      headers: {"Cookie": "sesion=${c.token}"},
    ).timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    return jsonDecode(r.body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> apiPost(Conexion c, String ruta, Map<String, dynamic> cuerpo) async {
  try {
    final r = await http.post(
      Uri.parse("${c.base}$ruta"),
      headers: {"Cookie": "sesion=${c.token}", "Content-Type": "application/json"},
      body: jsonEncode(cuerpo),
    ).timeout(const Duration(seconds: 8));
    if (r.statusCode >= 400) return null;
    return jsonDecode(r.body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

// ------------------------------------------------------------------- app ---

class ControlPCApp extends StatefulWidget {
  const ControlPCApp({super.key});
  @override
  State<ControlPCApp> createState() => _ControlPCAppState();
}

class _ControlPCAppState extends State<ControlPCApp> {
  Conexion? con;
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardada = prefs.getString(Conexion.clavePrefs);
    if (guardada != null && mounted) {
      final partes = guardada.split("|");
      if (partes.length == 3) {
        setState(() {
          con = Conexion(host: partes[0], puerto: int.parse(partes[1]), token: partes[2]);
          cargando = false;
        });
        return;
      }
    }
    if (mounted) setState(() => cargando = false);
  }

  /// Devuelve null si entró bien; si falló, el mensaje del error.
  Future<String?> _entrar(String host, int puerto, String clave) async {
    try {
      final r = await http
          .post(
            Uri.parse("http://$host:$puerto/api/acceso"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"contrasena": clave}),
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 401) {
        return "Contraseña incorrecta — usa el ojo 👁 para verificarla";
      }
      if (r.statusCode != 200) {
        return "El servidor respondió ${r.statusCode} — revisa IP y puerto";
      }
      final token = jsonDecode(r.body)["token"] as String;
      final c = Conexion(host: host, puerto: puerto, token: token);
      setState(() => con = c);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(Conexion.clavePrefs, "${c.host}|${c.puerto}|${c.token}");
      return null;
    } catch (_) {
      return "No se pudo conectar: revisa IP, que el servidor esté abierto y que el Firewall de la PC tenga la regla \"Control PC\" (el .bat iniciar_admin.bat la agrega)";
    }
  }

  Future<void> _salir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Conexion.clavePrefs);
    setState(() => con = null);
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final c = con;
    return MaterialApp(
      title: "Control PC",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF05070C),
        colorScheme: ThemeData.dark(useMaterial3: true)
            .colorScheme
            .copyWith(primary: const Color(0xFF4F83FF)),
      ),
      home: c == null
          ? PantallaAcceso(alEntrar: _entrar)
          : PantallaHome(conexion: c, alSalir: _salir),
    );
  }
}

// ------------------------------------------------------------------ acceso ---

class PantallaAcceso extends StatefulWidget {
  final Future<String?> Function(String, int, String) alEntrar;
  const PantallaAcceso({super.key, required this.alEntrar});
  @override
  State<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends State<PantallaAcceso> {
  final _host = TextEditingController();
  final _puerto = TextEditingController(text: "8566");
  final _clave = TextEditingController();
  String? error;
  bool ocupado = false;
  bool verClave = false;
  bool errorClave = false;

  @override
  void dispose() {
    _host.dispose();
    _puerto.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    setState(() { ocupado = true; error = null; errorClave = false; });

    // Limpieza de lo escrito en el campo IP: si el usuario pega el enlace
    // completo (http://192.168.100.27:8566/app/ o incluso con :puerto),
    // se extrae la IP y el Puerto automaticamente.
    var limpio = _host.text.trim();
    limpio = limpio.replaceFirst(RegExp(r"^https?://", caseSensitive: false), "");
    final corte = limpio.indexOf("/");
    if (corte > 0) limpio = limpio.substring(0, corte);
    int? puertoPegado;
    final dp = limpio.lastIndexOf(":");
    if (dp >= 1) {
      final posible = int.tryParse(limpio.substring(dp + 1));
      if (posible != null && posible > 0 && posible < 65536) {
        puertoPegado = posible;
        limpio = limpio.substring(0, dp);
      }
    }
    final hostLimpio = limpio.trim();
    final puertoFinal = puertoPegado ?? (int.tryParse(_puerto.text.trim()) ?? 8566);
    if (_puerto.text.trim().isEmpty && puertoPegado != null) {
      _puerto.text = "$puertoPegado";
    }

    final mensaje = await widget.alEntrar(
      hostLimpio,
      puertoFinal,
      _clave.text.trim(),
    );
    if (!mounted) return;
    if (mensaje != null) {
      setState(() {
        ocupado = false;
        error = mensaje;
        errorClave = mensaje.startsWith("Contraseña");
      });
    } else {
      setState(() => ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.computer, size: 64, color: Color(0xFF4F83FF)),
              const SizedBox(height: 8),
              const Text("Control PC", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  "La IP y la contraseña aparecen en la ventana\n\"Control PC\" de tu computadora.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _host,
                decoration: const InputDecoration(
                  labelText: "Dirección IP",
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _puerto,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Puerto",
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clave,
                obscureText: !verClave,
                decoration: InputDecoration(
                  labelText: "Contraseña",
                  border: OutlineInputBorder(),
                  filled: true,
                  errorText: errorClave ? (error ?? "Contraseña incorrecta") : null,
                  helperText: "Toca el ojo 👁 para ver lo que escribiste",
                  suffixIcon: IconButton(
                    icon: Icon(verClave ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => verClave = !verClave),
                  ),
                ),
              ),
              if (error != null && !errorClave) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 13)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: ocupado ? null : _entrar,
                child: ocupado
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Conectar", style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ home ---

class PantallaHome extends StatefulWidget {
  final Conexion conexion;
  final VoidCallback alSalir;
  const PantallaHome({super.key, required this.conexion, required this.alSalir});
  @override
  State<PantallaHome> createState() => _PantallaHomeState();
}

class _PantallaHomeState extends State<PantallaHome> {
  Map<String, dynamic>? datos;
  Timer? reloj;
  int ultimoAvisoId = 0;

  @override
  void initState() {
    super.initState();
    _consultar();
    reloj = Timer.periodic(const Duration(seconds: 3), (_) => _consultar());
  }

  @override
  void dispose() {
    reloj?.cancel();
    super.dispose();
  }

  Future<void> _consultar() async {
    final d = await apiGet(widget.conexion, "/api/estado");
    if (d == null || !mounted) return;
    setState(() => datos = d);
    _revisarAvisos(d);
  }

  Future<void> _revisarAvisos(Map<String, dynamic> d) async {
    final lista = (d["avisos"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    if (lista.isEmpty) return;
    final maxId = lista.map((a) => (a["id"] as num?)?.toInt() ?? 0).reduce(math.max);
    if (maxId <= ultimoAvisoId) return;
    for (final a in lista) {
      final id = (a["id"] as num?)?.toInt() ?? 0;
      if (id <= ultimoAvisoId) continue;
      final texto = a["texto"] as String? ?? "";
      final nivel = a["nivel"] as String? ?? "info";
      final esSeguridad = a["seguridad"] as bool? ?? false;
      if (!mounted) continue;
      if (esSeguridad) {
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: const Color(0xFF3B1218),
            content: SizedBox(
              width: double.infinity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(texto, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  "elige una acción:",
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => _accionSeguridad("permitir"),
                child: const Text("✅ Permitir"),
              ),
              TextButton(
                onPressed: () => _accionSeguridad("rechazar"),
                child: const Text("🚫 Rechazar"),
              ),
              TextButton(
                onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text("✕"),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: nivel == "advertencia" ? const Color(0xFF4B3A05) : const Color(0xFF12233B),
          duration: const Duration(seconds: 4),
          content: Text(texto, style: const TextStyle(fontSize: 13.5)),
          action: SnackBarAction(label: "OK", onPressed: () {}),
        ));
      }
      HapticFeedback.lightImpact();
    }
    ultimoAvisoId = maxId;
  }

  Future<void> _accionSeguridad(String accion) async {
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    final r = await apiPost(widget.conexion, "/api/seguridad-accion", {"accion": accion});
    if (!mounted) return;
    String msg;
    if (r == null) {
      msg = "No se pudo aplicar";
    } else if (r["ok"] == true && accion == "rechazar") {
      msg = "🚫 Ventana rechazada desde el teléfono";
    } else if (r["ok"] == true) {
      msg = "✅ " + ((r["mensaje"] as String?) ?? "Modo silencioso aplicado");
    } else if (r["error"] == "requiere-admin") {
      msg = "⚠️ Corre el servidor con iniciar_admin.bat para poder rechazar";
    } else if (r["pendiente"] == true) {
      msg = "📝 Autoriza la ventana de Windows en la PC para aplicar";
    } else {
      msg = "⚠️ " + ((r["error"] as String?) ?? "error desconocido");
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text(msg, style: const TextStyle(fontSize: 13.5)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Control PC · ${widget.conexion.host}"),
          actions: [
            if ((datos?["privilegio"] ?? "") == "administrador")
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.verified_user, color: Color(0xFF2DD4A7), size: 20),
              ),
            IconButton(icon: const Icon(Icons.logout), onPressed: widget.alSalir),
          ],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.monitor), text: "Pantalla"),
            Tab(icon: Icon(Icons.query_stats), text: "Estado"),
            Tab(icon: Icon(Icons.surround_sound), text: "Audio"),
            Tab(icon: Icon(Icons.keyboard_alt_outlined), text: "Teclado"),
          ]),
        ),
        body: TabBarView(children: [
          PantallaVideo(conexion: widget.conexion),
          PantallaEstado(conexion: widget.conexion, datos: datos, uacBoton: _cambiaUac, prueba: _pruebaAviso),
          PantallaAudio(conexion: widget.conexion, datos: datos),
          PantallaTeclado(conexion: widget.conexion),
        ]),
      ),
    );
  }

  Future<void> _cambiaUac(String modo) async {
    if (modo == "silencioso") {
      final seguir = await _confirmar(
        "Windows dejará de preguntar los permisos de administración en la PC (menos seguro). ¿Seguro?");
      if (seguir != true || !mounted) return;
    }
    final r = await apiPost(widget.conexion, "/api/uac", {"modo": modo});
    if (!mounted) return;
    if (r != null && r["pendiente"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Windows abrirá una ventana EN TU PC: autorizala para aplicar.",
            style: TextStyle(fontSize: 13.5)),
      ));
    }
    _consultar();
  }

  Future<bool?> _confirmar(String texto) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Confirmar", style: TextStyle(fontSize: 18)),
        content: Text(texto, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("Seguir")),
        ],
      ),
    );
  }

  Future<void> _pruebaAviso() async {
    await apiPost(widget.conexion, "/api/aviso", {"texto": "🔔 ¡Aviso de prueba!"});
    _consultar();
  }
}

// ------------------------------------------------------------------ video ---

class PantallaVideo extends StatefulWidget {
  final Conexion conexion;
  const PantallaVideo({super.key, required this.conexion});
  @override
  State<PantallaVideo> createState() => _PantallaVideoState();
}

class _PantallaVideoState extends State<PantallaVideo> {
  static const ANCHO_CALIDAD = {0: 960, 1: 1280, 2: 1600, 3: 1920};
  static const Q_CALIDAD = {0: 45, 1: 55, 2: 68, 3: 78};

  WebSocketChannel? canal;
  Uint8List? fotograma;
  int anchoImg = 1280, altoImg = 720;
  String estado = "Conectando…";
  Timer? reintento;
  double zoom = 1.0;
  Offset desplaza = Offset.zero;
  int nivelCalidad = 0;
  int fps = 24;
  int pantalla = 1;
  bool completo = false;

  // estado de gestos
  final Map<int, Offset> puntas = {};
  int? primario;
  double acumulado = 0;
  bool pulsado = false;
  bool largo = false;
  Timer? temporizadorLargo;
  bool arrastreLibre = false;
  ({double x, double y})? posTocar;
  // gesto 2 dedos
  double? gD0;
  double? gZ0;
  Offset? gCentro;
  String? gModo;

  @override
  void initState() {
    super.initState();
    _conectar();
  }

  @override
  void dispose() {
    reintento?.cancel();
    temporizadorLargo?.cancel();
    try {
      canal?.sink.close();
    } catch (_) {}
    super.dispose();
  }

  void _conectar() {
    try {
      final c = WebSocketChannel.connect(widget.conexion.urlWsVideo);
      canal = c;
      c.stream.listen(
        (mensaje) {
          if (mensaje is List<int>) {
            if (mounted) setState(() => fotograma = Uint8List.fromList(mensaje));
          } else if (mensaje is String) {
            try {
              final m = jsonDecode(mensaje) as Map<String, dynamic>;
              if (m["t"] == "dim") {
                if (mounted) {
                  setState(() {
                    anchoImg = (m["w"] as num?)?.toInt() ?? 1280;
                    altoImg = (m["h"] as num?)?.toInt() ?? 720;
                    zoom = 1;
                    desplaza = Offset.zero;
                  });
                }
              } else if (m["t"] == "error") {
                if (mounted) setState(() => estado = "Sesión caducada: reinicia la app");
              }
            } catch (_) {}
          }
        },
        onError: (_) => _reintentar(),
        onDone: () => _reintentar(),
      );
      _envia({"t": "cfg", "ancho_maximo": ANCHO_CALIDAD[nivelCalidad],
        "calidad_jpeg": Q_CALIDAD[nivelCalidad], "fps": fps, "pantalla": pantalla});
    } catch (_) {
      _reintentar();
    }
  }

  void _reintentar() {
    if (!mounted) return;
    setState(() => estado = "PC sin conexión. Reintentando…");
    reintento?.cancel();
    try {
      canal?.sink.close();
    } catch (_) {}
    canal = null;
    reintento = Timer(const Duration(seconds: 3), () {
      if (mounted) _conectar();
    });
  }

  void _envia(Map<String, Object?> evento) {
    try {
      canal?.sink.add(jsonEncode(evento));
    } catch (_) {}
  }

  void _cambiaCfg() {
    _envia({
      "t": "cfg",
      "ancho_maximo": ANCHO_CALIDAD[nivelCalidad],
      "calidad_jpeg": Q_CALIDAD[nivelCalidad],
      "fps": fps,
      "pantalla": pantalla,
    });
  }

  // ---------- mapeo a coordenada de imagen ----------
  ({double x, double y}) _aImagen(Offset local, Size tamano) {
    final ar = anchoImg / math.max(1, altoImg);
    double dibW = tamano.width, dibH = tamano.width / ar;
    if (dibH > tamano.height) {
      dibH = tamano.height;
      dibW = dibH * ar;
    }
    final oy = (tamano.height - dibH) / 2;
    final ox = (tamano.width - dibW) / 2;
    final x = ((local.dx - ox) / dibW).clamp(0.0, 1.0);
    final y = ((local.dy - oy) / dibH).clamp(0.0, 1.0);
    return (x: x, y: y);
  }

  void _abajo(PointerDownEvent ev, Size tamano) {
    puntas[ev.pointer] = ev.localPosition;
    if (puntas.length == 1) {
      primario = ev.pointer;
      acumulado = 0;
      pulsado = false;
      largo = false;
      arrastreLibre = false;
      posTocar = _aImagen(ev.localPosition, tamano);
      final p = _aImagen(ev.localPosition, tamano);
      _envia({"t": "mover", "x": p.x, "y": p.y});
      temporizadorLargo?.cancel();
      temporizadorLargo = Timer(const Duration(milliseconds: 600), () {
        if (puntas.length != 1) return;
        largo = true;
        pulsado = true;
        HapticFeedback.mediumImpact();
        final p2 = _aImagen(puntas[primario] ?? ev.localPosition, tamano);
        _envia({"t": "pulsar", "x": p2.x, "y": p2.y, "b": "der"});
      });
    } else if (puntas.length == 2) {
      temporizadorLargo?.cancel();
      if (pulsado) {
        _envia({"t": "soltar", "b": largo ? "der" : "izq"});
        pulsado = false;
      }
      final valores = puntas.values.toList();
      gD0 = (valores[0] - valores[1]).distance.abs().toDouble() + 1;
      gZ0 = zoom;
      gCentro = (valores[0] + valores[1]) / 2;
      gModo = null;
    } else {
      temporizadorLargo?.cancel();
      gModo = null;
    }
  }

  void _sobreMover(PointerMoveEvent ev, Size tamano) {
    if (!puntas.containsKey(ev.pointer)) return;
    final dx = ev.localPosition.dx - puntas[ev.pointer]!.dx;
    final dy = ev.localPosition.dy - puntas[ev.pointer]!.dy;
    puntas[ev.pointer] = ev.localPosition;

    if (puntas.length == 1 && ev.pointer == primario) {
      acumulado += (dx.abs() + dy.abs());
      if (acumulado > 18 && !pulsado && !largo) {
        temporizadorLargo?.cancel();
        if (zoom > 1) {
          // con la vista con zoom: arrastrar desplaza la imagen
          setState(() => desplaza = Offset(
            desplaza.dx - dx / (zoom * 2),
            desplaza.dy - dy / (zoom * 2),
          ));
          return;
        }
        if (arrastreLibre) {
          // modo puntero libre
        } else {
          final p = posTocar ?? _aImagen(ev.localPosition, tamano);
          _envia({"t": "pulsar", "x": p.x, "y": p.y, "b": "izq"});
          pulsado = true;
        }
      }
      final p = _aImagen(ev.localPosition, tamano);
      _envia({"t": "mover", "x": p.x, "y": p.y});
    } else if (puntas.length == 2 && gD0 != null) {
      final valores = puntas.values.toList();
      final d = (valores[0] - valores[1]).distance.abs().toDouble() + 1;
      final centro = (valores[0] + valores[1]) / 2;
      final pinch = (d - gD0!) / 2;
      final dax = centro.dx - gCentro!.dx;
      final day = centro.dy - gCentro!.dy;

      gModo ??= () {
        if (pinch.abs() > 14) return "pinz";
        if (day.abs() > 12 && zoom <= 1.02) return "desliza";
        if (dax.abs() > 12 && zoom > 1.02) return "pan";
        return null;
      }();

      if (gModo == "pinz") {
        setState(() => zoom = (gZ0! * (d / gD0!)).clamp(1.0, 8.0));
      } else if (gModo == "pan") {
        setState(() => desplaza = Offset(
          desplaza.dx - dax / (zoom * 2),
          desplaza.dy - day / (zoom * 2),
        ));
      } else if (gModo == "desliza") {
        final paso = (day / 40).truncateToDouble();
        if (paso.abs() >= 1) _envia({"t": "deslizar", "dy": paso * 40});
      }
      gD0 = d;
      gZ0 = zoom;
      gCentro = centro;
    }
  }

  void _arriba(PointerUpEvent ev, Size tamano) {
    if (!puntas.containsKey(ev.pointer)) return;
    puntas.remove(ev.pointer);
    if (puntas.length == 1) {
      gModo = null;
      acumulado = 0;
      posTocar = null;
      return;
    }
    if (puntas.isNotEmpty) return; // quedan 2
    temporizadorLargo?.cancel();
    if (gModo != null) {
      gModo = null;
      return;
    }
    if (pulsado) {
      _envia({"t": "soltar", "b": largo ? "der" : "izq"});
      pulsado = false;
      largo = false;
    } else if (posTocar != null && !arrastreLibre) {
      _envia({"t": "clic", "x": posTocar!.x, "y": posTocar!.y, "b": "izq"});
    }
    posTocar = null;
    arrastreLibre = false;
  }

  void _cancela(PointerCancelEvent ev, Size tamano) {
    _arriba(PointerUpEvent(pointer: ev.pointer, position: ev.localPosition), tamano);
  }

  @override
  Widget build(BuildContext context) {
    final botones = Row(children: [
      _selector<int>(
        valor: nivelCalidad,
        opciones: {0: "Rápida", 1: "Media", 2: "Alta", 3: "Máxima"},
        alElegir: (v) => setState(() { nivelCalidad = v; _cambiaCfg(); }),
      ),
      const SizedBox(width: 6),
      _selector<int>(
        valor: fps,
        opciones: {8: "8 fps", 15: "15 fps", 24: "24 fps", 30: "30 fps"},
        alElegir: (v) => setState(() { fps = v; _cambiaCfg(); }),
      ),
      const SizedBox(width: 6),
      _selector<int>(
        valor: pantalla,
        opciones: {1: "Monitor 1", 2: "Monitor 2", 0: "Todas"},
        alElegir: (v) => setState(() { pantalla = v; _cambiaCfg(); }),
      ),
      const SizedBox(width: 6),
      IconButton(
        icon: Icon(completo ? Icons.fullscreen_exit : Icons.fullscreen),
        onPressed: () {
          completo = !completo;
          SystemChrome.setEnabledSystemUIMode(
            completo ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
          );
          setState(() {});
        },
      ),
    ]);
    return Column(
      children: [
        if (!completo) behavedControls(botones),
        Expanded(
          child: fotograma == null
              ? Center(child: Text(estado, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)))
              : LayoutBuilder(builder: (context, cajas) {
                  final tamano = Size(cajas.maxWidth, cajas.maxHeight);
                  final dibujar = Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _abajo(e, tamano),
                    onPointerMove: (e) => _sobreMover(e, tamano),
                    onPointerUp: (e) => _arriba(e, tamano),
                    onPointerCancel: (e) => _cancela(e, tamano),
                    child: SizedBox.expand(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..translate(desplaza.dx, desplaza.dy)
                          ..scale(zoom),
                        child: Image.memory(fotograma!, fit: BoxFit.contain,
                          gaplessPlayback: true),
                      ),
                    ),
                  );
                  return dibujar;
                }),
        ),
        if (!completo)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(estado, style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ),
      ],
    );
  }

  Widget behavedControls(Widget hijo) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: hijo,
    );
  }

  Widget _selector<T>({required T valor, required Map<T, String> opciones, required ValueChanged<T> alElegir}) {
    final actual = opciones[valor] ?? "?";
    return PopupMenuButton<T>(
      onSelected: alElegir,
      initialValue: valor,
      itemBuilder: (c) => opciones.entries
          .map((e) => PopupMenuItem<T>(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF131A2B),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF232C42)),
        ),
        child: Text(actual, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }
}

// ------------------------------------------------------------------ estado ---

class PantallaEstado extends StatefulWidget {
  final Conexion conexion;
  final Map<String, dynamic>? datos;
  final ValueChanged<String> uacBoton;
  final VoidCallback prueba;
  const PantallaEstado({super.key, required this.conexion, required this.datos,
    required this.uacBoton, required this.prueba});
  @override
  State<PantallaEstado> createState() => _PantallaEstadoState();
}

class _PantallaEstadoState extends State<PantallaEstado> {
  bool descargando = false;
  int progreso = 0;

  Future<void> _descargarEInstalar(Map<String, dynamic> act) async {
    final urlApk = (act["apk"] as String? ?? "").trim();
    if (urlApk.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Esta actualización no trae APK: abre la página en el navegador.",
            style: TextStyle(fontSize: 13))));
      final u = act["url"] as String? ?? "";
      try {
        await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
      } catch (_) {}
      return;
    }
    setState(() { descargando = true; progreso = 0; });
    try {
      final dir = await getTemporaryDirectory();
      final ruta = "${dir.path}${Platform.pathSeparator}controlpc.apk";
      final cliente = http.Client();
      final solicitud = http.Request("GET", Uri.parse(urlApk));
      final respuesta = await cliente.send(solicitud).timeout(const Duration(minutes: 10));
      if (respuesta.statusCode != 200) throw "HTTP ${respuesta.statusCode}";
      final total = respuesta.contentLength ?? 0;
      int recibido = 0;
      final bloque = <int>[];
      final archivo = File(ruta);
      final f = archivo.openSync(mode: FileMode.write);
      await for (final trozo in respuesta.stream) {
        recibido += trozo.length;
        f.writeFromSync(trozo);
        if (total > 0 && mounted) {
          setState(() => progreso = ((recibido / total) * 100).clamp(0, 100).round());
        }
      }
      f.closeSync();
      cliente.close();
      if (!mounted) return;
      setState(() { descargando = false; progreso = 100; });
      final abierta = await OpenFilex.open(ruta);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          abierta.type != ResultType.done
              ? "Instalador abierto: acepta 'Instalar' y si pide, marca 'Permitir de esta fuente'."
              : "Descargada en $ruta",
          style: const TextStyle(fontSize: 13))));
    } catch (e) {
      setState(() => descargando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("No se pudo actualizar: $e", style: const TextStyle(fontSize: 13))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    if (d == null) {
      return const Center(child: Text("Consultando…", style: TextStyle(color: Colors.white38)));
    }
    final discos = (d["discos"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final procesos = (d["procesos"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final avisos = (d["avisos"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final bateria = d["bateria"] as Map<String, dynamic>?;
    final uac = d["uac"] as Map<String, dynamic>? ?? {};
    final encendidoS = (d["encendido_s"] as num?)?.toInt() ?? 0;
    final admin = d["privilegio"] == "administrador";

    double pct(Object? v) => ((v as num?) ?? 0).toDouble();

    String hace(int s) =>
        s < 60 ? "$s s" : s < 3600 ? "${s ~/ 60} min" : "${s ~/ 3600} h";

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _barra("CPU", pct(d["cpu"])),
        _barra("RAM", pct(d["ram_pct"])),
        const SizedBox(height: 10),
        _tarjeta("Detalles", [
          "RAM ${d["ram_usada_gb"]} GB de ${d["ram_total_gb"]} GB",
          if (bateria != null)
            "Batería ${bateria["pct"]}% ${bateria["enchufado"] == true ? "(cargando ⚡)" : ""}",
          ...discos.map((x) => "Disco ${x["montaje"]}: ${x["pct"]}% usado, ${x["libre_gb"]} GB libres"),
          "Red ↓${d["red_baja_kbps"]} kB/s · ↑${d["red_sube_kbps"]} kB/s",
          "Encendido: ${encendidoS ~/ 3600} h ${(encendidoS % 3600) ~/ 60} min",
          "Equipo: ${d["host"] ?? "-"}",
          "Servidor: ${admin ? "administrador ✓ (puede rechazar UAC)" : "usuario normal"}",
        ]),
        const SizedBox(height: 12),
        _tarjeta("Procesos más pesados",
            procesos.isEmpty ? ["—"] : procesos.map((p) {
              final cpu = ((p["cpu"] as num?) ?? 0).toDouble();
              return "${p["nombre"]}  ${cpu.toStringAsFixed(1)}%";
            }).toList()),
        const SizedBox(height: 12),
        _tarjeta("Últimos avisos",
            avisos.isEmpty ? ["—"] : avisos.take(10).map((a) {
              final ico = a["nivel"] == "peligro" ? "🔴" : a["nivel"] == "advertencia" ? "🟡" : "🔵";
              return "$ico ${a["texto"]}  (hace ${hace((a["hace"] as num?)?.toInt() ?? 0)})";
            }).toList()),
        const SizedBox(height: 12),
        Builder(builder: (c) {
          final act = d["actualizacion"] as Map<String, dynamic>?;
          final lineas = <String>["Versión instalada: V $VERSION_APP"];
          if (act != null && act["nueva"] != null) {
            lineas.add("🏁 Hay actualización: V ${act["nueva"]}");
          }
          return Column(children: [
            _tarjeta("Aplicación", lineas),
            if (act != null && act["nueva"] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(children: [
                  FilledButton.icon(
                    icon: descargando
                        ? const SizedBox(height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download),
                    label: Text(descargando
                        ? "Descargando… $progreso%"
                        : "⬇ Instalar la versión V ${act["nueva"]} ahora"),
                    onPressed: () => _descargarEInstalar(act),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Se descarga e instala automáticamente (Android pedirá confirmar).",
                    style: const TextStyle(fontSize: 11.5, color: Colors.white38),
                  ),
                ]),
              ),
          ]);
        }),
        const SizedBox(height: 14),
        const Text("AVISOS DE SEGURIDAD (UAC)",
            style: TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(
          uac["modo"] == "silencioso" ? "Modo silencioso ✓ (Windows no pregunta)" : "Preguntando (UAC activo)",
          style: const TextStyle(fontSize: 13.5),
        ),
        FilledButton.tonal(
          onPressed: () => widget.uacBoton(uac["modo"] == "silencioso" ? "aviso" : "silencioso"),
          child: Text(uac["modo"] == "silencioso" ? "Volver a pedir permisos" : "Dejar de preguntar"),
        ),
        FilledButton.tonal(
          onPressed: widget.prueba,
          child: const Text("🔔 Probar aviso"),
        ),
      ],
    );
  }

  Widget _barra(String titulo, double v) {
    final c = v > 88 ? const Color(0xFFF87171) : v > 70 ? const Color(0xFFFBBF24) : const Color(0xFF4F83FF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("$titulo  ${v.toStringAsFixed(0)}%", style: const TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: v / 100, color: c, backgroundColor: const Color(0xFF1B2233),
          minHeight: 9, borderRadius: BorderRadius.circular(6)),
      ]),
    );
  }

  Widget _tarjeta(String titulo, List<String> lineas) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF232C42)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo.toUpperCase(),
            style: const TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 6),
        ...lineas.map((l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(l, style: const TextStyle(fontSize: 13.5)),
            )),
      ]),
    );
  }
}

// ------------------------------------------------------------------ audio ---

class PantallaAudio extends StatefulWidget {
  final Conexion conexion;
  final Map<String, dynamic>? datos;
  const PantallaAudio({super.key, required this.conexion, required this.datos});
  @override
  State<PantallaAudio> createState() => _PantallaAudioState();
}

class _PantallaAudioState extends State<PantallaAudio> {
  WebSocketChannel? canalAudio;
  bool escuchando = false;
  String estadoAudio = "apagado";
  String nota = "";
  bool mudo = false;
  double nivel = 50;
  bool arrastrando = false;
  List<int> buffer = [];

  Future<void> _aplicarVolumen(double? nuevo, bool? mudoPred) async {
    final cuerpo = <String, dynamic>{};
    if (nuevo != null) cuerpo["nivel"] = nuevo.round();
    if (mudoPred != null) cuerpo["mudo"] = mudoPred;
    final r = await apiPost(widget.conexion, "/api/volumen", cuerpo);
    if (r == null || !mounted) return;
    mudo = (r["mudo"] ?? false) == true;
    final nv = (r["nivel"] as num?)?.toInt();
    if (nv != null && !arrastrando) setState(() => nivel = nv.toDouble());
  }

  void _drenar() async {
    if (buffer.isEmpty) return;
    final cuantos = math.min(buffer.length, 4800); // ~100 ms a 48 kHz
    final toma = buffer.sublist(0, cuantos);
    buffer.removeRange(0, cuantos);
    await FlutterPcmSound.feed(PcmArrayInt16.fromList(toma));
  }

  Future<void> _escuchar() async {
    if (escuchando) {
      try {
        canalAudio?.sink.close();
      } catch (_) {}
      await _soltarReproduccion();
      setState(() {
        escuchando = false;
        canalAudio = null;
        estadoAudio = "apagado";
        nota = "";
      });
      return;
    }
    try {
      final c = WebSocketChannel.connect(widget.conexion.urlWsAudio);
      canalAudio = c;
      late final StreamSubscription susc;
      susc = c.stream.listen(
        (mensaje) {
          if (mensaje is String) {
            try {
              final meta = jsonDecode(mensaje) as Map<String, dynamic>;
              final error = (meta["error"] ?? "") as String;
              if (error.isNotEmpty) {
                setState(() {
                  nota = "❌ $error";
                  escuchando = false;
                  estadoAudio = "apagado";
                });
                susc.cancel();
                return;
              }
              final srLocal = (meta["sr"] as num?)?.toInt() ?? 48000;
              if (!escuchando) _montarAudio(srLocal);
              if (mounted) {
                setState(() {
                  escuchando = true;
                  estadoAudio = "escuchando · $srLocal Hz";
                  nota = "Sonido de la PC al instante (una fracción de segundo es normal).";
                });
              }
            } catch (_) {}
          } else if (mensaje is List<int> && escuchando) {
            final bytes = Uint8List.fromList(mensaje.cast<int>());
            final i16 = Int16List.view(bytes.buffer);
            buffer.addAll(i16);
            _drenar();
          }
        },
        onError: (_) => _pararAudio(),
        onDone: () => _pararAudio(),
      );
    } catch (e) {
      setState(() => nota = "❌ $e");
    }
  }

  Future<void> _montarAudio(int sampleRate) async {
    try {
      await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
      // colchón de ~100 ms: bajo retardo estable frente al Wi-Fi
      await FlutterPcmSound.setFeedThreshold(sampleRate ~/ 10);
      FlutterPcmSound.setFeedCallback((quedan) => _drenar());
      FlutterPcmSound.start();
    } catch (e) {
      setState(() => nota = "❌ audio: $e");
    }
  }

  Future<void> _soltarReproduccion() async {
    buffer.clear();
    try {
      FlutterPcmSound.setFeedCallback(null);
      await FlutterPcmSound.release();
    } catch (_) {}
  }

  Future<void> _pararAudio() async {
    canalAudio = null;
    await _soltarReproduccion();
    if (mounted) {
      setState(() {
        if (escuchando) estadoAudio = "conexión cerrada";
        escuchando = false;
      });
    }
  }

  @override
  void dispose() {
    try {
      canalAudio?.sink.close();
    } catch (_) {}
    _soltarReproduccion();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = (widget.datos?["volumen"] as Map<String, dynamic>?);
    final soportado = v?["soportado"] == true;
    final nivelReal = (v?["nivel"] as num?)?.toDouble();
    final mudoReal = v?["mudo"] == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: () => _aplicarVolumen(null, !mudoReal),
              icon: Text(mudoReal ? "🔊" : "🔇", style: const TextStyle(fontSize: 20)),
            ),
            Expanded(
              child: Slider(
                value: arrastrando ? nivel : (nivelReal ?? nivel),
                min: 0, max: 100,
                onChanged: soportado
                    ? (nv) { setState(() { nivel = nv; arrastrando = true; }); }
                    : null,
                onChangeEnd: soportado
                    ? (nv) => _aplicarVolumen(nv, null)
                    : null,
              ),
            ),
            Text("${(nivelReal ?? nivel).round()}%",
                style: const TextStyle(fontSize: 13)),
          ],
        ),
        const Text("Controla el volumen maestro de la PC",
            style: TextStyle(fontSize: 11.5, color: Colors.white38)),
        const SizedBox(height: 18),
        const Text("SONIDO EN VIVO",
            style: TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 6),
        FilledButton.icon(
          icon: Icon(escuchando ? Icons.stop : Icons.play_arrow),
          label: Text(escuchando ? "⏸ Detener sonido" : "▶ Escuchar el sonido de la PC"),
          onPressed: _escuchar,
        ),
        const SizedBox(height: 6),
        Text(estadoAudio, style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
        if (nota.isNotEmpty)
          Text(nota, style: const TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(height: 14),
        const Text("Cuando escuches, el audio completo de la PC llega al teléfono en tiempo real.",
            style: TextStyle(fontSize: 11.5, color: Colors.white38)),
      ],
    );
  }
}

// ------------------------------------------------------------------ teclado ---

class PantallaTeclado extends StatefulWidget {
  final Conexion conexion;
  const PantallaTeclado({super.key, required this.conexion});
  @override
  State<PantallaTeclado> createState() => _PantallaTecladoState();
}

class _PantallaTecladoState extends State<PantallaTeclado> {
  final _texto = TextEditingController();
  final Set<String> _mods = {};

  Future<void> _enviaTeclas(String k) async {
    await apiPost(widget.conexion, "/api/entrada", {
      "t": "teclas",
      "mods": _mods.toList(),
      "k": k,
    });
    if (mounted) setState(() => _mods.clear());
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chips = ["ctrl", "alt", "shift", "win"]
        .map((m) => FilterChip(
              label: Text(m.toUpperCase(), style: const TextStyle(fontSize: 12.5)),
              selected: _mods.contains(m),
              onSelected: (v) {
                setState(() {
                  v ? _mods.add(m) : _mods.remove(m);
                });
              },
            ))
        .toList();
    final atajos = <String, Map<String, Object?>>{
      "Escritorio ⊞D": {"t": "teclas", "mods": ["win"], "k": "d"},
      "Explorador ⊞E": {"t": "teclas", "mods": ["win"], "k": "e"},
      "Ejecutar ⊞R": {"t": "teclas", "mods": ["win"], "k": "r"},
      "Alt+Tab": {"t": "teclas", "mods": ["alt"], "k": "tab"},
      "Ctrl+Alt+Supr": {"t": "teclas", "mods": ["ctrl", "alt"], "k": "delete"},
      "Admin. Tareas": {"t": "teclas", "mods": ["ctrl", "shift"], "k": "escape"},
      "Enter": {"t": "teclas", "mods": [], "k": "enter"},
      "Esc": {"t": "teclas", "mods": [], "k": "escape"},
      "Tab": {"t": "teclas", "mods": [], "k": "tab"},
      "Borrar ⌫": {"t": "teclas", "mods": [], "k": "backspace"},
      "Supr": {"t": "teclas", "mods": [], "k": "delete"},
      "F5": {"t": "teclas", "mods": [], "k": "f5"},
      "F11": {"t": "teclas", "mods": [], "k": "f11"},
      "Inicio": {"t": "teclas", "mods": [], "k": "home"},
      "Fin": {"t": "teclas", "mods": [], "k": "end"},
      "Bloquear ⊞L": {"t": "teclas", "mods": ["win"], "k": "l"},
      "Alt+F4": {"t": "teclas", "mods": ["alt"], "k": "f4"},
    };
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Wrap(children: chips),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _texto,
              decoration: const InputDecoration(
                hintText: "Escribe y envía (ñ, acentos…)",
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () async {
              final s = _texto.text;
              if (s.isNotEmpty) {
                await apiPost(widget.conexion, "/api/entrada", {"t": "texto", "s": s});
                _texto.clear();
              }
            },
            icon: const Icon(Icons.send),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: atajos.entries
              .map((e) => ActionChip(
                    label: Text(e.key, style: const TextStyle(fontSize: 12.5)),
                    onPressed: () async {
                      final evento = Map<String, Object?>.from(e.value);
                      final lista = ((evento["mods"] ?? []) as List).cast<Object>();
                      await apiPost(widget.conexion, "/api/entrada", {
                        ...evento,
                        "mods": [..._mods, ...lista],
                      });
                      if (mounted && _mods.isNotEmpty) setState(() => _mods.clear());
                    },
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        const Text(
          "Nota: envía atajos y texto al servidor; las teclas también llegan con la pantalla abierta.",
          style: TextStyle(fontSize: 11.5, color: Colors.white38),
        ),
      ],
    );
  }
}
