// Control PC — APK nativo (Flutter)
// Nos conecta al servidor de la PC: pantalla en vivo, ratón táctil, teclado y estado.
// Requiere ejecutar "flutter create ." en esta carpeta una sola vez (ver README-APK.md).

import "dart:async";
import "dart:convert";
import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";
import "package:web_socket_channel/web_socket_channel.dart";

void main() {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const ControlPCApp());
}

// ------------------------------------------------------------------ base ---

class Conexion {
  String host; // ejemplo: 192.168.1.50 o 100.x.y.z (IP de Tailscale)
  int puerto;
  String token;

  Conexion({required this.host, required this.puerto, required this.token});

  String get base => "http://$host:$puerto";
  String get urlWs => "ws://$host:$puerto/ws?sesion=$token";

  static const clavePrefs = "conexion_guardada";
}

class DatosEstado {
  final double cpu, ram;
  final String host, os;
  final int encendidoS, puerto;
  final List<Map<String, Object?>> procesos;
  final String detalle;

  DatosEstado({
    required this.cpu,
    required this.ram,
    required this.host,
    required this.os,
    required this.encendidoS,
    required this.procesos,
    required this.detalle,
    required this.puerto,
  });

  static DatosEstado desdeJson(Map<String, dynamic> j) {
    final procs = (j["procesos"] as List? ?? [])
        .map<Map<String, Object?>>((p) => {"nombre": p["nombre"], "cpu": p["cpu"]})
        .toList();
    final bat = j["bateria"];
    final discs = (j["discos"] as List? ?? [])
        .map((d) => "Disco ${d["montaje"]}: ${d["pct"]}% usado")
        .join("\n");
    return DatosEstado(
      cpu: (j["cpu"] ?? 0) * 1.0,
      ram: (j["ram_pct"] ?? 0) * 1.0,
      host: j["host"] ?? "-",
      os: j["os"] ?? "-",
      encendidoS: j["encendido_s"] ?? 0,
      procesos: procs,
      puerto: j["puerto"] ?? 8566,
      detalle:
          "RAM ${j["ram_usada_gb"]} GB de ${j["ram_total_gb"]} GB\n${_bateriaLinea(bat)}\n$discs\n"
          "Red ↓${j["red_baja_kbps"]} kB/s ↑${j["red_sube_kbps"]} kB/s\nEncendido: ${(j["encendido_s"] ?? 0) ~/ 3600} h ${((j["encendido_s"] ?? 0) % 3600) ~/ 60} min",
    );
  }
}

String _bateriaLinea(dynamic bat) {
  if (bat == null) return "Batería: no disponible";
  return "Batería: ${bat["pct"]}% ${bat["enchufado"] ? "(cargando ⚡)" : ""}";
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

  Future<void> _guardar(Conexion c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Conexion.clavePrefs, "${c.host}|${c.puerto}|${c.token}");
  }

  Future<bool> _entrar(String host, int puerto, String clave) async {
    try {
      final r = await http
          .post(
            Uri.parse("http://$host:$puerto/api/acceso"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"contrasena": clave}),
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return false;
      final token = jsonDecode(r.body)["token"] as String;
      final c = Conexion(host: host, puerto: puerto, token: token);
      setState(() => con = c);
      await _guardar(c);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    final c = con;
    return MaterialApp(
      title: "Control PC",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF05070C),
        colorScheme: ThemeData.dark(useMaterial3: true).colorScheme.copyWith(primary: const Color(0xFF4F83FF)),
      ),
      home: c == null ? PantallaAcceso(alEntrar: _entrar) : PantallaHome(conexion: c, alSalir: _salir),
    );
  }

  Future<void> _salir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Conexion.clavePrefs);
    setState(() => con = null);
  }
}

// ------------------------------------------------------------------ acceso ---

class PantallaAcceso extends StatefulWidget {
  final Future<bool> Function(String, int, String) alEntrar;
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

