import socket
import time
from handler import handle_request

server_socket = socket.create_server(("0.0.0.0", 8080))

while True:
    try:
        client_socket, client_address = server_socket.accept()
        print(f"\nNew connection from {client_address}")

        request = {
            "method": "",
            "uri": "/",
            "protocol": "HTTP/1.1",
            "headers": [],
            "sorted_headers": [],
            "raw_headerorder": "",
            "headerorder_nocookies": "",
            "basic_headerorder": "",
            "cookies": dict(),
        }

        raw_request = client_socket.recv(1024)
        raw_request = raw_request.decode("utf-8")
        firstline = raw_request.split("\r\n")[0]
        request["method"], request["uri"], request["protocol"] = firstline.strip().split(" ")
        request["headers"] = raw_request.split("\r\n")[1:-2]
        request["sorted_headers"] = sorted(request["headers"])
        request["raw_headerorder"] = ""
        request["headerorder_nocookies"] = ""
        # header index in the sorted headers
        for header in request["headers"]:

            request["raw_headerorder"] += f"{str(request["sorted_headers"].index(header))}-"
            if "Cookie" in header:
                cookies = header.split("Cookie: ")[1]
                cookies = cookies.split("; ")
                for cookie in cookies:
                    cookie = cookie.split("=")
                    request["cookies"][cookie[0].strip()] = cookie[1].strip()
            else:
                request["headerorder_nocookies"] += f"{str(request["sorted_headers"].index(header))}-"

        request["raw_headerorder"] = request["raw_headerorder"][:-1]
        request["headerorder_nocookies"] = request["headerorder_nocookies"][:-1]

        client_socket.send(handle_request(request).encode("utf-8"))
        client_socket.close()
    except Exception as e:
        print(e)
        client_socket.close()
        continue
