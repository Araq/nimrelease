## Tool to build a Nim release package for diverse OSes.

#[

The Windows OpenSSL libraries that we ship via dlls.7z or windeps.7z
are taken from::

  https://curl.se/windows/dl-7.75.0_5/openssl-1.1.1k_5-win64-mingw.zip
  https://curl.se/windows/dl-7.75.0_5/openssl-1.1.1k_5-win32-mingw.zip
  (coming from https://github.com/curl/curl-for-win#binary-package-downloads)

Note the Windows MingW that we "ship" via finish.exe post 2021-05-15 directly
taken from (mirrored)::

  https://github.com/brechtsanders/winlibs_mingw/releases/download/11.1.0-12.0.0-8.0.2-r1/winlibs-x86_64-posix-seh-gcc-11.1.0-mingw-w64-8.0.2-r1.7z
  https://github.com/brechtsanders/winlibs_mingw/releases/download/11.1.0-12.0.0-8.0.2-r1/winlibs-i686-posix-dwarf-gcc-11.1.0-mingw-w64-8.0.2-r1.7z


Note the Windows MingW that we "ship" via finish.exe pre 1.4.8 (2021-05-15) is based on::

  https://jmeubank.github.io/tdm-gcc/articles/2020-03/9.2.0-release

]#

import os, strformat, strscans, strutils, osproc, cpuinfo

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

if os.paramCount() <= 2:
  quit """Usage: nimrelease command $version $hash

command is one of the following:

  all  -- run all nimrelease steps

Steps:

  1. download  -- download the tarballs from the nightly builds
  2. build -- build the tarballs
  3. test  -- test the tarballs
  4. update -- update the stable channel
"""

let cmd = paramStr(1)
let nimver = paramStr(2)
let hash = paramStr(3) # "2019-11-27-version-1-0-c8998c4"

const
  baseUrl = "https://github.com/nim-lang/nightlies/releases/download/"
  hotPatch = "" # "-1"
  ourDownloadDir = "/var/www/nim-lang.org/download"

var phase = ""

proc exec(cmd: string) =
  if execShellCmd(cmd) != 0: quit("FAILURE: " & cmd & "\nPHASE: " & phase)

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

proc downloadTarballs =
  phase = "download"
  withDir(ourDownloadDir):
    # Unix tarball:
    wget(dest ".tar.xz", source ".tar.xz")

    # Windows:
    wget(dest "_x32.zip", source "-windows_x32.zip")
    wget(dest "_x64.zip", source "-windows_x64.zip")

    # Linux
    wget(dest "-linux_x32.tar.xz", source "-linux_x32.tar.xz")
    wget(dest "-linux_x64.tar.xz", source "-linux_x64.tar.xz")

proc isNewerVersion(a, b: string): bool =
  var amajor, aminor, apatch, bmajor, bminor, bpatch: int
  assert scanf(a, "$i.$i.$i", amajor, aminor, apatch)
  assert scanf(b, "$i.$i.$i", bmajor, bminor, bpatch)
  if apatch mod 2 == 1:
    # release candidate: is not newer than latest stable release
    result = false
  else:
    result = (amajor, aminor, apatch) > (bmajor, bminor, bpatch)

proc execCleanPath*(cmd: string; additionalPath = "") =
  # simulate a poor man's virtual environment
  let prevPath = getEnv("PATH")
  when defined(windows):
    let cleanPath = r"$1\system32;$1;$1\System32\Wbem" % getEnv"SYSTEMROOT"
  else:
    const cleanPath = r"/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/X11/bin:."
  putEnv("PATH", cleanPath & PathSep & additionalPath)
  echo(cmd)
  if execShellCmd(cmd) != 0: quit("FAILURE: " & cmd)
  putEnv("PATH", prevPath)

proc patchNimdocCfg() =
  # DigitalOcean is a masterpiece of engineering. It manages to cache
  # unrelated CSS files for weeks. We workaround this here.
  const
    lineToPatch = """<link rel="stylesheet" type="text/css" href="$nimdoccss">"""
    patchedLine = """<link rel="stylesheet" type="text/css" href="$nimdoccss?reloadcss=hack">"""
    cfg = "config/nimdoc.cfg"
  let content = readFile(cfg)
  writeFile(cfg, content.replace(lineToPatch, patchedLine))

