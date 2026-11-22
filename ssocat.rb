class Ssocat < Formula
  desc "(SLIP-enhanced) netcat on steroids"
  homepage "https://github.com/KostyaEsmukov/socat/tree/feature/slip"

  head "https://github.com/KostyaEsmukov/socat.git", :branch => "feature/slip"

  depends_on "autoconf" => :build
  depends_on "openssl@4"
  depends_on "readline"

  # OpenSSL 4 compatibility and a native macOS utun backend for SLIP.
  patch :DATA

  def install
    system "autoconf"
    system "./configure", "--prefix=#{prefix}", "--mandir=#{man}",
                           "--with-openssl=#{Formula["openssl@4"].opt_prefix}"
    inreplace "Makefile", "PROGS = socat procan filan", "PROGS = ssocat"
    inreplace "Makefile", "all: progs doc", "all: progs"
    inreplace "Makefile", "socat: socat.o libxio.a", "ssocat: socat.o libxio.a"
    system "make"
    bin.install "ssocat"
  end

  test do
    output = shell_output("#{bin}/ssocat -V")
    assert_match "#define WITH_OPENSSL 1", output
    assert_match "#define WITH_TUN 1", output
    assert_match "slip", shell_output("#{bin}/ssocat -hh")
    assert_equal "ssocat test\n", pipe_output("#{bin}/ssocat - EXEC:cat", "ssocat test\n", 0)
  end
end

__END__
diff --git a/configure.in b/configure.in
index 2b804d0..5b8e138 100644
--- a/configure.in
+++ b/configure.in
@@ -78,7 +78,7 @@ AC_CHECK_HEADERS(arpa/nameser.h)
 
 AC_HEADER_RESOLV()
 
