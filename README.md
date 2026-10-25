# libssh2 for OpenVMS

[libssh2](https://libssh2.org) (**1.11.1**), the client-side SSH2 library, built natively for
OpenVMS on **IA64** and **x86-64** with VSI C against VSI's **SSL3** kit (OpenSSL 3.0). It is
an object library for static linking, made for [VFTP](https://github.com/issinoho/vms-vftp),
the family's full-screen FTP, SFTP and SCP client, and part of the
[ports and tools for OpenVMS](https://openvms.issinoho.com) family.

Like the family's other ports, this repository holds **only our changes**: every build starts
from the signed release tarball (Daniel Stenberg's key, pinned in `keys/`), applies
`patches/` and adds `overlay/`.

**Status: early, not released.**

| | IA64 (V8.4-2L3) | x86-64 (E9.2-4) |
|---|---|---|
| Builds (VSI C, SSL3) | yes | yes |
| Handshake, host key SHA-256, known_hosts check | yes | yes |
| Public-key login (OpenSSH ed25519 key) | yes | yes |
| SFTP list, write, read, remove | not yet tested | not yet tested |

Negotiated with VSI OpenSSH 9.9 and GitHub: curve25519-sha256, ecdsa-sha2-nistp256 host
keys, chacha20-poly1305@openssh.com.

## Building

```sh
tools/prepare.sh            # fetch, verify, patch, stage
tools/build.sh x86          # or ia64
```

On the node the result is `[.INSTALL_<arch>.LIB]LIBSSH2.OLB` with `LIBSSH2.OPT` (the
library and `SYS$SHARE:SSL3$LIBCRYPTO_SHR32`) and the headers in
`[.INSTALL_<arch>.INCLUDE]`. Compile programs with `/NAMES=(AS_IS,SHORTENED)` and link
with `LINK prog,dev:[dir.INSTALL_<arch>.LIB]LIBSSH2/OPTIONS`.

## Changes

| Patch | What |
|---|---|
| 0001 | `vms/libssh2_config.h`: drop typedefs VSI C now has (`uint32_t`, `socklen_t`, `ssize_t`), add `HAVE_STRTOLL`, no zlib |

Ours: `vms/build.com` (the build) and `vms/ssh2_smoke.c` (the smoke test).

## Licence

libssh2's BSD-3-Clause licence (`COPYING` in the source); our patches and VMS files are
under the same terms.
