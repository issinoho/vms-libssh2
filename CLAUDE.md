# CLAUDE.md

libssh2 for OpenVMS (IA64 and x86-64), built with VSI C against VSI's SSL3 kit (OpenSSL
3.0), wrapped by the same tooling as `~/projects/vms-zstd` and the other sibling ports
(read vms-zstd's `CLAUDE.md` for the VMS and ssh pitfalls; they all apply). Made for
`~/projects/vms-vftp` (its D3), which links the object library statically.

- **Never edit `staging/`, `cache/` or `out/`.** Upstream files change only through
  `patches/` (listed in `patches/series`); our files live in `overlay/vms/`.
- **Use `tools/vms.sh`** for remote work; never raw `ssh host cmd`, never `WAIT` over ssh.
- **Committed files must not contain real node details** (they live in `tools/nodes.conf`),
  credentials or private keys.
- Work directories: IA64 the family's `[.VMS_GREP]` (beside vms-zlib, vms-zstd...); x86
  `DISK$SYSDUMP:[IAIN.VMS_LIBSSH2]` (x86 no longer has `USER$ROOT:[IAIN.VMS_GREP]`).
- The build is our `[.VMS]BUILD.COM` (DCL, no MMS): it compiles `src/Makefile.inc`'s
  CSOURCES (listed by prepare.sh into `vms/sources.txt`), always all of them.
  Upstream's own `vms/libssh2_make_*.dcl` (2010, Alpha, HP SSL, GNV shared image) are
  not used; its `vms/libssh2_config.h` is, patched (0001).
- Compile warnings from upstream code are allowed and stay in the log; errors fail.
  `tools/build.sh` also fails on link errors and undefined symbols.

```sh
tools/prepare.sh                 # after every change to patches/ or overlay/
tools/build.sh <x86|ia64> [ALL|CLEAN] [KEEP_GOING]
tools/vms.sh <node> run <proc.com> [params]   # e.g. the smoke tests
```

If a push seems to have sent nothing after a failed first push, delete
`cache/pushed-*` (the manifest records files as sent).

Don't push without the user asking; the GitHub repository does not exist yet.
