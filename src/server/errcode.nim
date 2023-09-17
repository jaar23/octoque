
type 
  QErrCode* = enum
    TOPIC_NOT_FOUND         = "Requested topic not found"
    NOT_IMPLEMENTED         = "Feature not implemented"
    INVALID_COMMAND         = "Invalid queue command"
    INVALID_TRANSFER_METHOD = "Invalid transfer method"
    INVALID_PROTOCOL        = "Invalid protocol"
    INVALID_PAYLOADROWS     = "Invalid rows of payload, positive number only"
    INVALID_CONTENT_LENGTH  = "Invalid content length, positive number only"

