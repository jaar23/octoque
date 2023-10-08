# octoque
simple queue server implemented in nim

todo:

[x] pubsub channel

[x] multiple subcriber (push and broadcast based)

[x] logging for common and pubsub channel

[x] standardize response

[x] standardize request
    
    example:
    
    - get command
        ```
        OTQ GET default 1 BATCH
        ```
    
    -  put command 
        ```
        OTQ PUT default 1  BATCH 11
        hello world
        ```
    
[p] streaming of data

[p] new topic on the fly

[x] REPL, send command to octoque without using the client. Currently do not support for pubsub command.
   
    example:

    - start with `octoque --interactive y`

[ ] init with file config

[ ] error queue

[ ] persistent store

[ ] schema based queue

[x] batch delivery

[ ] secure queue access with external secure services

[ ] file-based authentication as default secure service
