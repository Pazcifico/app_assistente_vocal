import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    cameras = await availableCameras();
  }

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: TccVisionApp()),
  );
}

class TccVisionApp extends StatefulWidget {
  const TccVisionApp({super.key});

  @override
  State<TccVisionApp> createState() => _TccVisionAppState();
}

class _TccVisionAppState extends State<TccVisionApp> {
  CameraController? controller;
  late FlutterVision vision;
  late FlutterTts tts;

  bool isDetecting = false;
  bool isPaused = false;

  List<Map<String, dynamic>> yoloResults = [];

  String lastObject = "";
  DateTime lastSpeechTime = DateTime.now();

  double imageWidthOriginal = 1024;
  double imageHeightOriginal = 1024;

  final Map<String, String> tradutor = {
    "apple": "maçã",
    "backpack": "mochila",
    "ball": "bola",
    "banana": "banana",
    "bed": "cama",
    "bench": "banco",
    "bicycle": "bicicleta",
    "bird": "pássaro",
    "boat": "barco",
    "book": "livro",
    "bottle": "garrafa",
    "bowl": "tigela",
    "broccoli": "brócolis",
    "can": "lata",
    "cake": "bolo",
    "car": "carro",
    "cat": "gato",
    "cell phone": "celular",
    "cellphone": "celular",
    "chair": "cadeira",
    "clock": "relógio",
    "couch": "sofá",
    "cow": "vaca",
    "cup": "copo",
    "dining table": "mesa",
    "dog": "cachorro",
    "door": "porta",
    "door mat": "tapete",
    "donut": "rosquinha",
    "dustpan": "pá",
    "envelope": "envelope",
    "fan": "ventilador",
    "fire hydrant": "hidrante",
    "flag pole": "mastro",
    "folder": "pasta",
    "fork": "garfo",
    "frisbee": "frisbee",
    "gate": "portão",
    "hair drier": "secador",
    "handbag": "bolsa",
    "horse": "cavalo",
    "hot dog": "cachorro-quente",
    "key": "chave",
    "keyboard": "teclado",
    "kite": "pipa",
    "knife": "faca",
    "laptop": "notebook",
    "microwave": "micro-ondas",
    "motorcycle": "moto",
    "mouse": "mouse",
    "orange": "laranja",
    "outlet": "tomada",
    "oven": "forno",
    "paper clip": "clipe",
    "parking meter": "parquímetro",
    "pen": "caneta",
    "pillow": "travesseiro",
    "pizza": "pizza",
    "potted plant": "planta",
    "pottedplant": "planta",
    "power switch": "interruptor",
    "refrigerator": "geladeira",
    "remote": "controle",
    "sandwich": "sanduíche",
    "scissor": "tesoura",
    "scissors": "tesoura",
    "shoes": "sapato",
    "sheep": "ovelha",
    "sink": "pia",
    "skateboard": "skate",
    "sofa": "sofá",
    "spoon": "colher",
    "sports ball": "bola",
    "stapler": "grampeador",
    "star": "estrela",
    "stair": "escada",
    "stop sign": "pare",
    "suitcase": "mala",
    "surfboard": "prancha",
    "tv": "TV",
    "teddy bear": "urso",
    "tennis racket": "raquete",
    "tie": "gravata",
    "toaster": "torradeira",
    "toilet": "vaso",
    "toothbrush": "escova",
    "traffic light": "sinal",
    "trash can": "lixeira",
    "triangle": "triângulo",
    "truck": "caminhão",
    "umbrella": "guarda-chuva",
    "vase": "vaso",
    "wine glass": "taça",
  };

  @override
  void initState() {
    super.initState();

    vision = FlutterVision();
    tts = FlutterTts();

    setupSpeech();
    initCameraAndModel();
  }

  Future<void> setupSpeech() async {
    await tts.setLanguage("pt-BR");
    await tts.setSpeechRate(0.5);
  }

  Future<void> initCameraAndModel() async {
    if (kIsWeb) return;

    controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();

    await vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/best_float32.tflite',
      modelVersion: "yolov8",
      numThreads: 2,
      useGpu: false,
    );

    controller!.startImageStream((image) {
      if (!isDetecting && !isPaused) {
        isDetecting = true;

        imageWidthOriginal = image.width.toDouble();
        imageHeightOriginal = image.height.toDouble();

        runInference(image);
      }
    });

    setState(() {});
  }

  Future<void> runInference(CameraImage image) async {
    final result = await vision.yoloOnFrame(
      bytesList: image.planes.map((plane) => plane.bytes).toList(),
      imageHeight: image.height,
      imageWidth: image.width,
      iouThreshold: 0.4,
      confThreshold: 0.6,
      classThreshold: 0.6,
    );

    if (result.isNotEmpty) {
      setState(() => yoloResults = result);

      var obj = result.reduce((a, b) {
        double areaA =
            (a['box'][2] - a['box'][0]) * (a['box'][3] - a['box'][1]);

        double areaB =
            (b['box'][2] - b['box'][0]) * (b['box'][3] - b['box'][1]);

        return areaA > areaB ? a : b;
      });

      double xCenter = (obj['box'][0] + obj['box'][2]) / 2;

      double area =
          (obj['box'][2] - obj['box'][0]) * (obj['box'][3] - obj['box'][1]);

      double ratio = area / (image.width * image.height);

      String tag = obj['tag'].toLowerCase();

      String nome = tradutor[tag] ?? tag;

      String pos =
          xCenter < image.width / 3
              ? "à esquerda"
              : xCenter < 2 * image.width / 3
              ? "à frente"
              : "à direita";

      String dist = "longe";

      if (ratio > 0.35)
        dist = "muito perto";
      else if (ratio > 0.10)
        dist = "perto";
      else if (ratio > 0.03)
        dist = "a média distância";

      processAccessibility(nome, pos, dist, ratio);
    } else {
      setState(() => yoloResults = []);
    }

    isDetecting = false;
  }

  Future<void> processAccessibility(
    String nome,
    String pos,
    String dist,
    double ratio,
  ) async {
    var agora = DateTime.now();

    if (ratio > 0.35) {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 500);
      }

      await tts.speak("Cuidado! $nome muito perto!");
    } else {
      String anuncio = "$nome $pos, $dist";

      if (anuncio != lastObject ||
          agora.difference(lastSpeechTime).inSeconds > 5) {
        await tts.speak(anuncio);

        lastObject = anuncio;
        lastSpeechTime = agora;
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    vision.closeYoloModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: GestureDetector(
        onTap: () => tts.speak("Sistema ativo. Olhando para $lastObject"),
        onDoubleTap: () {
          setState(() => isPaused = !isPaused);
          tts.speak(isPaused ? "Câmera pausada" : "Câmera ligada");
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller!),

            ...yoloResults.map((res) {
              return Positioned(
                left: res["box"][0] * (size.width / imageWidthOriginal),
                top: res["box"][1] * (size.height / imageHeightOriginal),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.yellow, width: 2),
                  ),
                  child: Text(
                    "${tradutor[res["tag"].toLowerCase()] ?? res["tag"]} ${(res["box"][4] * 100).toStringAsFixed(0)}%",
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontWeight: FontWeight.bold,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
