## Message Structure

octoque processing the incoming message in 2 steps.

1. Client send command to queue server to notify about upcoming action (whether is a `get` or `put` action)

2. Server validate command, do necessary checks and open up client to send in message.

For example:
```
## put one message to default topic with batch transfer mode
OTQ PUT default 1 BATCH (step 1)
    |
    |
    V
## server check whether user has access to queue topic
    |
    |
    V
## server check whether user has required role to access the queue topic
    |
    |
    V
## server check for queue / queue topic state is available to put / get message (work in progress)
    |
    |
    V
## passed all check, server response "PROCEED" to client to continue its action
    |
    |
    V
## message data sending over to default topic
"hello world!" (step 2)
    |
    |
    V
## ENDOFRESP, when operation is done
```


`protocol`, used to identify different protocol message structure, for now, there is only the default `otq` protocol is supported..

`command`, command send to queue server for different operations.

    GET         ## get message from queue topic
    PUT         ## put message into queue topic
    PUTACK      ## put message into queue topic and return whether success or fail
    PUBLISH     ## put message into multiple queue topic (work in progress)
    SUBSCRIBE   ## subscribe for new message from queue topic
    UNSUBSCRIBE ## unsubscribe from current subscription
    PING        ## check for queue topic existence
    CLEAR       ## clear data and reset queue topic
    NEW         ## create new queue topic with different connection type (BROKER, PUBSUB)
    DISPLAY     ## display the state of queue topic
    CONNECT     ## connect to queue server and acquire a connection
    DISCONNECT  ## disconnect from current queue server and release the connection
    ACKNOWLEDGE ## being sent from queue server to acknowledge action (work in progress)

`topic`, queue topic name inside queue server

`transferMethod`, way of transferring message data, available options:

  - BATCH, message send in batch mode, this mode allow user to send multiple messages in one command.

  - STREAM, message being streaming over connection, only one message at one time (work in prograss).


`payloadRows`, number of payload being send in current reqeust, row is being delimited by next line "`\n`", default value is 1.

`numberOfMsg`, number of messages being retrieve from queue, default value is 1.\

`topicSize`, queue topic capacity, used to define the number of message able to store in one queue topic.

`connectionType`, queue topic connection type, available options:

  - BROKER, queue topic that has features like, message validation, transformation, shcema-driven and routing. 

  - PUBSUB, queue topic that is available for pubsub connection.

`lifespan`, message life span, remove after defined time limit (work in progress)

`numberofThread`, number of thread will be spawn to listenning for new conenction for each queue topic.

`username`, username used by `CONNECT` command to acquire connection.

`password`, password used by `CONNECT` command to acquire connection.


Find out more on [message commands](./message-command.md) for available commands.