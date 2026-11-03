$! VMS_INSTALLCHECK.COM <tree-dir-name> <port> - install the LIBSSH2 kit, verify it,
$! build the smoke test against the installed kit (headers, LIBSSH2.OPT) and run its
$! handshake against this node's sshd on <port>, then remove the kit.  Changes the
$! system while it runs (PCSI database, SYS$COMMON:[LIBSSH2], system logical
$! LIBSSH2$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ tree = f$environment("DEFAULT") - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install LIBSSH2 /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product LIBSSH2 /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:LIBSSH2$STARTUP.COM"), "]"
$ show logical LIBSSH2$ROOT
$ directory/nohead/notrail LIBSSH2$ROOT:[000000...]*.*
$ open/read opt LIBSSH2$ROOT:[LIB]LIBSSH2.OPT
$opt_loop:
$ read/end=opt_done opt line
$ write sys$output "LIBSSH2.OPT: ", line
$ goto opt_loop
$opt_done:
$ close opt
$ write sys$output "=== SMOKE TEST built against the installed kit"
$ scratch = tree - "]" + ".INSTALLCHECK]"
$ if f$search(tree - "]" + "]INSTALLCHECK.DIR") .eqs. "" then create/directory 'scratch'
$ define/process OPENSSL SSL3$INCLUDE:
$ cc/names=(as_is,shortened)/pointer_size=32/define=(_USE_STD_STAT=1,_LARGEFILE) -
     /include=LIBSSH2$ROOT:[INCLUDE] /object='scratch'SSH2_SMOKE.OBJ 'tree'[.VMS]SSH2_SMOKE.C
$ write sys$output "SMOKE: cc status ", $status
$ link/executable='scratch'SSH2_SMOKE.EXE 'scratch'SSH2_SMOKE.OBJ,LIBSSH2$ROOT:[LIB]LIBSSH2/options
$ write sys$output "SMOKE: link status ", $status
$ smoke = "$" + scratch + "SSH2_SMOKE.EXE"
$ smoke "127.0.0.1" 'p2'
$ write sys$output "SMOKE: exit status ", $status
$ deassign/process OPENSSL
$ delete/nolog 'scratch'*.*;*
$ set protection=o:rwed 'tree'INSTALLCHECK.DIR
$ delete/nolog 'tree'INSTALLCHECK.DIR;
$ write sys$output "=== REMOVE"
$ product remove LIBSSH2 /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "LIBSSH2$ROOT after removal: [", f$trnlnm("LIBSSH2$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[LIBSSH2...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:LIBSSH2$STARTUP.COM"), "]"
$ product show product LIBSSH2 /producer=ISSINOHO
