### Persistence

- Append only file per topic
    
    Pros:

    - easy and fast

    Cons:

    - hard to keep track of read receipt
    - longer processing time while restart

- Sqlite db per topic
    
    Pros:

    - easy and fast
    - single file per topic
    - query possible

    Cons:
    
    - ??