  @override
  void dispose() {
    _host.dispose();
    _puerto.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    setState(() { ocupado = true; error = null; });
    final ok = await widget.alEntrar(
      _host.text.trim(),
      int.tryParse(_puerto.text.trim()) ?? 8566,
      _clave.text.trim(),
    );
    if (!mounted) return;
    if (!ok) setState(() { ocupado = false; error = "No se pudo conectar: revisa host, puerto y contraseña."; });
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
              const Text("La IP y la contraseña aparecen en la ventana\n\"Control PC\" de tu computadora.",
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12.5)),
              const SizedBox(height: 24),
              TextField(controller: _host, decoration: const InputDecoration(labelText: "Dirección IP", border: OutlineInputBorder(), filled: true)),
              const SizedBox(height: 12),
              TextField(controller: _puerto, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Puerto", border: OutlineInputBorder(), filled: true)),
              const SizedBox(height: 12),
              TextField(controller: _clave, obscureText: true, decoration: const InputDecoration(labelText: "Contraseña", border: OutlineInputBorder(), filled: true)),
              if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 13))],
              const SizedBox(height: 20),
              FilledButton(onPressed: ocupado ? null : _entrar, child: ocupado ? const CircularProgressIndicator() : const Text("Conectar", style: TextStyle(fontSize: 16))),
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
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Control PC · ${widget.conexion.host}"),
          actions: [
            IconButton(icon: const Icon(Icons.logout), onPressed: widget.alSalir),
          ],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.monitor), text: "Pantalla"),
            Tab(icon: Icon(Icons.query_stats), text: "Estado"),
            Tab(icon: Icon(Icons.keyboard_alt_outlined), text: "Teclado"),
          ]),
        ),
        body: TabBarView(
          children: [
            PantallaVideo(conexion: widget.conexion),
            PantallaEstado(conexion: widget.conexion),
            PantallaTeclado(conexion: widget.conexion),
          ],
        ),
      ),
    );
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
  WebSocketChannel? canal;
  Uint8List? ultimoFotograma;
  String estado = "Conectando…";
  Timer? reintento;
  double zoom = 1.0;

  @override
  void initState() {
    super.initState();
    _conectar();
  }

  void _conectar() {
    try {
      final c = WebSocketChannel.connect(Uri.parse(widget.conexion.urlWs));
      canal = c;
      c.stream.listen(
        (mensaje) {
          if (mensaje is List<int>) {
            if (mounted) setState(() => ultimoFotograma = Uint8List.fromList(mensaje));
          } else if (mensaje is String) {
            if (mensaje.contains("sin-sesion")) {
              if (mounted) setState(() => estado = "Sesión caducada. Reinicia la app.");
            }
          }
        },
        onError: (_) => _reintentar(),
        onDone: () => _reintentar(),
      );
      // configuración inicial del video
      c.sink.add(jsonEncode({"t": "cfg", "ancho_maximo": 1280, "calidad_jpeg": 55, "fps": 12, "pantalla": 1}));
    } catch (_) {
      _reintentar();
    }
  }

  void _reintentar() {
    if (!mounted) return;
    setState(() => estado = "PC sin conexión. Reintentando…");
    reintento?.cancel();
    reintento = Timer(const Duration(seconds: 3), () { if (mounted) _conectar(); });
  }

  @override
  void dispose() {
    reintento?.cancel();
    canal?.sink.close();
    super.dispose();
  }

  void _enviar(Map<String, Object?> evento) {
    try { canal?.sink.add(jsonEncode(evento)); } catch (_) {}
  }

  void _tocarPixel(Offset local, double boxAncho, double boxAlto) {
    // coordenada normalizada respecto a la imagen mostrada
    if (ultimoFotograma == null) return;
    final nx = (local.dx / boxAncho).clamp(0.0, 1.0);
    final ny = (local.dy / boxAlto).clamp(0.0, 1.0);
    _enviar({"t": "mover", "x": nx, "y": ny});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ultimoFotograma == null
              ? Center(child: Text(estado, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)))
              : LayoutBuilder(builder: (context, caja) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final nx = (d.localPosition.dx / caja.maxWidth).clamp(0.0, 1.0);
                      final ny = (d.localPosition.dy / caja.maxHeight).clamp(0.0, 1.0);
                      _enviar({"t": "clic", "x": nx, "y": ny, "b": "izq"});
                    },
                    onLongPressStart: (d) {
                      final nx = (d.localPosition.dx / caja.maxWidth).clamp(0.0, 1.0);
                      final ny = (d.localPosition.dy / caja.maxHeight).clamp(0.0, 1.0);
                      _enviar({"t": "mover", "x": nx, "y": ny});
                      _enviar({"t": "pulsar", "x": nx, "y": ny, "b": "der"});
                    },
                    onLongPressEnd: (d) => _enviar({"t": "soltar", "b": "der"}),
                    onPanStart: (d) {
                      final nx = (d.localPosition.dx / caja.maxWidth).clamp(0.0, 1.0);
                      final ny = (d.localPosition.dy / caja.maxHeight).clamp(0.0, 1.0);
                      _enviar({"t": "pulsar", "x": nx, "y": ny, "b": "izq"});
                    },
                    onPanUpdate: (d) {
                      final nx = (d.localPosition.dx / caja.maxWidth).clamp(0.0, 1.0);
                      final ny = (d.localPosition.dy / caja.maxHeight).clamp(0.0, 1.0);
                      _enviar({"t": "mover", "x": nx, "y": ny});
                    },
                    onPanEnd: (_) => _enviar({"t": "soltar", "b": "izq"}),
                    onPanCancel: () => _enviar({"t": "soltar", "b": "izq"}),
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 1.0,
                      maxScale: 8.0,
                      child: Align(
                        alignment: Alignment.center,
                        child: AspectRatio(
                          aspectRatio: 1280 / 720,
                          child: Image.memory(ultimoFotograma!, fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                      ),
                    ),
                  );
                }),
        ),
        Text(estado, style: const TextStyle(fontSize: 11, color: Colors.white38)),
      ],
    );
  }
}

