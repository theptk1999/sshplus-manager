#!/usr/bin/env python3
# ==================================================
# SSHPlus WebSocket Proxy v2.0
# Why: รองรับ 3 โหมด: Raw TCP, HTTP Upgrade, WebSocket (RFC 6455)
#      พร้อม graceful shutdown, stats, และ logging ที่ดี
# ==================================================

import socket
import threading
import select
import signal
import sys
import os
import time
import struct
import hashlib
import base64
import logging
from typing import Optional, Tuple

# ==================================================
# Configuration
# ==================================================
BIND_ADDR = "0.0.0.0"
SSH_ADDR = "127.0.0.1"
BUFFER_SIZE = 8192
IDLE_TIMEOUT = 300
MAX_CONNECTIONS = 1000
WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# ==================================================
# Logging
# ==================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("ws-proxy")

# ==================================================
# Connection Statistics
# Why: ติดตามจำนวน connection เพื่อ debug และ monitor
# ==================================================
class Stats:
    def __init__(self):
        self._lock = threading.Lock()
        self.active = 0
        self.total = 0
        self.rejected = 0
        self.start_time = time.time()

    def connect(self):
        with self._lock:
            self.active += 1
            self.total += 1

    def disconnect(self):
        with self._lock:
            self.active = max(0, self.active - 1)

    def reject(self):
        with self._lock:
            self.rejected += 1

    def summary(self) -> str:
        with self._lock:
            uptime = int(time.time() - self.start_time)
            h, m = divmod(uptime, 3600)
            m //= 60
            return (
                f"uptime={h}h{m}m "
                f"active={self.active} "
                f"total={self.total} "
                f"rejected={self.rejected}"
            )

stats = Stats()

# ==================================================
# Graceful Shutdown
# Why: รับ SIGTERM/SIGINT แล้วปิด server อย่างสุภาพ
#      ไม่ทิ้ง connection ค้าง
# ==================================================
shutdown_event = threading.Event()

def signal_handler(signum, frame):
    sig_name = signal.Signals(signum).name
    logger.info(f"Received {sig_name}, shutting down gracefully...")
    logger.info(f"Final stats: {stats.summary()}")
    shutdown_event.set()

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

# ==================================================
# Socket Helpers
# ==================================================
def close_socket(sock: socket.socket) -> None:
    # Why: shutdown ก่อน close เพื่อ flush buffer ค้าง
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    finally:
        try:
            sock.close()
        except OSError:
            pass

def set_keepalive(sock: socket.socket) -> None:
    # Why: เปิด TCP keepalive เพื่อตรวจจับ connection ที่ตายเงียบ
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        # Linux-specific: probe ทุก 60 วินาที
        if hasattr(socket, "TCP_KEEPIDLE"):
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 60)
        if hasattr(socket, "TCP_KEEPINTVL"):
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)
        if hasattr(socket, "TCP_KEEPCNT"):
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)
    except OSError:
        pass

# ==================================================
# WebSocket Frame Parser (RFC 6455)
# Why: parse WebSocket frame จาก client ที่ใช้ ws transport จริง
#      เช่น v2rayNG, Nekobox, WebSocket SSH client
# ==================================================
def ws_accept_key(key: str) -> str:
    # Why: คำนวณ Sec-WebSocket-Accept ตาม RFC 6455 section 4.2.2
    digest = hashlib.sha1((key.strip() + WS_MAGIC).encode()).digest()
    return base64.b64encode(digest).decode()

def parse_http_headers(data: bytes) -> dict:
    # Why: แปลง HTTP request headers เป็น dict สำหรับตรวจ WebSocket upgrade
    headers = {}
    try:
        text = data.decode("utf-8", errors="ignore")
        for line in text.split("\r\n")[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
    except Exception:
        pass
    return headers

def read_ws_frame(sock: socket.socket) -> Optional[Tuple[int, bytes, bool]]:
    # Why: อ่าน WebSocket frame 1 frame จาก socket
    #      return (opcode, payload, fin) หรือ None ถ้า connection ปิด
    try:
        header = _recv_exact(sock, 2)
        if header is None:
            return None

        fin = bool(header[0] & 0x80)
        opcode = header[0] & 0x0F
        masked = bool(header[1] & 0x80)
        length = header[1] & 0x7F

        if length == 126:
            raw = _recv_exact(sock, 2)
            if raw is None:
                return None
            length = struct.unpack("!H", raw)[0]
        elif length == 127:
            raw = _recv_exact(sock, 8)
            if raw is None:
                return None
            length = struct.unpack("!Q", raw)[0]

        # Why: ป้องกัน memory bomb จาก frame ขนาดใหญ่ผิดปกติ
        if length > 10 * 1024 * 1024:
            logger.warning(f"WS frame too large: {length} bytes, dropping")
            return None

        mask_key = b""
        if masked:
            mask_key = _recv_exact(sock, 4)
            if mask_key is None:
                return None

        payload = b""
        if length > 0:
            payload = _recv_exact(sock, length)
            if payload is None:
                return None

        if masked and mask_key:
            payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))

        return opcode, payload, fin

    except (OSError, struct.error):
        return None

