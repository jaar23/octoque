# octoque

*Note* Threadpool is deprecated, the project is in the middle of migrating to use different thread lib.

*Note*  queue message persistent strategy is unsafe for now.
---

octoque is a simple message queue server implemented in nim. The initiative of creating octoque is, learn by doing, a lot of the features implemented here might not be the best approach but it should be usable. It works similar to redis, but acting more towards a message queue.

octoque's queue has topic to help organize the message storing in the message queue. A simple illustration as below:

```shell
├── queue server                                                                 
│   
└── queue
    │   
    └── topics
        │
        └── default topic [messages....]
        │
        └── pubsub topic [messages....]
```
The current message queue only running in FIFO mode. There is two topic connection type, `BROKER` and `PUBSUB`. 

`BROKER` works as a message broker, it is request-response based, the queue server will handling incoming request and process it accordingly. 

`PUBSUB` used to allow application to publish and subcribe on certain queue topic, whenever there are new messages reached the queue topic, it will be automatic push to its subscriber.

octoque command started with its own protocol, `otq`, it also has its own comand format, for example:

```shell
## connect to octoque, acquire a conection by authenticate with username/password
> otq connect admin password

## display the state of all the queue topic
> otq display *

## put a new message to default topic with batch delivery mode
> otq put default 1 batch

## get a message from default topic with batch delivery mode
> otq get default 1 batch

## subscribe to pubsub topic, all new message will be received automatically
> otq subscribe pubsub

## create new topic with broker type in octoque
> otq new topic1 broker

## disconnect from octoque
> otq disconnect
```

To try out, you can run `octoque repl` to start octoque in REPL mode, then you can run the command above in the terminal.

### Running with podman / docker

The image is available at quay.io/jaar23/octoque. 

Running as octoque server

```shell
podman pull quay.io/jaar23/octoque:latest

podman run -d -p 6789:6789 quay.io/jaar23/octoque:latest

```

Then, you can use the client library to connect octoque with your application, a quick example can refer [octoque_client](https://github.com/jaar23/octoque_client)

[Getting started](./doc/getting-started.md)

More documentation is coming soon.
