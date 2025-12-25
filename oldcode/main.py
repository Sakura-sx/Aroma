import asyncio
from handler import handle_request

async def handle_client(reader, writer):
    client_address = writer.get_extra_info("peername")
    print(f"\nNew connection from {client_address}")

    try:
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

        raw_request = await reader.read(1024)
        if not raw_request:
            return

        raw_request = raw_request.decode("utf-8")
        firstline = raw_request.split("\r\n")[0]
        print(firstline)
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

        response = await handle_request(request)
        writer.write(response.encode("utf-8"))
        await writer.drain()

    except Exception as e:
        print(f"Error: {e}")
    finally:
        writer.close()
        await writer.wait_closed()


async def main():
    server = await asyncio.start_server(handle_client, "0.0.0.0", 8080)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())