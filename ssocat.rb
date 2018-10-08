class Ssocat < Formula
  desc "(SLIP-enhanced) netcat on steroids"
  homepage "https://github.com/KostyaEsmukov/socat/tree/feature/slip"

  head "https://github.com/KostyaEsmukov/socat.git", :branch => "feature/slip"

  depends_on "autoconf" => :build
  depends_on "openssl@1.1"
  depends_on "readline"

  def install
    system "autoconf"
    system "./configure", "--prefix=#{prefix}", "--mandir=#{man}"
    inreplace "Makefile", "PROGS = socat procan filan", "PROGS = ssocat"
    inreplace "Makefile", "all: progs doc", "all: progs"
    inreplace "Makefile", "socat: socat.o libxio.a", "ssocat: socat.o libxio.a"
    system "make"
    bin.install "ssocat"
  end

  test do
    output = pipe_output("#{bin}/socat - tcp:www.google.com:80", "GET / HTTP/1.0\r\n\r\n")
    assert_match "HTTP/1.0", output.lines.first
  end
end
