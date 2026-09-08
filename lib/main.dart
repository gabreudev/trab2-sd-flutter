import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

void main() {
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
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  bool _isProcessing = false;
  String _statusMessage = 'Aguardando ação. Toque em "Tirar e Analisar" para iniciar.';
  
  // Lista de objetos detectados retornados pelo servidor
  List<String> _detectedObjects = [];
  bool _hasAnalyzed = false;

  // Configurações do serviço TCP
  String _serverIp = '192.168.1.100';
  int _serverPort = 5000;

  /// Fluxo principal do trabalho:
  /// Captura foto com max 1280px e qualidade 80 JPEG, depois envia via socket TCP
  Future<void> _captureAndAnalyze() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Abrindo câmera para captura...';
    });

    try {
      // Requisito do trabalho: JPEG, qualidade ~80, largura até 1280px
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1280,
        imageQuality: 80,
      );

      if (photo != null) {
        setState(() {
          _imageFile = photo;
          _hasAnalyzed = false;
          _detectedObjects = [];
        });

        // Envia automaticamente para o servidor Python
        await _sendImageViaTcp(photo);
      } else {
        setState(() {
          _statusMessage = 'Captura cancelada pelo usuário.';
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

  /// Opção alternativa: Escolher da galeria (com o mesmo redimensionamento e qualidade)
  Future<void> _pickFromGalleryAndAnalyze() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Abrindo galeria...';
    });

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 80,
      );

      if (photo != null) {
        setState(() {
          _imageFile = photo;
          _hasAnalyzed = false;
          _detectedObjects = [];
        });

        await _sendImageViaTcp(photo);
      } else {
        setState(() {
          _statusMessage = 'Seleção cancelada.';
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erro na galeria: $e';
        _isProcessing = false;
      });
    }
  }

  /// Comunicação TCP conforme especificação do trabalho:
  /// [4 bytes Big-Endian com tamanho] + [bytes da foto em JPEG]
  Future<void> _sendImageViaTcp(XFile photo) async {
    if (kIsWeb) {
      setState(() {
        _statusMessage = 'Sockets TCP não são suportados no navegador Web.';
        _isProcessing = false;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Conectando ao servidor Python em $_serverIp:$_serverPort...';
    });

    Socket? socket;
    try {
      final file = File(photo.path);
      final imageBytes = await file.readAsBytes();
      final sizeKb = (imageBytes.length / 1024).toStringAsFixed(1);

      debugPrint('[TCP] Conectando a $_serverIp:$_serverPort...');
      socket = await Socket.connect(
        _serverIp,
        _serverPort,
        timeout: const Duration(seconds: 6),
      );

      debugPrint('[TCP] Conectado! Enviando cabeçalho (4 bytes) + imagem ($sizeKb KB)...');
      setState(() {
        _statusMessage = 'Enviando imagem ($sizeKb KB) para o servidor...';
      });

      // 1. Cria cabeçalho de 4 bytes com o tamanho da imagem (Big-Endian uint32)
      final lengthHeader = ByteData(4)..setUint32(0, imageBytes.length, Endian.big);

      // 2. Envia cabeçalho e bytes da foto
      socket.add(lengthHeader.buffer.asUint8List());
      socket.add(imageBytes);
      await socket.flush();

      debugPrint('[TCP] Imagem enviada! Aguardando detecção do modelo...');
      setState(() {
        _statusMessage = 'Processando detecção no servidor (YOLO)...';
      });

      // 3. Lê resposta do servidor com timeout de 15 segundos
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

      // Aguarda o término da transmissão do servidor ou fecha por timeout
      try {
        await completer.future.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        debugPrint('[TCP] Timeout aguardando fechamento. Processando bytes recebidos.');
      }
      await subscription.cancel();

      final responseText = utf8.decode(receivedBytes, allowMalformed: true).trim();
      debugPrint('[TCP] Resposta recebida do servidor: "$responseText"');

      // 4. Trata resultado
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
      debugPrint('[TCP] Erro na comunicação socket: $e');
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
      _imageFile = null;
      _detectedObjects = [];
      _hasAnalyzed = false;
      _statusMessage = 'Pronto. Toque em "Tirar e Analisar" para iniciar.';
    });
  }

  /// Diálogo da engrenagem para configurar IP e Porta do serviço TCP
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
              if (kIsWeb) {
                setDialogState(() {
                  testSuccess = false;
                  testMessage = 'Sockets TCP não são suportados no navegador Web.';
                });
                return;
              }

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
                  Text('Servidor Python (TCP)', style: TextStyle(fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configure o IP e a porta do servidor Python onde o modelo YOLO está rodando.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ipController,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'Endereço IP do Servidor',
                        hintText: 'Ex: 192.168.1.100',
                        prefixIcon: Icon(Icons.lan_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Porta TCP',
                        hintText: 'Ex: 5000',
                        prefixIcon: Icon(Icons.numbers_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isTesting ? null : testTcpConnection,
                      icon: isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check_outlined),
                      label: Text(isTesting ? 'Testando...' : 'Testar Conexão'),
                    ),
                    if (testMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: testSuccess == true
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: testSuccess == true ? Colors.green : Colors.red,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              testSuccess == true
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: testSuccess == true ? Colors.green : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                testMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: testSuccess == true
                                      ? (Theme.of(context).brightness == Brightness.dark
                                          ? Colors.greenAccent
                                          : Colors.green.shade800)
                                      : (Theme.of(context).brightness == Brightness.dark
                                          ? Colors.redAccent
                                          : Colors.red.shade800),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

                    if (ip.isEmpty || port == null || port <= 0 || port > 65535) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Por favor, informe um IP e porta válidos.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    setState(() {
                      _serverIp = ip;
                      _serverPort = port;
                      _statusMessage = 'Servidor TCP configurado para $_serverIp:$_serverPort';
                    });

                    Navigator.of(dialogContext).pop();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Servidor salvo: $_serverIp:$_serverPort'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
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

  Widget _buildImagePreview() {
    if (_imageFile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhuma foto capturada',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Toque em "Tirar e Analisar" abaixo',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: kIsWeb
          ? Image.network(
              _imageFile!.path,
              fit: BoxFit.cover,
              width: double.infinity,
            )
          : Image.file(
              File(_imageFile!.path),
              fit: BoxFit.cover,
              width: double.infinity,
            ),
    );
  }

  /// Painel de resultados da detecção do YOLO
  Widget _buildDetectionResultsCard(ColorScheme colorScheme) {
    if (!_hasAnalyzed && !_isProcessing) {
      return const SizedBox.shrink();
    }

    if (_isProcessing) {
      return Card(
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 14),
              Text(
                'Transmitindo e analisando imagem...',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final isNothingDetected = _detectedObjects.isEmpty ||
        (_detectedObjects.length == 1 &&
            _detectedObjects.first.toLowerCase().contains('nada detectado'));

    return Card(
      color: isNothingDetected
          ? Colors.orange.withValues(alpha: 0.12)
          : Colors.green.withValues(alpha: 0.12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isNothingDetected ? Colors.orange : Colors.green,
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isNothingDetected
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: isNothingDetected ? Colors.orange[800] : Colors.green[800],
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  isNothingDetected ? 'Resultado da Análise' : 'Objetos Detectados:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isNothingDetected ? Colors.orange[900] : Colors.green[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isNothingDetected)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  'Nada Detectado',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900],
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _detectedObjects.map((item) {
                  return Chip(
                    avatar: const Icon(Icons.label_outline, size: 16),
                    label: Text(
                      item,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.green.withValues(alpha: 0.25)
                        : Colors.green.shade100,
                  );
                }).toList(),
              ),
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
        title: const Text('Detecção de Objetos (Sockets)'),
        centerTitle: true,
        backgroundColor: colorScheme.surfaceContainerHighest,
        actions: [
          if (_imageFile != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Limpar imagem',
              onPressed: _isProcessing ? null : _clearImage,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configurar Servidor TCP',
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
              // Barra informativa do servidor configurado
              InkWell(
                onTap: _openSettingsDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.settings_ethernet,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Serviço TCP Destino',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.outline,
                                  ),
                            ),
                            Text(
                              '$_serverIp:$_serverPort',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Área da imagem capturada
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                  child: _buildImagePreview(),
                ),
              ),
              const SizedBox(height: 12),

              // Painel de Resultados da Análise (YOLO)
              _buildDetectionResultsCard(colorScheme),
              const SizedBox(height: 8),

              // Card de Status da Conexão / Logs
              Card(
                elevation: 0,
                color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                              ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Botão Principal conforme o roteiro do professor: "Tirar e Analisar"
              FilledButton.icon(
                onPressed: _isProcessing ? null : _captureAndAnalyze,
                icon: const Icon(Icons.camera_alt),
                label: const Text(
                  'Tirar e Analisar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Botão secundário para testar com imagem da galeria
              OutlinedButton.icon(
                onPressed: _isProcessing ? null : _pickFromGalleryAndAnalyze,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Escolher da Galeria e Analisar'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
