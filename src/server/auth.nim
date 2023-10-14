import nimword, options, os, octolog, yaml, streams, sequtils, sugar

type
  AccessMode* = enum
    TRead = "r", TWrite = "w", TReadWrite = "rw"
  Topic = object
    name: string
    access: string
  Role = object
    name: string
    topics: seq[Topic]
  User = object
    username: string
    passwordHash: string
    role: string
    topics: seq[Topic]
  Auth* = object
    roles: seq[Role]
    users: seq[User]

  AuthFileError = object of CatchableError
  AuthError = object of CatchableError

proc initAuthFile(): void {.raises: AuthFileError.} =
  try:
    let
      authDir = getHomeDir() & "/.config/octoque/"
      authFile = "auth.yaml"
      defaultTopicRead = Topic(name: "default", access: $TRead)
      defaultTopicReadWrite = Topic(name: "default", access: $TReadWrite)
      adminRole = Role(name: "admin", topics: @[defaultTopicReadWrite])
      userRole = Role(name: "user", topics: @[defaultTopicRead])
      iterations: int = 3
      encodedHash: string = hashEncodePassword("password", iterations)
      adminUser = User(username: "admin", passwordHash: encodedHash,
          role: "admin", topics: @[defaultTopicReadWrite])
      auth = Auth(roles: @[adminRole, userRole], users: @[adminUser])
    ## create if config folder is not exist
    discard existsOrCreateDir(authDir)
    var authYaml = newFileStream(authDir & authFile, fmWrite)
    Dumper().dump(auth, authYaml)
    authYaml.close()
  except OSError as oserr:
    octolog.info "OS failure"
    octolog.error oserr.msg
    raise newException(AuthFileError, oserr.msg)
  except IOError as ioerr:
    octolog.info "IO failure"
    octolog.error ioerr.msg
    raise newException(AuthFileError, ioerr.msg)
  except:
    octolog.info "Authentication failure"
    octolog.error getCurrentExceptionMsg()


proc getAuth*(): Auth {.raises: AuthFileError.} =
  let authDir = getHomeDir() & "/.config/octoque/"
  let authFile = "auth.yaml"
  try:
    if not fileExists(authDir & authFile):
      initAuthFile()
    var auth: Auth
    var authYaml = newFileStream(authDir & authFile)
    load(authYaml, auth)
    authYaml.close()
    return auth
  except:
    octolog.error getCurrentExceptionMsg()
    raise newException(AuthFileError, getCurrentExceptionMsg())


proc saveAuth(auth: Auth): void {.raises: AuthFileError.} =
  let authDir = getHomeDir() & "/.config/octoque/"
  let authFile = "auth.yaml"
  try:
    var authYaml = newFileStream(authDir & authFile, fmWrite)
    Dumper().dump(auth, authYaml)
    authYaml.close()
  except:
    octolog.error getCurrentExceptionMsg()
    raise newException(AuthFileError, getCurrentExceptionMsg())


#proc validateLogin*(username: string, password: string): bool


proc createUser*(username: string, password: string, role: Option[string],
    topics: seq[string]): void {.raises: [AuthError, AuthFileError].} =
  try:
    var auth = getAuth()
    let userRole = if role.isSome: role.get else: "user"
    echo auth
    echo topics
    if auth.users.filter(u => u.username == username).len > 0:
      raise newException(AuthError, "user is already existed")
    if auth.roles.filter(r => r.name == userRole).len > 0:
      let iterations: int = 3
      let encodedHash: string = hashEncodePassword(password, iterations)
      var user = User(username: username, passwordHash: encodedHash,
          role: userRole)
      if topics.len > 0:
        for t in topics:
          var topic = Topic(name: t, access: $TRead & $TWrite)
          user.topics.add(topic)

      auth.users.add(user)
      saveAuth(auth)
    else:
      octolog.error("role is not exists")
      raise newException(AuthError, "role is not exist")
  except AuthFileError as aferr:
    raise newException(AuthFileError, aferr.msg)
  except AuthError as aerr:
    raise newException(AuthError, aerr.msg)
  except:
    raise newException(AuthError, getCurrentExceptionMsg())




#proc updateUser*(username: string, password: Option[string], role: Option[string], topic: varargs)

#proc removeUser*(username: string, password: Option[string], role: Option[string], topic: varargs)

