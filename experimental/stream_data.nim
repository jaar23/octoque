import std/net, threadpool

proc execute(client: Socket): void {.thread.} =
  var recvLine = client.recvLine()
  echo "----------------------------------------"
  echo recvLine  
  echo "----------------------------------------"



proc start* (): void =
  let socket = newSocket()
  socket.bindAddr(Port(6789))
  socket.listen()

  var address = "127.0.0.1"
  while true:
    var client: Socket
    socket.acceptAddr(client, address)
    echo "Cliented connected from: ", address
    spawn execute(client)
    #let recvData = client.recvLine()
    #var recvdata = client.recv(1024)
    #echo "received: \n", recvData

  socket.close()


start()


