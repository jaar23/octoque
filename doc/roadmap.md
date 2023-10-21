## Roadmap

###  version 0.1.0 (current)

- octoque running in detach mode

- octoque running with console logging or file logging

- octoque command
    ```
    GET
    PUT
    PUTACK
    PUBLISH
    SUBSCRIBE
    UNSUBSCRIBE
    PING
    CLEAR
    NEW
    DISPLAY
    CONNECT
    DISCONNECT
    ACKNOWLEDGE
    ```
- pubsub support on topic level, publish and subscribe on single topic

- standardize request format. response is return as it is

- REPL mode, allow user to run command to interact with octoque.

- batch delivery of message.

- authenticate user via file-based authentication. admin user is default created, user can add more user by using `octoque adm create` command.

- octoque able to run in low end hardware, for example 1 cpu 256 MB RAM.

- octoque able to handle multiple connection, the data that storing in queue depends on the available memory on the system.

- in-memory store.

- client library to be used for develop application with octoque (work in progress).


### version 0.2.0 (future)

- message properties to handle extra header, such as lifespan of message, service level, etc.

- state of queue

- state of qtopic

- check state of queue and qtopio before proceed 

- octoque start with file config

- schema based qtopic

### version 0.3.0 (future)

- PUBLISH support put message to multiple qtopic

- SUBSCRIBE support to consume message from multiple qtopic

- streaming on payload message (such as file based data / large data type)

- streaming of output message

### version 0.3.5 (future)

- COMMIT command to persist message to disk

- persistent storage of message

### version 0.4.0 (future)

- monitoring of queue server

- monitoring of qtopic

- replay of message flow based on log / event