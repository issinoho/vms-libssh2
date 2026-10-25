/* ssh2_smoke.c - smoke test for libssh2 on OpenVMS.

     ssh2_smoke host port [user]
         handshake; print the host key type and SHA-256 fingerprint (as ssh
         prints it), whether known_hosts knows it, and the user's auth methods
     ssh2_smoke host port user keyfile dir
         also log in with the private key, list dir by SFTP, put a small file
         there, read it back, compare it, and remove it

   known_hosts is the file named by SSH2_SMOKE_KNOWN_HOSTS (a logical name or
   environment variable), if any.  Each step prints "SMOKE: ok <step>" or
   "SMOKE: FAIL <step> ..."; the exit status is success only if all passed.
   No password is ever read or written. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <libssh2.h>
#include <libssh2_sftp.h>

static int fails;

static void ok(const char *step) { printf("SMOKE: ok %s\n", step); }

static void fail(const char *step, LIBSSH2_SESSION *s)
{
    char *msg = 0;
    int len = 0, rc = 0;
    if (s) rc = libssh2_session_last_error(s, &msg, &len, 0);
    printf("SMOKE: FAIL %s (%d %s)\n", step, rc, msg ? msg : "");
    fails++;
}

static void base64(const unsigned char *in, int n, char *out)
{
    static const char t[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    int i;
    for (i = 0; i + 2 < n; i += 3) {
        *out++ = t[in[i] >> 2];
        *out++ = t[((in[i] & 3) << 4) | (in[i + 1] >> 4)];
        *out++ = t[((in[i + 1] & 15) << 2) | (in[i + 2] >> 6)];
        *out++ = t[in[i + 2] & 63];
    }
    if (n - i == 1) {
        *out++ = t[in[i] >> 2];
        *out++ = t[(in[i] & 3) << 4];
    } else if (n - i == 2) {
        *out++ = t[in[i] >> 2];
        *out++ = t[((in[i] & 3) << 4) | (in[i + 1] >> 4)];
        *out++ = t[(in[i + 1] & 15) << 2];
    }
    *out = 0;               /* no padding, as OpenSSH shows it */
}

static int dial(const char *host, const char *port)
{
    struct addrinfo hints, *res, *ai;
    int fd = -1;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, port, &hints, &res) != 0) return -1;
    for (ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) break;
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    return fd;
}

static void check_known(LIBSSH2_SESSION *s, const char *host, int port)
{
    const char *file = getenv("SSH2_SMOKE_KNOWN_HOSTS");
    LIBSSH2_KNOWNHOSTS *kh;
    const char *key;
    size_t len;
    int type, n, r;
    if (!file || !*file) { printf("SMOKE: known_hosts not checked\n"); return; }
    kh = libssh2_knownhost_init(s);
    if (!kh) { fail("knownhost_init", s); return; }
    n = libssh2_knownhost_readfile(kh, file, LIBSSH2_KNOWNHOST_FILE_OPENSSH);
    if (n < 0) { fail("knownhost_readfile", s); libssh2_knownhost_free(kh); return; }
    printf("SMOKE: known_hosts %s: %d entries\n", file, n);
    key = libssh2_session_hostkey(s, &len, &type);
    r = libssh2_knownhost_checkp(kh, host, port, key, len,
                                 LIBSSH2_KNOWNHOST_TYPE_PLAIN | LIBSSH2_KNOWNHOST_KEYENC_RAW, 0);
    printf("SMOKE: known_hosts says %s\n",
           r == LIBSSH2_KNOWNHOST_CHECK_MATCH ? "MATCH" :
           r == LIBSSH2_KNOWNHOST_CHECK_MISMATCH ? "MISMATCH" :
           r == LIBSSH2_KNOWNHOST_CHECK_NOTFOUND ? "NOTFOUND" : "FAILURE");
    ok("known_hosts");
    libssh2_knownhost_free(kh);
}

