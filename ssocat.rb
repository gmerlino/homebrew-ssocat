class Ssocat < Formula
  desc "(SLIP-enhanced) netcat on steroids"
  homepage "https://github.com/KostyaEsmukov/socat/tree/feature/slip"

  head "https://github.com/KostyaEsmukov/socat.git", :branch => "feature/slip"

  depends_on "autoconf" => :build
  depends_on "openssl@4"
  depends_on "readline"

  # Compatibility with OpenSSL 4 for the feature/slip fork.
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
    if output.include?("#define WITH_TUN 1")
      assert_match "iff-slip", shell_output("#{bin}/ssocat -hh")
    end
    assert_equal "ssocat test\n", pipe_output("#{bin}/ssocat - EXEC:cat", "ssocat test\n", 0)
  end
end

__END__
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
