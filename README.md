# octoque
simple queue server implemented in nim

todo:

[x] pubsub channel

[x] multiple subcriber (push and broadcast based)

[x] logging for common and pubsub channel

[p] standardize response

[p] standardize request
    
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

[ ] new topic on the fly

[ ] REPL

[ ] init with file config

[ ] error queue

[ ] persistent store

[ ] schema based queue

[p] batch delivery