proc builddocs() =
  phase = "docs"
  var major = ""
  var minor = ""
  assert scanf(nimver, "$+.$+.", major, minor)
  let nimdocs = &"nimdocs-{nimver}"
  if not dirExists(nimdocs):
    exec("git clone https://github.com/nim-lang/nim " & nimdocs)

  const dotslash = when defined(posix): "./" else: ""

  withDir(&"nimdocs-{nimver}"):
    if not fileExists("web/upload/" & nimver & "/manual.html"):
      copyFileWithPermissions("../csources/bin/nim", "bin/nim")

      exec(&"git checkout version-{major}-{minor}")
      exec(&"git pull origin version-{major}-{minor}")

      patchNimdocCfg()

      # build a version of 'koch' that uses the proper version number
      execCleanPath("bin/nim c koch.nim")

      # build a version of 'nim' that uses the proper version number
      execCleanPath(dotslash & "koch boot -d:release")
      # build the documentation:
      execCleanPath(dotslash & "koch docs0 --docCmd:skip")
    copyDir("web/upload/" & nimver, "/var/www/nim-lang.org/" & nimver)

proc copyDocs() =
  phase = "docs"
  var major = ""
  var minor = ""
  assert scanf(nimver, "$+.$+.", major, minor)

  let toUnpack = ourDownloadDir / dest "_x64.zip"
  let tmpNim = &"nim-{nimver}-deleteme"
  exec("unzip " & quoteShell(toUnpack) & " -d " & tmpNim)
  copyDir(tmpNim / &"nim-{nimver}" / "doc/html", "/var/www/nim-lang.org/" & nimver)
  removeDir(tmpNim)

proc updateLinks =
  # Updating links to the current docs:
  withDir("/var/www/nim-lang.org/"):
    exec(&"ln -sfn {nimver} docs")
    # verify this worked:
    exec("ls -la | grep \"docs\"")

proc buildTarballs =
  phase = "build"
  withDir("/var/www/nim-lang.org/download"):
    exec(&"cp nim-{nimver}.tar.xz nim-{nimver}_copy.tar.xz")
    exec(&"unxz nim-{nimver}_copy.tar.xz")
    exec(&"gzip --best nim-{nimver}_copy.tar")
    exec(&"mv nim-{nimver}_copy.tar.gz nim-{nimver}.tar.gz")
    exec(&"sha256sum nim-{nimver}.tar.gz > nim-{nimver}.tar.gz.sha256")

proc testSourceTarball =
  phase = "test"
  # Todo: Test for binaries inside the other tarballs.
  let tarball = dest(".tar.xz")

  let oldCurrentDir = getCurrentDir()
  try:
    let destDir = getTempDir()
    copyFile(ourDownloadDir / tarball,
             destDir / tarball)
    setCurrentDir(destDir)
    execCleanPath("tar -xJf " & tarball)
    setCurrentDir("nim-" & nimver)
    execCleanPath("sh build.sh")
    # first test: try if './bin/nim --version' outputs something sane:
    let output = execProcess("./bin/nim --version").splitLines
    if output.len > 0 and output[0].contains(nimver):
      echo "Version check: success"
      execCleanPath("./bin/nim c koch.nim")
      execCleanPath("./koch boot -d:release", destDir / "bin")
      when false:
        # This takes a lot of time and we already build the documentation
        # in the very first step. To speed-up the build, this is now disabled.
        # check the docs build:
        execCleanPath("./koch docs --docCmd:skip", destDir / "bin")
        # check nimble builds:
        execCleanPath("./koch tools -d:release")
      # check the tests work:
      putEnv("NIM_EXE_NOT_IN_PATH", "NOT_IN_PATH")
      execCleanPath("./koch tests --nim:./bin/nim cat macros", destDir / "bin")

      execCleanPath("./koch nimble -d:release")
      # check that a simple nimble test works:
      let nimExe = getCurrentDir() / "bin/nim"
      execCleanPath(&"./bin/nimble install -y --nim:{nimExe} npeg", nimExe)
    else:
      echo "Version check: failure"
  finally:
    setCurrentDir oldCurrentDir

proc updateStableChannel =
  phase = "update"
  # Update the stable channel:
  withDir("/var/www/nim-lang.org/channels"):
    let oldVersion = try: readFile("stable") except: "0.0.0"
    if isNewerVersion(nimver, oldVersion):
      updateLinks()
      writeFile("stable", nimver & "\n")
      echo "New latest stable release is: ", nimver
    else:
      echo "There is a different latest stable release: ", oldVersion

proc showNumberOfCpus() =
  echo cpuinfo.countProcessors()

case cmd
of "0", "all":
  #builddocs()
  downloadTarballs()
  copyDocs()
  buildTarballs()
  #testSourceTarball()
  updateStableChannel()
  #of "1", "docs":
  #  builddocs()
of "1", "download":
  downloadTarballs()
  copyDocs()
of "2", "build": buildTarballs()
of "3", "test": testSourceTarball()
of "4", "update": updateStableChannel()
of "cpus": showNumberOfCpus()
