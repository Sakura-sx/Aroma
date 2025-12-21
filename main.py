import socket
import time

server_socket = socket.create_server(("0.0.0.0", 8080))

while True:
    try:
        client_socket, client_address = server_socket.accept()
        print(f"\nNew connection from {client_address}")
        
        request = client_socket.recv(1024)
        request = request.decode("utf-8")
        firstline = request.split("\r\n")[0]
        method, uri, protocol = firstline.strip().split(" ")
        headers = request.split("\r\n")[1:-2]
        sorted_headers = sorted(headers)
        headerorder = ""
        cookies = False
        # header index in the sorted headers
        for header in headers:
            print(header)
            print(sorted_headers.index(header))
            headerorder += f"{str(sorted_headers.index(header))}-"
            if "Cookie" in header:
                cookies = header.split("Cookie: ")[1]
                print(cookies)

        print(headerorder)

        key = ""

        if cookies:
            cookies = cookies.split("; ")
            for cookie in cookies:
                cookie = cookie.split("=")
                if cookie[0] == "key":
                    key = cookie[1]
        
        print(key)

        if method == "GET" and uri == "/":
            if key.strip() != "" and key.strip() != "None" and key.isdigit():
                client_socket.send(b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nSet-Cookie: key=\r\n\r\n<html><body><h1>"+headerorder.encode("utf-8")+b" - "+(str((time.time_ns()-(int(key)))/1e6)).encode("utf-8")+b"</h1></body></html>")
            else:
                client_socket.send(b"HTTP/1.1 307 Temporary Redirect\r\nLocation: /\r\nCache-Control: no-store, no-cache, must-revalidate, max-age=0\r\nContent-Type: text/html\r\nSet-Cookie: key="+str(time.time_ns()).encode("utf-8")+b"\r\n\r\n<html><body><h1>Hiii</h1></body></html>")
            client_socket.close()
        elif method == "GET" and len(uri) == 4:
            client_socket.send(b"HTTP/1.1 " + uri[1:].encode("utf-8") + b" HI\r\nContent-Type: text/html\r\n\r\n<html><body><h1>Hiiiii!</h1></body></html>")
    except Exception as e:
        print(e)
        client_socket.close()
        continue