def build_ws_frame(opcode: int, payload: bytes) -> bytes:
    # Why: สร้าง WebSocket frame สำหรับส่งกลับ client (server ไม่ mask)
    frame = bytearray()
    frame.append(0x80 | opcode)

    length = len(payload)
    if length < 126:
        frame.append(length)
    elif length < 65536:
        frame.append(126)
        frame.extend(struct.pack("!H", length))
    else:
        frame.append(127)
        frame.extend(struct.pack("!Q", length))

    frame.extend(payload)
    return bytes(frame)

def _recv_exact(sock: socket.socket, n: int) -> Optional[bytes]:
    # Why: อ่านข้อมูลให้ครบ n bytes แน่นอน
    data = bytearray()
    while len(data) < n:
        try:
            chunk = sock.recv(n - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        except OSError:
            return None
    return bytes(data)

# ==================================================
# Proxy Modes
# ==================================================
def raw_tcp_relay(client: socket.socket, target: socket.socket) -> None:
    # Why: forward ข้อมูล TCP ตรงๆ ระหว่าง client กับ SSH server
    #      ใช้สำหรับ client ที่ส่ง SSH banner ตรงๆ หรือหลัง HTTP upgrade
    try:
        while not shutdown_event.is_set():
            r, _, _ = select.select([client, target], [], [], 5)
            if not r:
                continue

            if client in r:
                data = client.recv(BUFFER_SIZE)
                if not data:
                    break
                target.sendall(data)

            if target in r:
                data = target.recv(BUFFER_SIZE)
                if not data:
                    break
                client.sendall(data)
    except OSError:
        pass

def ws_frame_relay(client: socket.socket, target: socket.socket) -> None:
    # Why: แปลง WebSocket frame <-> raw TCP
    #      client ส่ง WS binary frame → proxy extract payload → ส่งไป SSH
    #      SSH ตอบ raw data → proxy wrap เป็น WS binary frame → ส่งกลับ client
    try:
        while not shutdown_event.is_set():
            # Why: อ่าน WS frame จาก client
            r, _, _ = select.select([client, target], [], [], 5)
            if not r:
                continue

            if client in r:
                result = read_ws_frame(client)
                if result is None:
                    break

                opcode, payload, fin = result

                # Why: จัดการ control frames ตาม RFC 6455
                if opcode == 0x8:  # Close
                    close_frame = build_ws_frame(0x8, payload[:2] if len(payload) >= 2 else b"")
                    client.sendall(close_frame)
                    break
                elif opcode == 0x9:  # Ping
                    pong = build_ws_frame(0xA, payload)
                    client.sendall(pong)
                    continue
                elif opcode == 0xA:  # Pong
                    continue
                elif opcode in (0x1, 0x2, 0x0):  # Text, Binary, Continuation
                    if payload:
                        target.sendall(payload)
                else:
                    logger.debug(f"Unknown WS opcode: {opcode}")
                    break

            # Why: อ่าน raw data จาก SSH แล้ว wrap เป็น WS binary frame
            if target in r:
                data = target.recv(BUFFER_SIZE)
                if not data:
                    break
                ws_frame = build_ws_frame(0x2, data)
                client.sendall(ws_frame)

    except OSError:
        pass

# ==================================================
# Connection Handler
# ==================================================
def handler(client_socket: socket.socket, client_addr, ssh_port: int) -> None:
    # Why: จัดการแต่ละ connection แยก thread
    #      ตรวจจับโหมดอัตโนมัติ: Raw TCP / HTTP Upgrade / WebSocket
    stats.connect()
    peer = f"{client_addr[0]}:{client_addr[1]}"

    try:
        set_keepalive(client_socket)

        # Why: เชื่อมต่อไป SSH server ก่อน
        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        set_keepalive(target_socket)
        target_socket.settimeout(10)
        target_socket.connect((SSH_ADDR, ssh_port))
        target_socket.settimeout(None)

        # Why: อ่าน payload แรกจาก client เพื่อตรวจจับโหมด
        client_socket.settimeout(15)
        first_payload = client_socket.recv(BUFFER_SIZE)
        client_socket.settimeout(None)

        if not first_payload:
            return

        # Why: ตรวจว่าเป็น HTTP request หรือไม่
        header_text = first_payload.decode("utf-8", errors="ignore")
        is_http = (
            header_text.startswith("GET ")
            or header_text.startswith("POST ")
            or header_text.startswith("CONNECT ")
            or header_text.startswith("HEAD ")
            or "HTTP/1." in header_text.split("\r\n")[0]
        )

        if is_http:
            headers = parse_http_headers(first_payload)
            ws_key = headers.get("sec-websocket-key", "")
            upgrade = headers.get("upgrade", "").lower()

            if "websocket" in upgrade and ws_key:
                # ===== Mode 3: WebSocket (RFC 6455) =====
                # Why: ทำ handshake จริงพร้อม Sec-WebSocket-Accept
                accept = ws_accept_key(ws_key)
                ws_handshake = (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {accept}\r\n"
                    "\r\n"
                )
                client_socket.sendall(ws_handshake.encode("utf-8"))
                logger.info(f"[WS] {peer} -> SSH:{ssh_port} (WebSocket mode)")
                ws_frame_relay(client_socket, target_socket)
            else:
                # ===== Mode 2: HTTP Upgrade (legacy) =====
                # Why: รองรับ client เก่าที่ส่ง HTTP request แต่ไม่ใช้ WS frame
                #      เช่น HTTP Injector, HTTP Custom
                http_response = (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    "\r\n"
                )
                client_socket.sendall(http_response.encode("utf-8"))
                logger.info(f"[HTTP] {peer} -> SSH:{ssh_port} (HTTP upgrade mode)")
                raw_tcp_relay(client_socket, target_socket)
        else:
            # ===== Mode 1: Raw TCP =====
            # Why: client ส่ง SSH banner ตรงๆ โดยไม่มี HTTP header
            #      เช่น PuTTY, Termius, ssh command
            logger.info(f"[RAW] {peer} -> SSH:{ssh_port} (raw TCP mode)")
            target_socket.sendall(first_payload)
            raw_tcp_relay(client_socket, target_socket)

    except ConnectionRefusedError:
        logger.error(f"[{peer}] SSH server refused connection on port {ssh_port}")
    except socket.timeout:
        logger.warning(f"[{peer}] Connection timeout")
    except OSError as exc:
        logger.debug(f"[{peer}] Connection error: {exc}")
    except Exception as exc:
        logger.error(f"[{peer}] Unexpected error: {exc}")
    finally:
        close_socket(client_socket)
        try:
            close_socket(target_socket)
        except Exception:
            pass
        stats.disconnect()

# ==================================================
# Stats Reporter
# Why: แสดง stats ทุก 5 นาที เพื่อ monitor ว่า proxy ทำงานปกติ
# ==================================================
def stats_reporter():
    while not shutdown_event.is_set():
        shutdown_event.wait(300)
        if not shutdown_event.is_set():
            logger.info(f"[STATS] {stats.summary()}")

# ==================================================
# Server
# ==================================================
def server(listen_port: int, ssh_port: int) -> None:
    # Why: สร้าง server socket พร้อม SO_REUSEADDR
    #      ใช้ semaphore จำกัด concurrent connections
    semaphore = threading.BoundedSemaphore(MAX_CONNECTIONS)

    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.settimeout(2)

    try:
        server_socket.bind((BIND_ADDR, listen_port))
    except OSError as exc:
        logger.critical(f"Cannot bind to port {listen_port}: {exc}")
        sys.exit(1)

    server_socket.listen(1024)
    logger.info(f"SSHPlus WS Proxy v2.0 started")
    logger.info(f"Listening: {BIND_ADDR}:{listen_port} -> SSH {SSH_ADDR}:{ssh_port}")
    logger.info(f"Modes: Raw TCP | HTTP Upgrade | WebSocket (RFC 6455)")
    logger.info(f"Max connections: {MAX_CONNECTIONS}")

    # Why: เริ่ม stats reporter thread
    stats_thread = threading.Thread(target=stats_reporter, daemon=True)
    stats_thread.start()

    while not shutdown_event.is_set():
        try:
            client_socket, client_addr = server_socket.accept()
        except socket.timeout:
            continue
        except OSError:
            if shutdown_event.is_set():
                break
            logger.error("Accept error")
            continue

        # Why: จำกัด concurrent connections ด้วย semaphore
        acquired = semaphore.acquire(blocking=False)
        if not acquired:
            stats.reject()
            logger.warning(f"Max connections reached, rejecting {client_addr[0]}")
            close_socket(client_socket)
            continue

        def wrapped_handler(cs=client_socket, ca=client_addr):
            try:
                handler(cs, ca, ssh_port)
            finally:
                semaphore.release()

        t = threading.Thread(target=wrapped_handler, daemon=True)
        t.start()

    # Why: graceful shutdown - ปิด server socket
    logger.info("Shutting down server socket...")
    close_socket(server_socket)
    logger.info(f"Server stopped. Final stats: {stats.summary()}")

# ==================================================
# Entry Point
# ==================================================
if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: proxy_ws.py <Listen Port> <SSH Port>")
        print("Example: proxy_ws.py 80 22")
        sys.exit(1)

    try:
        p_listen = int(sys.argv[1])
        p_ssh = int(sys.argv[2])
    except ValueError:
        logger.critical("Ports must be integers.")
        sys.exit(1)

    if not (1 <= p_listen <= 65535) or not (1 <= p_ssh <= 65535):
        logger.critical("Ports must be between 1 and 65535.")
        sys.exit(1)

    server(p_listen, p_ssh)