
import os, strformat

#[
Based on these instructions:

### Uploading docs

- ``export NIM_VER=<current_ver>`` (for example ``export NIM_VER=0.19.0``).
- Upload documentation to ``/var/www/nim-lang.org/$NIM_VER``
- Change ``docs`` symlink
  - ``cd /var/www/nim-lang.org/``
  - ``ln -sfn $NIM_VER docs`` (change the version here)
  - Verify this worked using ``ls -la | grep "docs"``

### Updating choosenim's channels

Choosenim currently only supports gz so you will need to create a .tar.gz out of the .tar.xz:

- ``export NIM_VER=<current_ver>``
- ``cd /var/www/nim-lang.org/download``
- ``cp nim-$NIM_VER.tar.xz nim-"$NIM_VER"_copy.tar.xz``
- ``unxz nim-"$NIM_VER"_copy.tar.xz``
- ``gzip --best nim-"$NIM_VER"_copy.tar``
- ``mv nim-"$NIM_VER"_copy.tar.gz nim-"$NIM_VER".tar.gz``
- ``sha256sum nim-"$NIM_VER".tar.gz > nim-"$NIM_VER".tar.gz.sha256``

Update the ``stable`` channel:

- Update ``/var/www/nim-lang.org/channels`` using your favourite editor
  - ``vim /var/www/nim-lang.org/channels/stable``

]#

if os.paramCount() <= 1:
  quit "Usage: nimrelease $version $hash"

let nimver = paramStr(1)
let hash = paramStr(2) # "2019-11-27-version-1-0-c8998c4"

const
  baseUrl = "https://github.com/nim-lang/nightlies/releases/download/"
  hotPatch = "-1"

proc exec(cmd: string) =
  if execShellCmd(cmd) != 0: quit("FAILURE: " & cmd)

template withDir(dir, body) =
  let old = getCurrentDir()
  try:
    setCurrentDir(dir)
    body
  finally:
    setCurrentDir(old)

proc wget(dest, src: string) =
  let source = if src.len == 0: dest else: src
  exec(&"wget --output-document={dest} {baseUrl}{hash}/{source}")
  exec(&"sha256sum {dest} > {dest}.sha256")

proc source(suffix: string): string =
  result = "nim-" & nimver & hotPatch & suffix

proc dest(suffix: string): string =
  result = "nim-" & nimver & suffix

withDir("/var/www/nim-lang.org/download"):
  # Unix tarball:
  wget(dest ".tar.xz", source ".tar.xz")

  # Windows:
  wget(dest "_x32.zip", source "-windows_x32.zip")
  wget(dest "_x64.zip", source "-windows_x64.zip")

  # Linux
  wget(dest "-linux_x32.tar.xz", source "-linux_x32.tar.xz")
  wget(dest "-linux_x64.tar.xz", source "-linux_x64.tar.xz")

# Updating links to the current docs:
withDir("/var/www/nim-lang.org/"):
  exec(&"ln -sfn {nimver} docs")
  # verify this worked:
  exec("ls -la | grep \"docs\"")

withDir("/var/www/nim-lang.org/download"):
  exec(&"cp nim-{nimver}.tar.xz nim-{nimver}_copy.tar.xz")
  exec(&"unxz nim-{nimver}_copy.tar.xz")
  exec(&"gzip --best nim-{nimver}_copy.tar")
  exec(&"mv nim-{nimver}_copy.tar.gz nim-{nimver}.tar.gz")
  exec(&"sha256sum nim-{nimver}.tar.gz > nim-{nimver}.tar.gz.sha256")

# Update the stable channel:
withDir("/var/www/nim-lang.org/channels"):
  writeFile("stable", nimver & "\n")