// ------------------------------------------------------------------ estado ---

class PantallaEstado extends StatefulWidget {
  final Conexion conexion;
  const PantallaEstado({super.key, required this.conexion});
  @override
  State<PantallaEstado> createState() => _PantallaEstadoState();
}

class _PantallaEstadoState extends State<PantallaEstado> {
  DatosEstado? datos;
  Timer? reloj;

  @override
  void initState() {
    super.initState();
    _consultar();
    reloj = Timer.periodic(const Duration(seconds: 3), (_) => _consultar());
  }

  Future<void> _consultar() async {
    try {
      final r = await http.get(
        Uri.parse("${widget.conexion.base}/api/estado"),
        headers: {"Cookie": "sesion=${widget.conexion.token}"},
      ).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200 && mounted) {
        setState(() => datos = DatosEstado.desdeJson(jsonDecode(r.body)));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    reloj?.cancel();
    super.dispose();
  }

  String _segsA(int s) {
    final h = s ~/ 3600;
    return "$h h ${(s % 3600) ~/ 60} min";
  }

  @override
  Widget build(BuildContext context) {
    final d = datos;
    if (d == null) return const Center(child: Text("Consultando…", style: TextStyle(color: Colors.white38)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _barra("CPU", d.cpu),
        _barra("RAM", d.ram),
        const SizedBox(height: 12),
        _tarjeta("Detalles", d.detalle + "\nEquipo: ${d.host}"),
        const SizedBox(height: 12),
        _tarjeta("Procesos más pesados", d.procesos.isEmpty
            ? "—"
            : d.procesos.map((p) {
                final cpu = (p["cpu"] as num?)?.toDouble() ?? 0.0;
                return "${p["nombre"]}  ${cpu.toStringAsFixed(1)}%";
              }).join("\n")),
        const SizedBox(height: 12),
        _tarjeta("Encendido", _segsA(d.encendidoS)),
      ],
    );
  }

  Widget _barra(String titulo, double pct) {
    final color = pct > 88 ? const Color(0xFFF87171) : pct > 70 ? const Color(0xFFFBBF24) : const Color(0xFF4F83FF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$titulo  ${pct.toStringAsFixed(0)}%", style: const TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: pct / 100, color: color, backgroundColor: const Color(0xFF1B2233), minHeight: 9, borderRadius: BorderRadius.circular(6)),
        ],
      ),
    );
  }

  Widget _tarjeta(String titulo, String contenido) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF131A2B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF232C42))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo.toUpperCase(), style: const TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(contenido, style: const TextStyle(fontSize: 13.5)),
      ]),
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
  SharedPreferences? _prefs;

  Future<WebSocketChannel> _abrirCanal() async {
    _prefs ??= await SharedPreferences.getInstance();
    // el token guardado permite reabrir el canal de atajos sin nueva sesión
    return WebSocketChannel.connect(Uri.parse(widget.conexion.urlWs));
  }

  Future<void> _atajo(Map<String, Object?> evento) async {
    WebSocketChannel? c;
    try {
      c = await _abrirCanal();
      c.sink.add(jsonEncode(evento));
      await c.sink.close();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
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
      "Borrar": {"t": "teclas", "mods": [], "k": "backspace"},
      "F5": {"t": "teclas", "mods": [], "k": "f5"},
      "F11": {"t": "teclas", "mods": [], "k": "f11"},
    };
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(children: [
          Expanded(
            child: TextField(controller: _texto, decoration: const InputDecoration(hintText: "Escribe y envía (acepta ñ, á…)", filled: true, border: OutlineInputBorder())),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.send),
            onPressed: () => _atajo({"t": "texto", "s": _texto.text}),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: atajos.entries
              .map((e) => ActionChip(label: Text(e.key), labelStyle: const TextStyle(fontSize: 12.5), onPressed: () => _atajo(e.value)))
              .toList(),
        ),
        const SizedBox(height: 10),
        Text("Consejo: escribe texto aquí (Enter envía) y usa los chips para atajos.",
            style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
        Text("La escritura se envía por la conexión abierta cuando vuelvas a la pestaña Pantalla.",
            style: const TextStyle(fontSize: 11.5, color: Colors.white30)),
      ],
    );
  }
}
