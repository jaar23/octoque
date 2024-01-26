
todo:

[x] pubsub channel

[x] multiple subcriber (push and broadcast based)

[ ] subcribe to multiple topic

[ ] publish to multiple topic

[ ] check on state before access

    - queue state

    - topic state

[ ] message properties (internal use)

[x] logging for common and pubsub channel

[x] standardize response

[x] standardize request
    
    example:
    
    - get command
        
        OTQ GET default 1 BATCH
       
    
    -  put command 
        
        OTQ PUT default 1  BATCH 11
        hello world
       
[x] new topic on the fly
    
    example:

    OTQ NEW APPTOPIC BROKER

[x] REPL, send command to octoque without using the client.
   
    example:

    - start with `octoque repl`

[x] start with command line
    
    example:

    - start with `octoque run`

[x] start in detach mode
    
    start with `octoque run -d &`
    
    should upgrade when osproc's poDaemon is available

[ ] start with file config

[ ] error queue

[ ] schema based queue

[ ] streaming of data 

    - stream from file

    - stream from memory

[x] batch delivery

[ ] secure queue access with external secure services

[x] file-based authentication as default secure service
    
    dependencies: argon2, libsodium
    
    fedora / rhel: `sudo yum install libsodium -y`

    macos: `brew install libsodium`
    
    otq adm create -u user01 -p password -r admin -t default -t pubsub

[ ] COMMIT command to persist store

[ ] persistent store

[ ] replay queue based on log / persistent data

[ ] monitoring

[x] running in single core cpu environment
    
    current implementation keeping the queue data in a long running threads.
    this required the process to keep multiple threads which causing the program
    running out of available thread when adding new topic. 
    after evaluation, current resolution is to limit the number of available topic
    running in the process. there is always a limitation for a low end hardware.
    in this case, pubsub will be limited by the number of available thread.

[ ] documentation

[x] client library

[x] remove disconnected connection

[ ] commit by request, log by request or config