-AC_CHECK_HEADERS(termios.h linux/if_tun.h)
+AC_CHECK_HEADERS(termios.h linux/if_tun.h net/if_utun.h)
 AC_CHECK_HEADERS(net/if_dl.h)
 AC_CHECK_HEADERS(linux/types.h)
 AC_CHECK_HEADER(linux/errqueue.h, AC_DEFINE(HAVE_LINUX_ERRQUEUE_H), [], [#include <sys/time.h>
@@ -665,8 +665,8 @@ AC_ARG_ENABLE(tun, [  --disable-tun           disable TUN/TAP support],
 	       [AC_MSG_RESULT(yes);    WITH_TUN=1 ])
 
 #
-if ! test "$ac_cv_header_linux_if_tun_h" = 'yes'; then
-  AC_MSG_WARN(include file linux/if_tun.h not found, disabling TUN)
+if test "$ac_cv_header_linux_if_tun_h" != 'yes' -a "$ac_cv_header_net_if_utun_h" != 'yes'; then
+  AC_MSG_WARN(neither linux/if_tun.h nor net/if_utun.h found, disabling TUN)
   WITH_TUN=
 fi
 #
diff --git a/sslcls.c b/sslcls.c
index 8964663..596d2b2 100644
--- a/sslcls.c
+++ b/sslcls.c
@@ -91,6 +91,7 @@ const SSL_METHOD *sycSSLv23_server_method(void) {
    return result;
 }
 
+#if OPENSSL_VERSION_MAJOR < 4
 const SSL_METHOD *sycTLSv1_client_method(void) {
    const SSL_METHOD *result;
    Debug("TLSv1_client_method()");
@@ -107,6 +108,8 @@ const SSL_METHOD *sycTLSv1_server_method(void) {
    return result;
 }
 
+#endif /* OPENSSL_VERSION_MAJOR < 4 */
+
 #if HAVE_TLSv1_1_client_method
 const SSL_METHOD *sycTLSv1_1_client_method(void) {
    const SSL_METHOD *result;
diff --git a/xio-openssl.c b/xio-openssl.c
index e931983..97bc4a9 100644
--- a/xio-openssl.c
+++ b/xio-openssl.c
@@ -806,7 +806,9 @@ int
 	    Error1("openssl-method=\"%s\": method unknown or not provided by library", me_str);
 	 }
       } else {
-#if   HAVE_SSLv23_client_method
+#if OPENSSL_VERSION_MAJOR >= 4
+	 method = TLS_client_method();
+#elif HAVE_SSLv23_client_method
 	 method = sycSSLv23_client_method();
 #elif HAVE_TLSv1_2_client_method
 	 method = sycTLSv1_2_client_method();
@@ -859,7 +861,9 @@ int
 	    Error1("openssl-method=\"%s\": method unknown or not provided by library", me_str);
 	 }
       } else {
-#if   HAVE_SSLv23_server_method
+#if OPENSSL_VERSION_MAJOR >= 4
+	 method = TLS_server_method();
+#elif HAVE_SSLv23_server_method
 	 method = sycSSLv23_server_method();
 #elif HAVE_TLSv1_2_server_method
 	 method = sycTLSv1_2_server_method();
diff --git a/xio-tun.c b/xio-tun.c
index 38d6045..9093033 100644
--- a/xio-tun.c
+++ b/xio-tun.c
@@ -35,11 +35,19 @@ const struct optdesc opt_iff_running     = { "iff-running",     "running",     O
 const struct optdesc opt_iff_noarp       = { "iff-noarp",       "noarp",       OPT_IFF_NOARP,       GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(para.tun.iff_opts), IFF_NOARP };
 const struct optdesc opt_iff_promisc     = { "iff-promisc",     "promisc",     OPT_IFF_PROMISC,     GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(para.tun.iff_opts), IFF_PROMISC };
 const struct optdesc opt_iff_allmulti    = { "iff-allmulti",    "allmulti",    OPT_IFF_ALLMULTI,    GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(para.tun.iff_opts), IFF_ALLMULTI };
+#ifdef IFF_MASTER
 const struct optdesc opt_iff_master      = { "iff-master",      "master",      OPT_IFF_MASTER,      GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(para.tun.iff_opts), IFF_MASTER };
+#endif
+#ifdef IFF_SLAVE
 const struct optdesc opt_iff_slave       = { "iff-slave",       "slave",       OPT_IFF_SLAVE,       GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(para.tun.iff_opts), IFF_SLAVE };
+#endif
 const struct optdesc opt_iff_multicast   = { "iff-multicast",   NULL,          OPT_IFF_MULTICAST,   GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(para.tun.iff_opts), IFF_MULTICAST };
+#ifdef IFF_PORTSEL
 const struct optdesc opt_iff_portsel     = { "iff-portsel",     "portsel",     OPT_IFF_PORTSEL,     GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(para.tun.iff_opts), IFF_PORTSEL };
+#endif
+#ifdef IFF_AUTOMEDIA
 const struct optdesc opt_iff_automedia   = { "iff-automedia",   "automedia",   OPT_IFF_AUTOMEDIA,   GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(para.tun.iff_opts), IFF_AUTOMEDIA };
+#endif
 /*const struct optdesc opt_iff_dynamic   = { "iff-dynamic",     "dynamic",     OPT_IFF_DYNAMIC,     GROUP_INTERFACE, PH_FD,   TYPE_BOOL,     OFUNC_OFFSET_MASKS, XIO_OFFSETOF(para.tun.iff_opts), XIO_SIZEOF(short), IFF_DYNAMIC };*/
 #if LATER
 const struct optdesc opt_route           = { "route",           NULL,          OPT_ROUTE,           GROUP_INTERFACE, PH_INIT, TYPE_STRING,   OFUNC_SPEC };
@@ -65,6 +73,9 @@ static const struct optname xio_route_options[] = {
 } ;
 #endif
 
+#ifdef __APPLE__
+#include "xio-tun-darwin.h"
+#else
 static int xioopen_tun(int argc, const char *argv[], struct opt *opts, int xioflags, xiofile_t *xfd, unsigned groups, int dummy1, int dummy2, int dummy3) {
    char *tundevice = NULL;
    char *tunname = NULL, *tuntype = NULL;
@@ -218,6 +229,8 @@ static int xioopen_tun(int argc, const char *argv[], struct opt *opts, int xiofl
    return 0;
 }
 
+#endif
+
 ssize_t _packet_len_from_ip_header(const uint8_t *buff, size_t bufsiz) {
    if (bufsiz < 4)
       return 0;
@@ -410,7 +423,11 @@ ssize_t xiowrite_tun(struct single *pipe, void *buff, size_t bufsiz) {
          Debug2("Partial packetwrite. %d out of %d", packet_len, bufsiz_packet);
       }
 
+#ifdef __APPLE__
+      ssize_t writt = xiowrite_utun_packet(pipe->fd, buff_packet, packet_len);
+#else
       ssize_t writt = writefull(pipe->fd, buff_packet, packet_len);
+#endif
       if (writt < 0) {
          int _errno = errno;
          switch (_errno) {
@@ -441,7 +458,11 @@ ssize_t xiowrite_tun(struct single *pipe, void *buff, size_t bufsiz) {
 ssize_t xioread_tun(struct single *pipe, uint8_t *buff, size_t bufsiz) {
    ssize_t bytes;
    do {
+#ifdef __APPLE__
+      bytes = xioread_utun_packet(pipe->fd, buff, bufsiz);
+#else
       bytes = Read(pipe->fd, buff, bufsiz);
+#endif
    } while (bytes < 0 && errno == EINTR);
 
    if (bytes < 0) {
diff --git a/xioopts.c b/xioopts.c
index e65f67a..7f2824a 100644
--- a/xioopts.c
+++ b/xioopts.c
@@ -174,7 +174,9 @@ const struct optname optionnames[] = {
 #ifdef IPV6_AUTHHDR
 	IF_IP6    ("authhdr",	&opt_ipv6_authhdr)
 #endif
+#ifdef IFF_AUTOMEDIA
 	IF_TUN    ("automedia",	&opt_iff_automedia)
+#endif
 #ifdef CBAUD
 	IF_TERMIOS("b0",	&opt_b0)
 #ifdef B1000000
@@ -581,21 +583,29 @@ const struct optname optionnames[] = {
 	IF_SOCKET ("if",	&opt_so_bindtodevice)
 #endif
 	IF_TUN    ("iff-allmulti",	&opt_iff_allmulti)
+#ifdef IFF_AUTOMEDIA
 	IF_TUN    ("iff-automedia",	&opt_iff_automedia)
+#endif
 	IF_TUN    ("iff-broadcast",	&opt_iff_broadcast)
 	IF_TUN    ("iff-debug",	&opt_iff_debug)
 	/*IF_TUN    ("iff-dynamic",	&opt_iff_dynamic)*/
 	IF_TUN    ("iff-loopback",	&opt_iff_loopback)
+#ifdef IFF_MASTER
 	IF_TUN    ("iff-master",	&opt_iff_master)
+#endif
 	IF_TUN    ("iff-multicast",	&opt_iff_multicast)
 	IF_TUN    ("iff-no-pi",	&opt_iff_no_pi)
 	IF_TUN    ("iff-noarp",	&opt_iff_noarp)
 	IF_TUN    ("iff-notrailers",	&opt_iff_notrailers)
 	IF_TUN    ("iff-pointopoint",	&opt_iff_pointopoint)
+#ifdef IFF_PORTSEL
 	IF_TUN    ("iff-portsel",	&opt_iff_portsel)
+#endif
 	IF_TUN    ("iff-promisc",	&opt_iff_promisc)
 	IF_TUN    ("iff-running",	&opt_iff_running)
+#ifdef IFF_SLAVE
 	IF_TUN    ("iff-slave",	&opt_iff_slave)
+#endif
 	IF_TUN    ("iff-slip",	&opt_iff_slip)
 	IF_TUN    ("iff-up",	&opt_iff_up)
 	IF_TERMIOS("ignbrk",	&opt_ignbrk)
@@ -867,7 +877,9 @@ const struct optname optionnames[] = {
 	IF_ANY    ("lseek64-end",	&opt_lseek64_end)
 	IF_ANY    ("lseek64-set",	&opt_lseek64_set)
 #endif
+#ifdef IFF_MASTER
 	IF_TUN    ("master",	&opt_iff_master)
+#endif
 	IF_LISTEN ("max-children",	&opt_max_children)
 	IF_LISTEN ("maxchildren",	&opt_max_children)
 #ifdef TCP_MAXSEG
@@ -1152,7 +1164,9 @@ const struct optname optionnames[] = {
 	IF_ANY    ("pop-all",	&opt_streams_i_pop_all)
 #endif
 	/*IF_IPAPP("port",	&opt_port)*/
+#ifdef IFF_PORTSEL
 	IF_TUN    ("portsel",	&opt_iff_portsel)
+#endif
 #if HAVE_RESOLV_H
 	IF_IP     ("primary",	&opt_res_primary)
 #endif /* HAVE_RESOLV_H */
@@ -1368,7 +1382,9 @@ const struct optname optionnames[] = {
 #ifdef SIOCSPGRP
 	IF_SOCKET ("siocspgrp",	&opt_siocspgrp)
 #endif
+#ifdef IFF_SLAVE
 	IF_TUN    ("slave",	&opt_iff_slave)
+#endif
 	IF_TUN    ("slip",	&opt_iff_slip)
 	IF_SOCKET ("sndbuf",	&opt_so_sndbuf)
 	IF_SOCKET ("sndbuf-late",	&opt_so_sndbuf_late)
diff --git a/xio-tun-darwin.h b/xio-tun-darwin.h
new file mode 100644
--- /dev/null
+++ b/xio-tun-darwin.h
@@ -0,0 +1,141 @@
+/* macOS utun backend. The stream carries raw IPv4/IPv6, optionally SLIP.
+ * The four-byte network-order address family belongs only to the utun socket.
+ * Published under the GNU General Public License V.2, see COPYING. */
+#include <sys/kern_control.h>
+#include <sys/sys_domain.h>
+#include <net/if_utun.h>
+
+static ssize_t xioread_utun_packet(int fd, uint8_t *buff, size_t size) {
+   uint32_t family;
+   struct iovec iov[2] = {{&family, sizeof(family)}, {buff, size}};
+   struct msghdr msg;
+   ssize_t n;
+   memset(&msg, 0, sizeof(msg));
+   msg.msg_iov = iov;
+   msg.msg_iovlen = 2;
+   n = recvmsg(fd, &msg, 0);
+   if (n < 0) return n;
+   if (n <= sizeof(family) || (msg.msg_flags & MSG_TRUNC)) {
+      errno = EMSGSIZE;
+      return -1;
+   }
+   family = ntohl(family);
+   if (!((family == AF_INET && (buff[0] >> 4) == 4) ||
+         (family == AF_INET6 && (buff[0] >> 4) == 6))) {
+      errno = EAFNOSUPPORT;
+      return -1;
+   }
+   return n - sizeof(family);
+}
+
+static ssize_t xiowrite_utun_packet(int fd, const uint8_t *buff, size_t size) {
+   uint32_t family;
+   struct iovec iov[2];
+   ssize_t n;
+   if (!size || ((buff[0] >> 4) != 4 && (buff[0] >> 4) != 6)) {
+      errno = EAFNOSUPPORT;
+      return -1;
+   }
+   family = htonl((buff[0] >> 4) == 4 ? AF_INET : AF_INET6);
+   iov[0].iov_base = &family;
+   iov[0].iov_len = sizeof(family);
+   iov[1].iov_base = (void *)buff;
+   iov[1].iov_len = size;
+   do { n = writev(fd, iov, 2); } while (n < 0 && errno == EINTR);
+   if (n < 0) return n;
+   if ((size_t)n != size + sizeof(family)) { errno = EIO; return -1; }
+   return size;
+}
+
+static int xioopen_tun(int argc, const char *argv[], struct opt *opts,
+                      int xioflags, xiofile_t *xfd, unsigned groups,
+                      int dummy1, int dummy2, int dummy3) {
+   struct ctl_info info;
+   struct sockaddr_ctl ctl;
+   struct ifreq ifr;
+   char *name = NULL, *type = NULL, *device = NULL, *end;
+   char ifname[IFNAMSIZ];
+   socklen_t namelen = sizeof(ifname);
+   unsigned long unit = 0;
+   bool no_pi = true, slip = false;
+   int fd = -1, sockfd = -1, result;
+
+   /* Address configuration is deliberately explicit on Darwin: use ifconfig
+    * with local AND peer addresses after this process has created utunN. */
+   if (argc != 1) {
+      Error("macOS TUN takes no address: configure utun with ifconfig local peer");
+      return STAT_NORETRY;
+   }
+   if (retropt_string(opts, OPT_TUN_DEVICE, &device) == 0) {
+      free(device);
+      Error("macOS utun does not accept tun-device");
+      return STAT_NORETRY;
+   }
+   if (retropt_string(opts, OPT_TUN_TYPE, &type) == 0) {
+      result = strcmp(type, "tun");
+      free(type);
+      if (result) { Error("macOS utun supports tun-type=tun only"); return STAT_NORETRY; }
+   }
+   retropt_bool(opts, OPT_IFF_NO_PI, &no_pi);
+   if (!no_pi) { Error("macOS utun requires iff-no-pi=1"); return STAT_NORETRY; }
+   retropt_bool(opts, OPT_IFF_SLIP, &slip);
+   if (retropt_string(opts, OPT_TUN_NAME, &name) == 0) {
+      if (strncmp(name, "utun", 4) || name[4] < '0' || name[4] > '9') {
+         free(name); Error("tun-name must be utun followed by a number"); return STAT_NORETRY;
+      }
+      errno = 0;
+      unit = strtoul(name + 4, &end, 10);
+      if (errno || *end || unit >= UINT32_MAX) {
+         free(name); Error("invalid utun interface number"); return STAT_NORETRY;
+      }
+      unit++;
+      free(name);
+   }
+   fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
+   if (fd < 0) goto fail;
+   memset(&info, 0, sizeof(info));
+   strncpy(info.ctl_name, UTUN_CONTROL_NAME, sizeof(info.ctl_name)-1);
+   if (ioctl(fd, CTLIOCGINFO, &info) < 0) goto fail;
+   memset(&ctl, 0, sizeof(ctl));
+   ctl.sc_len = sizeof(ctl);
+   ctl.sc_family = AF_SYSTEM;
+   ctl.ss_sysaddr = AF_SYS_CONTROL;
+   ctl.sc_id = info.ctl_id;
+   ctl.sc_unit = (uint32_t)unit;
+   if (connect(fd, (struct sockaddr *)&ctl, sizeof(ctl)) < 0) goto fail;
+   if (getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, ifname, &namelen) < 0) goto fail;
+   ifname[sizeof(ifname)-1] = '\0';
+   xfd->stream.fd = fd;
+   xfd->stream.dtype = XIODATA_TUN;
+   xfd->stream.para.tun.tuntype = XIOTUNTYPE_TUN;
+   xfd->stream.para.tun.no_pi = true;
+   xfd->stream.para.tun.slip = slip;
+   applyopts_single(&xfd->stream, opts, PH_FD);
+   if (xfd->stream.para.tun.iff_opts[0] || xfd->stream.para.tun.iff_opts[1]) {
+      sockfd = socket(AF_INET, SOCK_DGRAM, 0);
+      if (sockfd < 0) goto fail;
+      memset(&ifr, 0, sizeof(ifr));
+      strncpy(ifr.ifr_name, ifname, sizeof(ifr.ifr_name)-1);
+      if (ioctl(sockfd, SIOCGIFFLAGS, &ifr) < 0) goto fail;
+      ifr.ifr_flags |= xfd->stream.para.tun.iff_opts[0];
+      ifr.ifr_flags &= ~xfd->stream.para.tun.iff_opts[1];
+      if (ioctl(sockfd, SIOCSIFFLAGS, &ifr) < 0) goto fail;
+      close(sockfd); sockfd = -1;
+   }
+   applyopts(fd, opts, PH_FD);
+   applyopts_cloexec(fd, opts);
+   result = _xio_openlate(&xfd->stream, opts);
+   if (result < 0) { close(fd); xfd->stream.fd = -1; return result; }
+   Notice1("created macOS interface %s", ifname);
+   return STAT_OK;
+fail:
+   {
+      int saved_errno = errno;
+      if (sockfd >= 0) close(sockfd);
+      if (fd >= 0) close(fd);
+      xfd->stream.fd = -1;
+      errno = saved_errno;
+      Error1("creating/configuring macOS utun: %s", strerror(errno));
+   }
+   return STAT_NORETRY;
+}
