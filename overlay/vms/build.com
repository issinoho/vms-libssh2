$! BUILD.COM - build libssh2 for OpenVMS (IA64 and x86-64) with VSI C
$!
$! Usage:  @[.VMS]BUILD [target] [KEEP_GOING]
$!         target ALL (default) or CLEAN.  KEEP_GOING carries on past failed
$!         compiles so one run reports every error.
$!
$! Outputs, under the top of the prepared tree:
$!   [.INSTALL_<arch>.LIB]LIBSSH2.OLB   object library, for static linking
$!   [.INSTALL_<arch>.LIB]LIBSSH2.OPT   link options: the library and SSL3's libcrypto
$!   [.INSTALL_<arch>.INCLUDE]*.H       public headers
$!   [.BIN_<arch>]SSH2_SMOKE.EXE        the smoke-test program (TEST_SMOKE.COM)
$!
$! Crypto is VSI's SSL3 kit (OpenSSL 3.0): OPENSSL is defined as SSL3$INCLUDE:
$! for the compiles, and programs link SYS$SHARE:SSL3$LIBCRYPTO_SHR32 (32-bit
$! pointers, as libssh2 is compiled).  Names are /NAMES=(AS_IS,SHORTENED):
$! libssh2's API is mixed case and some names are longer than 31 characters.
$!
$ status = 44  ! SS$_ABORT unless the build runs
$ on control_y then goto done
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ if arch .eqs. "IA64" .or. arch .eqs. "X86_64" then goto arch_ok
$ write sys$error "BUILD: unsupported architecture ''arch'"
$ goto done
$arch_ok:
$ target = p1
$ if target .eqs. "" then target = "ALL"
$ write sys$output "BUILD: ''target' for ''arch' in ''f$environment("DEFAULT")'"
$ if target .nes. "CLEAN" then goto build
$ if f$search("[.OBJ_''arch']*.*") .nes. "" then delete/nolog [.OBJ_'arch']*.*;*
$ if f$search("[.BIN_''arch']*.*") .nes. "" then delete/nolog [.BIN_'arch']*.*;*
$ if f$search("[.INSTALL_''arch'.LIB]*.*") .nes. "" then delete/nolog [.INSTALL_'arch'.LIB]*.*;*
$ if f$search("[.INSTALL_''arch'.INCLUDE]*.*") .nes. "" then delete/nolog [.INSTALL_'arch'.INCLUDE]*.*;*
$ write sys$output "BUILD: cleaned"
$ target = "ALL"
$build:
$ if f$trnlnm("SSL3$INCLUDE") .nes. "" then goto ssl_ok
$ write sys$error "BUILD: VSI's SSL3 kit (SSL3$INCLUDE) is not installed"
$ goto done
$ssl_ok:
$ define/process OPENSSL SSL3$INCLUDE:
$ if f$search("OBJ_''arch'.DIR") .eqs. "" then create/directory [.OBJ_'arch']
$ if f$search("BIN_''arch'.DIR") .eqs. "" then create/directory [.BIN_'arch']
$ if f$search("[.INSTALL_''arch']INCLUDE.DIR") .eqs. "" then create/directory [.INSTALL_'arch'.INCLUDE]
$ if f$search("[.INSTALL_''arch']LIB.DIR") .eqs. "" then create/directory [.INSTALL_'arch'.LIB]
$ cflags = "/NAMES=(AS_IS,SHORTENED)/PREFIX_LIBRARY_ENTRIES=ALL_ENTRIES" -
         + "/POINTER_SIZE=32/WARNINGS=DISABLE=(LONGEXTERN)" -
         + "/DEFINE=(_USE_STD_STAT=1,_LARGEFILE)" -
         + "/INCLUDE=([.VMS],[.INCLUDE],[.SRC])"
$ failed = 0
$ open/read src [.VMS]SOURCES.TXT
$src_loop:
$ read/end=src_done src name
$ name = f$edit(name, "TRIM")
$ if name .eqs. "" then goto src_loop
$ obj = "[.OBJ_''arch']" + name + ".OBJ"
$ write sys$output "BUILD: cc ''name'.c"
$ set noon
$ cc'cflags'/OBJECT='obj' [.SRC]'name'.C
$ s = $status
$ set on
$ on control_y then goto done
$! Warnings (severity 0) are upstream's and are left in the log; errors stop.
$ if s .or. (s .and. 7) .eq. 0 then goto src_loop
$ failed = failed + 1
$ write sys$error "BUILD: %CC-E- ''name'.c failed"
$ if p2 .eqs. "KEEP_GOING" then goto src_loop
$ close src
$ goto done
$src_done:
$ close src
$ if failed .gt. 0 then goto done
$ lib = "[.INSTALL_''arch'.LIB]LIBSSH2.OLB"
$ if f$search(lib) .nes. "" then delete/nolog 'lib';*
$ library/create/object 'lib' [.OBJ_'arch']*.OBJ
$ purge/nolog 'lib'
$ copy/nolog [.INCLUDE]*.H [.INSTALL_'arch'.INCLUDE]
$ purge/nolog [.INSTALL_'arch'.INCLUDE]*.H
$! The options file names the library by its location in the install tree,
$! so a program links with  LINK prog,dev:[dir.INSTALL_arch.LIB]LIBSSH2/OPT
$ libspec = f$parse(lib,,,"DEVICE") + f$parse(lib,,,"DIRECTORY") + "LIBSSH2.OLB"
$ open/write opt [.INSTALL_'arch'.LIB]LIBSSH2.OPT
$ write opt "''libspec'/LIBRARY"
$ write opt "SYS$SHARE:SSL3$LIBCRYPTO_SHR32/SHAREABLE"
$ close opt
$ purge/nolog [.INSTALL_'arch'.LIB]LIBSSH2.OPT
$ write sys$output "BUILD: library ''lib'"
$!
$ write sys$output "BUILD: smoke-test program"
$ cc'cflags'/OBJECT=[.BIN_'arch']SSH2_SMOKE.OBJ [.VMS]SSH2_SMOKE.C
$ if .not. $status then goto done
$ link/executable=[.BIN_'arch']SSH2_SMOKE.EXE [.BIN_'arch']SSH2_SMOKE.OBJ,[.INSTALL_'arch'.LIB]LIBSSH2.OPT/OPTIONS
$ if .not. $status then goto done
$ purge/nolog [.BIN_'arch']SSH2_SMOKE.EXE
$ status = 1
$ write sys$output "BUILD: done"
$done:
$ set default 'saved_default'
$ exit status
