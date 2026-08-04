#!/usr/bin/env python3
# proxyssh.py —— 通过本地 HTTP 代理(127.0.0.1:10808)建立 CONNECT 隧道，供 ssh ProxyCommand 使用
# 用法: ssh -o ProxyCommand="python3 proxyssh.py %h %p" ...
import sys, os, socket, threading

def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: proxyssh.py <host> <port>\n")
        sys.exit(2)
    host, port = sys.argv[1], int(sys.argv[2])
    PROXY_HOST, PROXY_PORT = "127.0.0.1", 10808

    s = socket.create_connection((PROXY_HOST, PROXY_PORT), timeout=15)
    s.sendall(f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = s.recv(4096)
        if not chunk:
            sys.stderr.write("proxy closed early\n")
            sys.exit(1)
        resp += chunk
    status = resp.split(b"\r\n")[0]
    if b" 200 " not in status:
        sys.stderr.write("proxy CONNECT failed: %s\n" % status.decode(errors="replace"))
        sys.exit(1)

    def pipe_stdin_to_sock():
        try:
            while True:
                data = os.read(0, 65536)
                if not data:
                    break
                s.sendall(data)
        except Exception:
            pass
        finally:
            try:
                s.shutdown(socket.SHUT_WR)
            except Exception:
                pass

    threading.Thread(target=pipe_stdin_to_sock, daemon=True).start()

    try:
        while True:
            data = s.recv(65536)
            if not data:
                break
            os.write(1, data)
    except Exception:
        pass
    finally:
        s.close()

if __name__ == "__main__":
    main()
