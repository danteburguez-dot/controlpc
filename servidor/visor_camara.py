# visor_camara.py — muestra la cámara del teléfono en una ventana en la PC
# Lee JPEG frames desde 127.0.0.1:8570 (servidor Control PC)
import socket
import struct
import io
import tkinter as tk
from PIL import Image, ImageTk

root = tk.Tk()
root.title("Control PC — cámaro del teléfono")
root.configure(bg="#05070c")
etiqueta = tk.Label(root, bg="#05070c")
etiqueta.pack(fill="both", expand=True)
estado = tk.Label(root, text="esperando frames...", fg="#8b93a7", bg="#05070c", font=("Segoe UI", 10))
estado.pack(fill="x", pady=2)

sock = socket.create_connection(("127.0.0.1", 8570))
sock.settimeout(6)

def bucle():
    try:
        cabecera = sock.recv(4)
        if len(cabecera) < 4:
            estado.config(text="cámara cerrada")
            sock.close()
            return
        tam = struct.unpack(">I", cabecera)[0]
        jpg = b""
        while len(jpg) < tam:
            trozo = sock.recv(65536)
            if not trozo:
                estado.config(text="cerrado")
                sock.close()
                return
            jpg += trozo
        img = Image.open(io.BytesIO(jpg))
        foto = ImageTk.PhotoImage(img)
        etiqueta.config(image=foto)
        etiqueta.image = foto
        estado.config(text="cámara activa ✓ (cerrar prosecutor: cierra esta ventana)")
    except socket.timeout:
        estado.config(text="sin señal de cámara...")
    except Exception as e:
        try:
            estado.config(text="sin señal: " + str(e)[:60])
            sock.close()
        except Exception:
            pass
        return
    root.after(40, bucle)

bucle()
root.mainloop()
