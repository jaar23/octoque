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
        
        OTQ GET default 1 BATCH
       
    
    -  put command 
        
        OTQ PUT default 1  BATCH 11
        hello world
       
[x] new topic on the fly
    
    example:

    OTQ NEW APPTOPIC BROKER

[x] REPL, send command to octoque without using the client. Currently do not support for pubsub command.
   
    example:

    - start with `octoque --interactive y`

[ ] start with file config

[ ] error queue

[ ] schema based queue

[p] streaming of data 

    - stream from file

    - stream from memory
[x] batch delivery

[ ] secure queue access with external secure services

[p] file-based authentication as default secure service
    
    dependencies: argon2, libsodium
    
    fedora / rhel: `sudo yum install libsodium -y`

    macos: `brew install libsodium`

[ ] COMMIT command to persist store

[ ] persistent store

[ ] replay queue based on log

[ ] monitoring

[x] running in single core cpu environment
    
    current implementation keeping the queue data in a long running threads.
    this required the process to keep multiple threads which causing the program
    running out of available thread when adding new topic. 
    after evaluation, current resolution is to limit the number of available topic
    running in the process. there is always a limitation for a low end hardware.
    in this case, pubsub will be limited by the number of available thread.
