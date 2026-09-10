import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Erro ao inicializar câmeras: $e');
  }
  runApp(const CameraTestApp());
}

class CameraTestApp extends StatelessWidget {
  const CameraTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detecção de Objetos via Sockets TCP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CameraHomePage(),
    );
  }
}

class CameraHomePage extends StatefulWidget {
  const CameraHomePage({super.key});

  @override
  State<CameraHomePage> createState() => _CameraHomePageState();
}

class _CameraHomePageState extends State<CameraHomePage> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  
  Uint8List? _capturedImageBytes;
  bool _isProcessing = false;
  String _statusMessage = 'Aguardando ação. Toque em "Tirar e Analisar" para iniciar.';
  
  List<String> _detectedObjects = [];
  bool _hasAnalyzed = false;

  String _serverIp = '192.168.1.100';
  int _serverPort = 5000;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    
    // Tenta usar a câmera traseira
    CameraDescription? selectedCamera;
    for (var camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        selectedCamera = camera;
        break;
      }
    }
    selectedCamera ??= cameras.first;

    _controller = CameraController(
      selectedCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Erro ao inicializar câmera: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndAnalyze() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Capturando imagem...';
    });

    try {
      final XFile photo = await _controller!.takePicture();
      
      setState(() {
        _statusMessage = 'Comprimindo imagem...';
      });

      // Comprime para JPEG (~80%) com largura máxima de 1280px
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        photo.path,
        minWidth: 1280,
        quality: 80,
        format: CompressFormat.jpeg,
      );

      if (compressedBytes != null) {
        setState(() {
          _capturedImageBytes = compressedBytes;
          _hasAnalyzed = false;
          _detectedObjects = [];
        });

        await _sendImageViaTcp(compressedBytes);
      } else {
        setState(() {
          _statusMessage = 'Erro ao comprimir imagem.';
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint('[ERRO] Falha ao capturar imagem: $e');
      setState(() {
        _statusMessage = 'Erro na câmera: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _sendImageViaTcp(Uint8List imageBytes) async {
    if (kIsWeb) {
      setState(() {
        _statusMessage = 'Sockets TCP não são suportados no navegador Web.';
        _isProcessing = false;
      });
      return;
    }

    setState(() {
      _statusMessage = 'Conectando ao servidor Python em $_serverIp:$_serverPort...';
    });

    Socket? socket;
    try {
      final sizeKb = (imageBytes.length / 1024).toStringAsFixed(1);

      debugPrint('[TCP] Conectando a $_serverIp:$_serverPort...');
      socket = await Socket.connect(
        _serverIp,
        _serverPort,
        timeout: const Duration(seconds: 6),
      );

      setState(() {
        _statusMessage = 'Enviando imagem ($sizeKb KB) para o servidor...';
      });

      final lengthHeader = ByteData(4)..setUint32(0, imageBytes.length, Endian.big);
      socket.add(lengthHeader.buffer.asUint8List());
      socket.add(imageBytes);
      await socket.flush();

      setState(() {
        _statusMessage = 'Processando detecção no servidor (YOLO)...';
      });

      final receivedBytes = <int>[];
      final completer = Completer<void>();

      final subscription = socket.listen(
        (chunk) {
          receivedBytes.addAll(chunk);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        cancelOnError: true,
      );

      try {
        await completer.future.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        debugPrint('[TCP] Timeout aguardando fechamento.');
      }
      await subscription.cancel();

      final responseText = utf8.decode(receivedBytes, allowMalformed: true).trim();
      
      final lines = responseText
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      setState(() {
        _hasAnalyzed = true;
        if (lines.isEmpty || responseText.toLowerCase().contains('nada detectado')) {
          _detectedObjects = ['Nada Detectado'];
          _statusMessage = 'Análise concluída: nenhum objeto identificado.';
        } else {
          _detectedObjects = lines;
          _statusMessage = 'Análise concluída com sucesso! ${_detectedObjects.length} item(ns) encontrado(s).';
        }
      });
    } catch (e) {
      setState(() {
        _hasAnalyzed = true;
        _detectedObjects = [];
        _statusMessage = 'Falha no socket TCP ($_serverIp:$_serverPort):\n$e';
      });
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}

      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _clearImage() {
    setState(() {
      _capturedImageBytes = null;
      _detectedObjects = [];
      _hasAnalyzed = false;
      _statusMessage = 'Pronto. Toque em "Tirar e Analisar" para iniciar.';
    });
  }

  void _openSettingsDialog() {
    final ipController = TextEditingController(text: _serverIp);
    final portController = TextEditingController(text: _serverPort.toString());
    String? testMessage;
    bool? testSuccess;
    bool isTesting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> testTcpConnection() async {
              final host = ipController.text.trim();
              final port = int.tryParse(portController.text.trim());

              if (host.isEmpty || port == null || port <= 0 || port > 65535) {
                setDialogState(() {
                  testSuccess = false;
                  testMessage = 'Informe IP e porta válidos (1 a 65535).';
                });
                return;
              }

              setDialogState(() {
                isTesting = true;
                testMessage = null;
                testSuccess = null;
              });

              try {
                final socket = await Socket.connect(
                  host,
                  port,
                  timeout: const Duration(seconds: 3),
                );
                socket.destroy();

                setDialogState(() {
                  isTesting = false;
                  testSuccess = true;
                  testMessage = '✓ Conexão bem-sucedida com $host:$port!';
                });
              } catch (e) {
                setDialogState(() {
                  isTesting = false;
                  testSuccess = false;
                  testMessage = 'Falha ao conectar: $e';
                });
              }
            }

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Text('Servidor Python', style: TextStyle(fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ipController,
                      decoration: const InputDecoration(
                        labelText: 'Endereço IP',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Porta TCP',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isTesting ? null : testTcpConnection,
                      icon: isTesting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.network_check_outlined),
                      label: Text(isTesting ? 'Testando...' : 'Testar Conexão'),
                    ),
                    if (testMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        testMessage!,
                        style: TextStyle(
                          color: testSuccess == true ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final ip = ipController.text.trim();
                    final port = int.tryParse(portController.text.trim());

                    if (ip.isEmpty || port == null || port <= 0 || port > 65535) return;

                    setState(() {
                      _serverIp = ip;
                      _serverPort = port;
                      _statusMessage = 'Servidor configurado para $_serverIp:$_serverPort';
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetectionResultsCard(ColorScheme colorScheme) {
    if (!_hasAnalyzed && !_isProcessing) return const SizedBox.shrink();

    if (_isProcessing) {
      return Card(
        color: colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 14),
              Text('Analisando...', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    final isNothingDetected = _detectedObjects.isEmpty ||
        (_detectedObjects.length == 1 && _detectedObjects.first.toLowerCase().contains('nada detectado'));

    return Card(
      color: isNothingDetected ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNothingDetected ? 'Nada Detectado' : 'Objetos Detectados:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isNothingDetected ? Colors.orange[900] : Colors.green[900],
              ),
            ),
            if (!isNothingDetected) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _detectedObjects.map((item) => Chip(label: Text(item))).toList(),
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detecção YOLO'),
        actions: [
          if (_capturedImageBytes != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isProcessing ? null : _clearImage,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Servidor: $_serverIp:$_serverPort', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _capturedImageBytes != null
                      ? Image.memory(_capturedImageBytes!, fit: BoxFit.cover, width: double.infinity)
                      : (_isCameraInitialized
                          ? CameraPreview(_controller!)
                          : const Center(child: CircularProgressIndicator())),
                ),
              ),
              const SizedBox(height: 12),
              
              _buildDetectionResultsCard(colorScheme),
              const SizedBox(height: 8),
              
              Text(_statusMessage, style: const TextStyle(color: Colors.grey), maxLines: 2),
              const SizedBox(height: 14),
              
              FilledButton.icon(
                onPressed: _isProcessing || _capturedImageBytes != null ? null : _captureAndAnalyze,
                icon: const Icon(Icons.camera),
                label: const Text('Tirar e Analisar', style: TextStyle(fontSize: 16)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
