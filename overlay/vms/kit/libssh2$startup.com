$! LIBSSH2$STARTUP.COM - system startup for libssh2 on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! LIBSSH2$ROOT, pointing at the installed [LIBSSH2] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:LIBSSH2$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign LIBSSH2$ROOT instead (PCSI runs it so at removal).
$!
$! Programs then compile with /INCLUDE=LIBSSH2$ROOT:[INCLUDE] and link with
$!     LINK prog,LIBSSH2$ROOT:[LIB]LIBSSH2/OPTIONS
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("LIBSSH2$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode LIBSSH2$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[LIBSSH2].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.LIBSSH2.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "LIBSSH2.]"
$ if root .eqs. dir + "LIBSSH2.]"
$ then
$   write sys$error "LIBSSH2$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed LIBSSH2$ROOT 'dev''root'
$ if f$search("LIBSSH2$ROOT:[LIB]LIBSSH2.OLB") .eqs. ""
$ then
$   write sys$error "LIBSSH2$STARTUP: LIBSSH2.OLB not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for libssh2"
$ say ""
$ say "    At system startup: to define LIBSSH2$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:LIBSSH2$STARTUP.COM"
$ say "    To build with it: compile with /INCLUDE=LIBSSH2$ROOT:[INCLUDE] and"
$ say "    /NAMES=(AS_IS,SHORTENED), link with LIBSSH2$ROOT:[LIB]LIBSSH2/OPTIONS."
$ say ""
$ say "    PRODUCT REMOVE LIBSSH2 removes the product and deassigns LIBSSH2$ROOT."
$ say ""
$ exit 1
