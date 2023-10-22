## Message Comamnd

This page shows all the available commands in octoque v0.1.0.

**Note** queue topic name is case sensitive.

**Note** command is case insensitive.

**Note** space is used to delimit the action within command

`CONNECT`

authenticate the user and acquire a connection.

command structure: `<PROTOCOL> <COMMAND> <USERNAME> <PASSWORD>`

default user      : `admin`

default password  : `password`
```shell
OTQ CONNECT admin password
```

`DISCONNECT`

disconnect and release the current connection

command structure: `<PROTOCOL> <COMMAND>`

```shell
OTQ DISCONNECT
```

`DISPLAY`

display the state of queue topic, normally is used in REPL mode only.

command structure: `<PROTOCOL> <COMMAND> <TOPIC>`

*use "\*\" to display all the topic available*

```shell
## display the state of default topic
OTQ DISPLAY default

## display the state of all topic
OTQ DISPLAY *
```

`GET`

get message from queue topic.

command structure: `<PROTOCOL> <COMMAND> <TOPIC> <NUMBER OF MESSAGE> <TRANSFER MODE>`

if command is validated successful, the message will be sending over after server response `PROCEED` keyword. When all the required number of messages being sending over, server will send `ENDOFRESP` to indicate the end of current transfer.

flow example:
```shell
## command
OTQ GET default 1 BATCH <--- send by client

## validated
PROCEED <--- send by server

## message output
"hello world" <--- message send out by server
```

```shell
## get 1 message from default topic via batch transfer mode
OTQ GET default 1 BATCH

## get 10 message from default topic via batch transfer mode
OTQ GET default 10 BATCH
```

`PUT`

put message to queue topic.

command structure: `<PROTOCOL> <COMMAND> <TOPIC> <ROWS OF PAYLOAD> <TRANSFER MODE>`

if command is validated successful, the message will be sending over after server response with `PROCEED` keyword. When all the required number of messages being sending over, server will send `ENDOFRESP` to indicate the end of current transfer.

flow example:
```shell
## command
OTQ PUT default 1 BATCH <--- send by client

## validated
PROCEED <--- send by server

## message data
"hello world" <--- message send by client
```

```shell
## put 1 message to default topic via batch transfer mode
OTQ PUT default 1 BATCH

## put 10 message to default topic via batch transfer mode
OTQ PUT default 10 BATCH
```
if you are using REPL mode, it will prompt you to enter the data after server is response with `PROCEED` keyword, client library will handle itself, you only required to send in the command and message like normal function.

`PUTACK`

put message to queue topic, server will response whether operation is success or fail, behavior is similar to `PUT` command, please refer to above.

command structure: `<PROTOCOL> <COMMAND> <TOPIC> <ROWS OF PAYLOAD> <TRANSFER MODE>`


```shell
## put 1 message to default topic via batch transfer mode
OTQ PUTACK default 1 BATCH

SUCCESS <--- send by server to acknowledge that is successfully put

## put 10 message to default topic via batch transfer mode
OTQ PUTACK default 10 BATCH

FAIL <--- send by server if any of the message fail to put
```

`SUBSCRIBE`

subscribe for all incoming message to queue topic (pubsub connection type), only message data is being sending over. 

command structure: `<PROTOCOL> <COMMAND> <TOPIC>`

```shell
## subscribe to pubsub queue topic
OTQ SUBSCRIBE pubsub

PROCEED <--- send by server after validated command

"hello world!" <--- send by server when there is any new message.
```

Error will be return with `DECLINE:<FAIL REASONS>` format when subscribe to non `PUBSUB` connection type queue topic.


`UNSUBSCRIBE`

unsubscribe current subscripiton.

command structure: `<PROTOCOL> <COMMAND> <TOPIC>`

```shell
## unscubscribe from pubsub queue topic
OTQ UNSUBSCRIBE pubsub
```

`PING`

check the existence of a queue topic.

command structure: `<PROTOCOL> <COMMAND> <TOPIC>`

```shell
## check if default topic exists
OTQ PING default

## return 'PONG' if success, 'NOT FOUND' if failed
PONG
```

`CLEAR`

clear message in the topic and reset.

command structure: `<PROTOCOL> <COMMAND> <TOPIC>`

```shell
## clear default topic
OTQ CLEAR default

## return 'SUCCESS' if success, 'FAIL' if failed
SUCCESS
```

`NEW`

create new queue topic

command structure: `<PROTOCOL> <COMMAND> <TOPIC> <CONNECTION TYPE> <CAPACITY> <LISTENER THREAD>`

`<CAPACITY>` and `<LISTENER THREAD>` is optional value, default value will be used if not pass in.

`CAPACITY` used to determine how many message is able to hold by the topic, default capacity is unlimited. Unlimited also means to be limit by current system available memory. `OOM` exception will be raised when trying to store more message than system available memory. A solution about catch for this execption or default the capacity based on available memory is work in progress.

`LISTENER THREAD` used to determine how many listener will be stand by for new message, default is 1.

**Note** You cannot have two topic with the same name, an exception will be raised.

```shell
## create new topic with unlimited capacity with BROKER type
OTQ NEW topic1 BROKER

## create new topic with unlimited capacity with PUBSUB type
OTQ NEW topic2 PUBSUB

## create new topic with 500 capacity with BROKER type
OTQ NEW topic3 BROKER 500

## create new topic with unlimited capacity with BROKER type and 2 listener thread
OTQ NEW topic4 BROKER T2

## create new topic with 500 capacity with BROKER type and 2 listener thread
OTQ NEW topic5 BROKER 500 T2
```

`PUBLISH`

put message to multiple queue topic (work in progress)


Find out more about [message structure](./message-structure.md)
