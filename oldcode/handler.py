import time
import json

async def handle_request(request):
    key = request["cookies"].get("key", None)

    # show header order and http rtt
    if request["method"] == "GET" and request["uri"] == "/":
        if key and key.strip() != "" and key.strip() != "None" and key.isdigit():
            return "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nSet-Cookie: key=\r\n\r\n<html><body><h1>"+request["raw_headerorder"]+ " - "+(str((time.time_ns()-(int(key)))/1e6))+"</h1></body></html>"
        else:
            return "HTTP/1.1 307 Temporary Redirect\r\nLocation: /\r\nCache-Control: no-store, no-cache, must-revalidate, max-age=0\r\nContent-Type: text/html\r\nSet-Cookie: key="+str(time.time_ns())+"\r\n\r\n<html><body><h1>Hiii</h1></body></html>"

    # file serving
    elif request["method"] == "GET" and request["uri"] == "/test.html":
        readfile = open("test.html", "rb")
        return "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n" + readfile.read().decode("utf-8")

    # play with response codes
    elif request["method"] == "GET" and request["uri"][1:].split("/")[0].isdigit() and len(request["uri"][1:].split("/")) <= 2:
        if len(request["uri"][1:].split("/")) == 1:
            return "HTTP/1.1 " + request["uri"][1:] + " H I\r\nContent-Type: text/html\r\n\r\n<html><body><h1>Hiiiii!</h1></body></html>"
        else:
            return "HTTP/1.1 " + request["uri"][1:].split("/")[0] + " " + request["uri"][1:].split("/")[1] + "\r\nContent-Type: text/html\r\n\r\n<html><body><h1>Hiiiii!</h1></body></html>"

    # req.json
    elif request["method"] == "GET" and request["uri"] == "/req.json":
        return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" + json.dumps(request)

    # everything else
    else:
        return "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\n\r\n<html><body><h1>404 Not Found</h1></body></html>"