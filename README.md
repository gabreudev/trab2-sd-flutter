# Atividade 2 – Foto via Botão (Android → Servidor Python por Sockets)
**Sistemas Distribuídos - 8º Período**

Aplicação cliente-servidor para captura de fotos em dispositivo Android e detecção automatizada de objetos via sockets TCP utilizando Inteligência Artificial (**YOLOv8** e **OpenCV**).

---

## 🏛️ Arquitetura e Protocolo de Comunicação

1. **Cliente (Flutter/Dart):**
   - Captura a foto da câmera ou seleciona da galeria com largura máxima de **1280px** e qualidade **JPEG ~80%**.
   - Conecta-se via Socket TCP na porta configurada (padrão: `5000`).
   - **Protocolo de Envio:**
     - **4 bytes:** Inteiro de 32 bits sem sinal em formato Big-Endian (`uint32`) contendo o tamanho $N$ da imagem em bytes.
     - **$N$ bytes:** Fluxo bruto dos bytes da foto em formato JPEG.
   - Aguarda a resposta em texto do servidor e exibe os objetos identificados.

2. **Servidor (Python):**
   - Recebe o cabeçalho de 4 bytes e lê exatamente os $N$ bytes da imagem.
   - Salva a foto recebida na pasta `capturas/` com timestamp (`captura_YYYYMMDD_HHMMSS.jpg`).
   - Decodifica a imagem com **OpenCV** (`cv2.imdecode`).
   - Realiza a inferência com **YOLOv8n** (`ultralytics`).
   - Salva uma cópia da imagem com as marcações/bounding boxes em `capturas/anotadas/`.
   - Retorna via socket TCP a lista de objetos identificados (ex: *Pessoa detectada*, *Cadeira detectada*, *Mochila detectada*) ou *Nada Detectado*.

---

## 🚀 Como Rodar o Servidor Python

### 1. Pré-requisitos
* Python 3.10+ instalado no computador.

### 2. Ativação do Ambiente Virtual (`venv`) e Instalação
O ambiente virtual `.venv` já está configurado no projeto:

```bash
# Ative a venv no terminal
source .venv/bin/activate

# (Caso precise reinstalar as dependências)
pip install -r requirements.txt
```

### 3. Iniciar o Servidor
```bash
python server.py
```
O terminal exibirá o **endereço IP local** da sua máquina (ex.: `192.168.1.100`) e a mensagem `Aguardando imagem...`.

---

## 📱 Como Configurar e Rodar o App Flutter

### 1. Conectar o Celular e Iniciar o App
Com o celular Android conectado via USB (ou depuração por Wi-Fi) e autorizado:

```bash
flutter run
```

### 2. Configurar o IP e a Porta no App
1. No canto superior direito da tela do aplicativo, toque no **ícone de engrenagem** ⚙️ (ou no card de status do topo).
2. Digite o **Endereço IP** exibido no terminal do `server.py` e a **Porta** (`5000`).
3. Toque no botão **"Testar Conexão"** para verificar se o celular consegue alcançar o computador via rede local.
4. Toque em **"Salvar"**.

---

## 🎬 Roteiro de Demonstração (Passo a Passo)

1. **Iniciar o Servidor:**
   * Execute `python server.py`. A janela permanecerá aberta com a mensagem `"Aguardando imagem..."`.
2. **No Aplicativo:**
   * Certifique-se de que o IP e Porta do servidor estão corretos.
   * Toque no botão principal **"Tirar e Analisar"**.
   * Tire a foto de um ou mais objetos (ex: uma pessoa, uma cadeira, uma garrafa ou mochila) e confirme.
3. **No Servidor:**
   * O servidor recebe os bytes, salva a imagem em `capturas/` e executa a detecção do YOLO.
   * Exibe no terminal os itens detectados e devolve o texto ao app.
4. **Resultado no App:**
   * O aplicativo exibe os badges com os nomes dos objetos (ex: `Pessoa detectada`, `Mochila detectada`).
   * Caso a foto não contenha objetos reconhecíveis, exibirá `Nada Detectado`.
5. **Nova Captura:**
   * Toque novamente em **"Tirar e Analisar"** para uma nova foto; o resultado se atualizará instantaneamente.

---

## 🖼️ Capturas de Tela e Evidências

> Adicione aqui as capturas de tela para a entrega final:
> 
> * **Interface do Aplicativo com Resultado:** *(Inserir print)*
> * **Foto Capturada salva pelo Servidor (`capturas/`):** *(Inserir imagem)*
> * **Detecção com Bounding Boxes (`capturas/anotadas/`):** *(Inserir imagem)*

---

## 📦 Tecnologias e Bibliotecas Utilizadas
* **Flutter / Dart:** `image_picker`, `dart:io` (Sockets TCP), Material Design 3.
* **Python 3:** `socket`, `struct`, `ultralytics` (YOLOv8n / YOLO11n), `opencv-python`, `numpy`.
