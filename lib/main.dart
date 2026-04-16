import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
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
  late CameraController controller;
  late FlutterVision vision;
  late FlutterTts tts;

  bool isDetecting = false;
  bool isPaused = false;
  List<Map<String, dynamic>> yoloResults = [];
  String lastObject = "";
  DateTime lastSpeechTime = DateTime.now();

  // Variáveis para as dimensões da imagem (Resolve o erro Undefined name)
  double imageWidthOriginal = 1024.0;
  double imageHeightOriginal = 1024.0;

  final Map<String, String> tradutor = {
    "backpack": "mochila",
    "book": "livro",
    "cell phone": "celular",
    "chair": "cadeira",
    "cup": "copo",
    "laptop": "notebook",
    "keyboard": "teclado",
    "mouse": "mouse",
    "remote": "controle remoto",
    "tv": "televisão",
    "bottle": "garrafa",
    "car": "carro",
    "motorcycle": "moto",
    "dog": "cachorro",
    "cat": "gato",
    "bird": "pássaro",
    "apple": "maçã",
    "banana": "banana",
    "bed": "cama",
    "sink": "pia",
    "refrigerator": "geladeira",
    "scissors": "tesoura",
    "toothbrush": "escova de dente",
    "clock": "relógio",
    "spoon": "colher",
    "fork": "garfo",
    "knife": "faca",
    "bowl": "tigela",
  };

  @override
  void initState() {
    super.initState();
    vision = FlutterVision();
    tts = FlutterTts();
    setupSpeech();
    initCameraAndModel();
  }

  setupSpeech() async {
    await tts.setLanguage("pt-BR");
    await tts.setSpeechRate(0.6);
  }

  initCameraAndModel() async {
    controller = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();

    await vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/best_int8.tflite',
      modelVersion: "yolov8",
      numThreads: 4,
      useGpu: true,
    );

    controller.startImageStream((image) {
      if (!isDetecting && !isPaused) {
        isDetecting = true;
        // Atualiza as dimensões baseada no frame real da câmera
        imageWidthOriginal = image.width.toDouble();
        imageHeightOriginal = image.height.toDouble();
        runInference(image);
      }
    });
    setState(() {});
  }

  runInference(CameraImage image) async {
    final result = await vision.yoloOnFrame(
      bytesList: image.planes.map((plane) => plane.bytes).toList(),
      imageHeight: image.height,
      imageWidth: image.width,
      iouThreshold: 0.4,
      confThreshold: 0.60,
      classThreshold: 0.60,
    );

    if (result.isNotEmpty) {
      setState(() {
        yoloResults = result;
      });

      var obj = result.reduce((a, b) {
        // CORREÇÃO: Adicionado .toDouble() para resolver o erro de int vs double
        double areaA =
            (a['box'][2].toDouble() - a['box'][0].toDouble()) *
            (a['box'][3].toDouble() - a['box'][1].toDouble());
        double areaB =
            (b['box'][2].toDouble() - b['box'][0].toDouble()) *
            (b['box'][3].toDouble() - b['box'][1].toDouble());
        return areaA > areaB ? a : b;
      });

      double xCenter =
          (obj['box'][0].toDouble() + obj['box'][2].toDouble()) / 2;
      double area =
          (obj['box'][2].toDouble() - obj['box'][0].toDouble()) *
          (obj['box'][3].toDouble() - obj['box'][1].toDouble());
      double totalArea = image.width.toDouble() * image.height.toDouble();
      double ratio = area / totalArea;

      String tag = obj['tag'].toString().toLowerCase();
      String nome = tradutor[tag] ?? tag;
      String pos =
          (xCenter < image.width / 3)
              ? "à esquerda"
              : (xCenter < 2 * image.width / 3 ? "à frente" : "à direita");

      processAccessibility(nome, pos, ratio);
    } else {
      setState(() {
        yoloResults = [];
      });
    }
    isDetecting = false;
  }

  void processAccessibility(String nome, String pos, double ratio) async {
    var agora = DateTime.now();
    bool isDanger = ratio > 0.35;

    if (isDanger) {
      Vibration.vibrate(duration: 500);
      await tts.speak("Cuidado! $nome muito perto!");
    } else {
      if (nome != lastObject ||
          agora.difference(lastSpeechTime).inSeconds > 5) {
        await tts.speak("$nome $pos");
        lastObject = nome;
        lastSpeechTime = agora;
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    vision.closeYoloModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
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
            CameraPreview(controller),
            // Desenha as caixas (visual para sua defesa do TCC)
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
                    "${res["tag"]} ${(res["box"][4] * 100).toStringAsFixed(0)}%",
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontWeight: FontWeight.bold,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              );
            }), // CORREÇÃO: Removido .toList() desnecessário
          ],
        ),
      ),
    );
  }
}