static void sftp_steps(LIBSSH2_SESSION *s, const char *dir)
{
    static const char data[] = "libssh2 smoke test\nsecond line\n";
    LIBSSH2_SFTP *sftp;
    LIBSSH2_SFTP_HANDLE *h;
    LIBSSH2_SFTP_ATTRIBUTES at;
    char name[512], longentry[512], path[1024], back[256];
    int n, count = 0;
    ssize_t got;

    sftp = libssh2_sftp_init(s);
    if (!sftp) { fail("sftp_init", s); return; }
    ok("sftp_init");
    n = libssh2_sftp_realpath(sftp, dir, path, sizeof path - 1);
    if (n < 0) { fail("sftp_realpath", s); libssh2_sftp_shutdown(sftp); return; }
    path[n] = 0;
    printf("SMOKE: realpath %s -> %s\n", dir, path);
    h = libssh2_sftp_opendir(sftp, path);
    if (!h) { fail("sftp_opendir", s); libssh2_sftp_shutdown(sftp); return; }
    while ((n = libssh2_sftp_readdir_ex(h, name, sizeof name, longentry, sizeof longentry, &at)) > 0) {
        if (count++ < 8) printf("SMOKE:   %s\n", longentry);
    }
    libssh2_sftp_closedir(h);
    printf("SMOKE: %d entries\n", count);
    ok("sftp_readdir");

    strcat(path, path[strlen(path) - 1] == '/' ? "" : "/");
    strcat(path, "ssh2_smoke.tmp");
    h = libssh2_sftp_open(sftp, path, LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC,
                          LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR);
    if (!h) { fail("sftp_open write", s); libssh2_sftp_shutdown(sftp); return; }
    got = libssh2_sftp_write(h, data, sizeof data - 1);
    libssh2_sftp_close(h);
    if (got != (ssize_t) (sizeof data - 1)) fail("sftp_write", s); else ok("sftp_write");

    h = libssh2_sftp_open(sftp, path, LIBSSH2_FXF_READ, 0);
    if (!h) { fail("sftp_open read", s); libssh2_sftp_shutdown(sftp); return; }
    got = 0;
    while ((n = (int) libssh2_sftp_read(h, back + got, sizeof back - 1 - got)) > 0) got += n;
    libssh2_sftp_close(h);
    back[got] = 0;
    if (got == (ssize_t) (sizeof data - 1) && memcmp(back, data, got) == 0) ok("sftp_read");
    else { printf("SMOKE: read back %d bytes\n", (int) got); fail("sftp_read", s); }

    if (libssh2_sftp_stat(sftp, path, &at) == 0)
        printf("SMOKE: stat size %lu perms %o\n", (unsigned long) at.filesize, (unsigned) at.permissions);
    if (libssh2_sftp_unlink(sftp, path) != 0) fail("sftp_unlink", s); else ok("sftp_unlink");
    libssh2_sftp_shutdown(sftp);
}

int main(int argc, char **argv)
{
    LIBSSH2_SESSION *s;
    const char *fp;
    char b64[64], *methods;
    int fd, type;
    size_t len;

    if (argc < 3) {
        printf("usage: ssh2_smoke host port [user [keyfile dir]]\n");
        exit(2);
    }
    printf("SMOKE: libssh2 %s\n", libssh2_version(0));
    if (libssh2_init(0) != 0) { fail("init", 0); exit(44); }
    fd = dial(argv[1], argv[2]);
    if (fd < 0) { printf("SMOKE: FAIL connect %s port %s\n", argv[1], argv[2]); exit(44); }
    ok("connect");
    s = libssh2_session_init();
    libssh2_session_set_blocking(s, 1);
    if (libssh2_session_handshake(s, fd) != 0) { fail("handshake", s); exit(44); }
    ok("handshake");
    printf("SMOKE: kex %s, hostkey %s, cipher %s, mac %s\n",
           libssh2_session_methods(s, LIBSSH2_METHOD_KEX),
           libssh2_session_methods(s, LIBSSH2_METHOD_HOSTKEY),
           libssh2_session_methods(s, LIBSSH2_METHOD_CRYPT_CS),
           libssh2_session_methods(s, LIBSSH2_METHOD_MAC_CS));
    fp = libssh2_hostkey_hash(s, LIBSSH2_HOSTKEY_HASH_SHA256);
    libssh2_session_hostkey(s, &len, &type);
    if (!fp) fail("hostkey_hash", s);
    else {
        base64((const unsigned char *) fp, 32, b64);
        printf("SMOKE: host key type %d, SHA256:%s\n", type, b64);
        ok("hostkey");
    }
    check_known(s, argv[1], atoi(argv[2]));

    if (argc >= 4) {
        methods = libssh2_userauth_list(s, argv[3], (unsigned int) strlen(argv[3]));
        printf("SMOKE: auth methods for %s: %s\n", argv[3], methods ? methods : "(none: authenticated)");
        ok("userauth_list");
    }
    if (argc >= 6) {
        if (libssh2_userauth_publickey_fromfile(s, argv[3], 0, argv[4], 0) != 0) fail("publickey", s);
        else {
            ok("publickey");
            sftp_steps(s, argv[5]);
        }
    }
    libssh2_session_disconnect(s, "smoke test done");
    libssh2_session_free(s);
    close(fd);
    libssh2_exit();
    printf("SMOKE: %s\n", fails ? "FAILED" : "PASSED");
    exit(fails ? 44 : 1);
}
