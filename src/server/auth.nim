import nimword, options, os, octolog, yaml, streams, sequtils,
       sugar, std/enumerate, terminal, strutils

type
  AccessMode* = enum
    TRead = "r",
    TWrite = "w",
    TNew = "n",
    TClear = "c",
    TReadWrite = "rw",
    TAll = "rwnc"
  UpdateMode* = enum
    Append, Replace
  Topic* = object
    name*: string
    access*: string
  Role* = object
    name*: string
    topics*: seq[Topic]
  User* = object
    username*: string
    passwordHash*: string
    role*: string
    topics*: seq[string]
  Auth* = object
    roles*: seq[Role]
    users*: seq[User]

  AuthFileError = object of CatchableError
  AuthError = object of CatchableError

const argon2Iteration = 3

template stdoutWarning (msg: string) =
  stdout.setForegroundColor(fgMagenta)
  stdout.write msg
  stdout.resetAttributes()


proc initAuthFile(): void {.raises: AuthFileError.} =
  try:
    let
      authDir = getHomeDir() & "/.config/octoque/"
      authFile = "auth.yaml"
      defaultTopicReadWrite = Topic(name: "default", access: $TReadWrite)
      defaultTopicAllAccess = Topic(name: "default", access: $TAll)
      adminRole = Role(name: "admin", topics: @[defaultTopicAllAccess])
      userRole = Role(name: "user", topics: @[defaultTopicReadWrite])
      iterations: int = 3
      encodedHash: string = hashEncodePassword("password", iterations)
      adminUser = User(username: "admin", passwordHash: encodedHash,
          role: "admin", topics: @["default"])
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


proc printUserInfo(user: User, updatedPassword = false): void =
  octolog.info "username: " & user.username
  octolog.info "password: " & (if updatedPassword: "updated" else: "not updated")
  octolog.info "role    : " & user.role
  octolog.info "topics  : " & $user.topics


proc verifyPassowrd*(password: string, passwordHash: string): bool =
  isValidPassword(password, passwordHash)


proc findUser(auth: Auth, username: string): (int, Option[User]) =
  var user: User
  var found = false
  var index = -1
  for u in auth.users:
    index = index + 1
    if u.username == username:
      user = u
      found = true
      break
  return if found: (index, some(user)) else: (-1, none(User))


proc userHasAccess*(auth: Auth, username, topic: string): bool =
  let users = auth.users.filter(u => u.username == username)
  if users.len > 0:
    if users[0].topics.contains(topic):
      return true
    else:
      return false
  else:
    return false


proc roleHasAccess*(auth: Auth, role, topic: string,
    accessMode: AccessMode): bool =
  ## admin access
  if role == "admin" and topic == "*" and accessMode == TRead:
    return true
  if role == "admin" and accessMode == TNew:
    octolog.info "authorized to create new topic"
    return true

  let roles = auth.roles.filter(r => r.name == role)
  if role.len > 0:
    let topics = roles[0].topics.filter(t => t.name == topic)
    ## topic not exists
    if topics.len == 0:
      return false
    ## access mode is right
    if topics[0].access == $TAll:
      result = true
    elif topics[0].access.contains($accessMode):
      result = true
    else:
      result = false
  else:
    result = false


proc createUser*(username, password: string, role: Option[string],
    topics: seq[string]): void {.raises: [AuthError, AuthFileError].} =
  try:
    var auth = getAuth()
    let userRole = if role.isSome: role.get else: "user"
    if auth.users.filter(u => u.username == username).len > 0:
      raise newException(AuthError, "user is already existed")
    if auth.roles.filter(r => r.name == userRole).len > 0:
      let encodedHash: string = hashEncodePassword(password, argon2Iteration)
      var user = User(username: username, passwordHash: encodedHash,
          role: userRole)
      if topics.len > 0:
        for topic in topics:
          user.topics.add(topic)

      auth.users.add(user)
      printUserInfo(user)
      saveAuth(auth)
      stdoutWarning "Changes will take effect after octoque restart\n"
    else:
      octolog.error("role is not exists")
      raise newException(AuthError, "role is not exist")
  except AuthFileError as aferr:
    raise newException(AuthFileError, aferr.msg)
  except AuthError as aerr:
    raise newException(AuthError, aerr.msg)
  except:
    raise newException(AuthError, getCurrentExceptionMsg())


proc updateUser*(username: string, password, role: Option[string], topics: seq[
    string], updateMode: UpdateMode = Append): void {.raises: [AuthError,
    AuthFileError].} =
  try:
    var auth = getAuth()
    var roleToUpdate = ""
    var (index, user) = findUser(auth, username)
    if user.isNone:
      raise newException(AuthError, "user is not found")
    if role.isSome and auth.roles.filter(r => r.name == role.get).len > 0:
      roleToUpdate = role.get
    if updateMode == Append:
      if topics.len > 0:
        for t in topics:
          if not user.get.topics.contains(t):
            user.get.topics.add(t)
    elif updateMode == Replace:
      if password.isSome:
        let encodedHash: string = hashEncodePassword(password.get, argon2Iteration)
        user.get.passwordHash = encodedHash
      if role.isSome:
        user.get.role = roleToUpdate
      if topics.len > 0:
        user.get.topics = topics
    else:
      raise newException(CatchableError, "Unknown update mode passed in. This should not happen")

    auth.users.delete(index)
    auth.users.add(user.get)
    printUserInfo(user.get, password.isSome)
    stdoutWarning "Changes will take effect after octoque restart\n"
    saveAuth(auth)
  except AuthFileError as aferr:
    raise newException(AuthFileError, aferr.msg)
  except AuthError as aerr:
    raise newException(AuthError, aerr.msg)
  except:
    raise newException(AuthError, getCurrentExceptionMsg())


proc removeUser*(username: string, topics: seq[string]): void {.raises: [
    AuthError, AuthFileError].} =
  try:
    var auth = getAuth()
    var (index, user) = findUser(auth, username)
    if user.isNone:
      raise newException(AuthError, "user is not found")
    if topics.len > 0:
      for i, t in enumerate(topics):
        if user.get.topics.contains(t):
          user.get.topics.delete(i)
          octolog.info "'" & t & "' has been removed from user's accessible topic"
      saveAuth(auth)
      stdoutWarning "Changes will take effect after octoque restart\n"
    else:
      echo "Please confirm you want to remove this user? (y/n)"
      var confirmation = readLine(stdin)
      if confirmation.toLowerAscii() == "y" or confirmation.toLowerAscii() == "yes":
        echo "Please enter admin password: "
        let adminPassword = readPasswordFromStdin()
        let encodedPasswordHash = auth.users.filter(u => u.username == "admin")[0].passwordHash
        if isValidPassword(adminPassword, encodedPasswordHash):
          auth.users.delete(index)
          octolog.info "user has been removed"
          saveAuth(auth)
          stdoutWarning "Changes will take effect after octoque restart\n"
      else: octolog.info "operation cancelled"

  except AuthFileError as aferr:
    raise newException(AuthFileError, aferr.msg)
  except AuthError as aerr:
    raise newException(AuthError, aerr.msg)
  except:
    raise newException(AuthError, getCurrentExceptionMsg())




