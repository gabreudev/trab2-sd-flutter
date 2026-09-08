#!/usr/bin/env python3
"""
Servidor TCP para Recepção de Imagens e Detecção de Objetos com YOLO
Atividade 2 - Foto via Botão (Android -> Servidor Python por Sockets)

Protocolo:
  - Cliente envia 4 bytes (uint32 Big-Endian) com o tamanho N da imagem JPEG.
  - Cliente envia N bytes contendo os dados brutos da foto em JPEG.
  - Servidor salva a imagem em 'capturas/' com timestamp.
  - Servidor realiza a inferência com modelo YOLO (YOLOv8n / YOLO11n).
  - Servidor salva imagem anotada (com bounding boxes) para evidência.
  - Servidor responde via socket TCP com a lista de objetos identificados:
      Exemplo:
        Pessoa detectada
        Cadeira detectada
        Mochila detectada
      Ou caso nenhum objeto seja detectado:
        Nada Detectado
"""

import os
import socket
import struct
from datetime import datetime
import cv2
import numpy as np
from ultralytics import YOLO

# Dicionário de tradução das classes COCO mais comuns para o Português
CLASS_TRANSLATIONS = {
    'person': 'Pessoa detectada',
    'bicycle': 'Bicicleta detectada',
    'car': 'Carro detectado',
    'motorcycle': 'Motocicleta detectada',
    'airplane': 'Avião detectado',
    'bus': 'Ônibus detectado',
    'train': 'Trem detectado',
    'truck': 'Caminhão detectado',
    'boat': 'Barco detectado',
    'traffic light': 'Semáforo detectado',
    'fire hydrant': 'Hidrante detectado',
    'stop sign': 'Placa de Pare detectada',
    'bench': 'Banco detectado',
    'bird': 'Pássaro detectado',
    'cat': 'Gato detectado',
    'dog': 'Cachorro detectado',
    'horse': 'Cavalo detectado',
    'sheep': 'Ovelha detectada',
    'cow': 'Vaca detectada',
    'elephant': 'Elefante detectado',
    'bear': 'Urso detectado',
    'zebra': 'Zebra detectada',
    'giraffe': 'Girafa detectada',
    'backpack': 'Mochila detectada',
    'umbrella': 'Guarda-chuva detectado',
    'handbag': 'Bolsa detectada',
    'tie': 'Gravata detectada',
    'suitcase': 'Mala detectada',
    'frisbee': 'Frisbee detectado',
    'skis': 'Esqui detectado',
    'snowboard': 'Snowboard detectado',
    'sports ball': 'Bola detectada',
    'kite': 'Pipa detectada',
    'baseball bat': 'Taco de beisebol detectado',
    'baseball glove': 'Luva de beisebol detectada',
    'skateboard': 'Skate detectado',
    'surfboard': 'Prancha de surfe detectada',
    'tennis racket': 'Raquete de tênis detectada',
    'bottle': 'Garrafa detectada',
    'wine glass': 'Taça detectada',
    'cup': 'Copo/Xícara detectada',
    'fork': 'Garfo detectado',
    'knife': 'Faca detectada',
    'spoon': 'Colher detectada',
    'bowl': 'Tigela detectada',
    'banana': 'Banana detectada',
    'apple': 'Maçã detectada',
    'sandwich': 'Sanduíche detectado',
    'orange': 'Laranja detectada',
    'broccoli': 'Brócolis detectado',
    'carrot': 'Cenoura detectada',
    'hot dog': 'Cachorro-quente detectado',
    'pizza': 'Pizza detectada',
    'donut': 'Donut detectado',
    'cake': 'Bolo detectado',
    'chair': 'Cadeira detectada',
    'couch': 'Sofá detectado',
    'potted plant': 'Vaso de planta detectado',
    'bed': 'Cama detectada',
    'dining table': 'Mesa de jantar detectada',
    'toilet': 'Vaso sanitário detectado',
    'tv': 'Televisão detectada',
    'laptop': 'Notebook/Laptop detectado',
    'mouse': 'Mouse detectado',
    'remote': 'Controle remoto detectado',
    'keyboard': 'Teclado detectado',
    'cell phone': 'Celular detectado',
    'microwave': 'Micro-ondas detectado',
    'oven': 'Forno detectado',
    'toaster': 'Torradeira detectada',
    'sink': 'Pia detectada',
    'refrigerator': 'Geladeira detectada',
    'book': 'Livro detectado',
    'clock': 'Relógio detectado',
    'vase': 'Vaso detectado',
    'scissors': 'Tesoura detectada',
    'teddy bear': 'Urso de pelúcia detectado',
    'hair drier': 'Secador de cabelo detectado',
    'toothbrush': 'Escova de dentes detectada'
}

