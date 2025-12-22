import time

def handle_request(request):
    key = request["cookies"].get("key", None)

    if request["method"] == "GET" and request["uri"] == "/":
        if key and key.strip() != "" and key.strip() != "None" and key.isdigit():
            return "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nSet-Cookie: key=\r\n\r\n<html><body><h1>"+request["raw_headerorder"]+ " - "+(str((time.time_ns()-(int(key)))/1e6))+"</h1></body></html>"
        else:
            return "HTTP/1.1 307 Temporary Redirect\r\nLocation: /\r\nCache-Control: no-store, no-cache, must-revalidate, max-age=0\r\nContent-Type: text/html\r\nSet-Cookie: key="+str(time.time_ns())+"\r\n\r\n<html><body><h1>Hiii</h1></body></html>"

    elif request["method"] == "GET" and request["uri"] == "/test.html":
        readfile = open("test.html", "rb")
        return "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n" + readfile.read().decode("utf-8")

    elif request["method"] == "GET" and len(request["uri"]) == 4:
        return "HTTP/1.1 " + request["uri"][1:] + " HI\r\nContent-Type: text/html\r\n\r\n<html><body><h1>Hiiiii!</h1></body></html>"

    else:
        return "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\n\r\n<html><body><h1>404 Not Found</h1></body></html>"