def get_local_ip():
    """Descobre o endereço IP desta máquina na rede local."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def recv_exact(sock, num_bytes):
    """Recebe exatamente 'num_bytes' do socket ou retorna None se a conexão fechar."""
    buffer = bytearray()
    while len(buffer) < num_bytes:
        chunk = sock.recv(min(4096, num_bytes - len(buffer)))
        if not chunk:
            return None
        buffer.extend(chunk)
    return bytes(buffer)

def main():
    HOST = '0.0.0.0'
    PORT = 5000

    # Cria diretórios para salvar evidências e capturas
    os.makedirs('capturas', exist_ok=True)
    os.makedirs('capturas/anotadas', exist_ok=True)

    print("=" * 60)
    print(" Carregando modelo YOLO (recomendado pelo trabalho)...")
    # Carrega modelo YOLOv8n (ou yolo11n se preferir)
    model = YOLO("yolov8n.pt")
    print(" Modelo carregado com sucesso!")
    print("=" * 60)

    local_ip = get_local_ip()

    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind((HOST, PORT))
    server_socket.listen(5)

    print(f"\n============================================================")
    print(f" Servidor TCP iniciado e escutando na porta: {PORT}")
    print(f" IP na Rede Local: {local_ip}")
    print(f" -> No App Flutter, configure na engrenagem:")
    print(f"    IP:    {local_ip}")
    print(f"    Porta: {PORT}")
    print(f"============================================================")

    while True:
        print("\nAguardando imagem...")
        try:
            client_socket, client_addr = server_socket.accept()
            print(f"[CONEXÃO] Cliente conectado: {client_addr[0]}:{client_addr[1]}")

            # 1. Lê cabeçalho de 4 bytes contendo o tamanho da imagem (Big-Endian uint32)
            header = recv_exact(client_socket, 4)
            if not header or len(header) < 4:
                print("[AVISO] Conexão de teste ou cabeçalho incompleto recebido.")
                client_socket.close()
                continue

            image_size = struct.unpack('>I', header)[0]
            print(f"[REDE] Tamanho da imagem recebida: {image_size} bytes ({image_size / 1024:.1f} KB)")

            # 2. Lê os bytes da imagem
            image_bytes = recv_exact(client_socket, image_size)
            if not image_bytes or len(image_bytes) < image_size:
                print("[ERRO] Falha ao receber o fluxo completo de bytes da imagem.")
                client_socket.close()
                continue

            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            raw_image_path = os.path.join("capturas", f"captura_{timestamp}.jpg")

            # 3. Salva a imagem recebida com timestamp
            with open(raw_image_path, "wb") as f:
                f.write(image_bytes)
            print(f"[SALVO] Imagem salva em: {raw_image_path}")

            # 4. Decodifica com OpenCV
            np_arr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if img is None:
                print("[ERRO] Erro ao decodificar imagem JPEG via OpenCV.")
                response = "Nada Detectado\n"
            else:
                # 5. Executa inferência com YOLO
                results = model(img, conf=0.35, verbose=False)

                detected_classes = set()
                annotated_img = img.copy()

                for result in results:
                    annotated_img = result.plot()
                    for box in result.boxes:
                        class_id = int(box.cls[0].item())
                        class_name = model.names.get(class_id, "objeto")
                        
                        # Traduz a classe para o padrão exigido
                        translated = CLASS_TRANSLATIONS.get(
                            class_name.lower(),
                            f"{class_name.capitalize()} detectado(a)"
                        )
                        detected_classes.add(translated)

                # Salva a imagem com bounding boxes anotados para o README / Relatório
                annotated_image_path = os.path.join("capturas", "anotadas", f"detectado_{timestamp}.jpg")
                cv2.imwrite(annotated_image_path, annotated_img)
                print(f"[SALVO] Imagem com detecções anotadas salva em: {annotated_image_path}")

                # 6. Formata a resposta para o aplicativo
                if detected_classes:
                    response_items = sorted(list(detected_classes))
                    response = "\n".join(response_items)
                    print(f"[DETECÇÃO] Objetos identificados:\n  - " + "\n  - ".join(response_items))
                else:
                    response = "Nada Detectado"
                    print("[DETECÇÃO] Nenhum objeto com confiança suficiente: Nada Detectado")

            # 7. Retorna a resposta para o aplicativo via socket TCP
            client_socket.sendall(response.encode('utf-8'))
            print("[RESPOSTA] Resultado enviado com sucesso ao aplicativo!")

            client_socket.close()

        except KeyboardInterrupt:
            print("\nEncerrando servidor TCP...")
            break
        except Exception as e:
            print(f"[ERRO] Ocorreu uma exceção: {e}")

    server_socket.close()

if __name__ == "__main__":
    main()
