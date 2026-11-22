# Homebrew formula for ssocat - (SLIP-enhanced) socat
## How do I install this formula?
`brew tap gmerlino/ssocat` and then `brew install <formula>`.

Or install via URL (which will not receive updates):

```
brew install https://raw.githubusercontent.com/gmerlino/homebrew-ssocat/master/<formula>.rb
```

## Documentation
`brew help`, `man brew` or check [Homebrew's documentation](https://github.com/Homebrew/brew/tree/master/share/doc/homebrew#readme).

## SLIP over TCP on macOS

The formula patches the `feature/slip` fork to use macOS's built-in `utun`
interface. No third-party TUN kernel extension is needed. Both endpoints must
use SLIP framing; a plain TCP relay does not add it automatically.

### Two Macs

Choose an unused `utun` number on each machine (`ifconfig utun20` must report
that it does not exist). The two machines may use the same interface name.
Replace `SERVER_IP` with the server's existing LAN address. The tunnel subnet
below must not overlap a network already in use.

Server, first terminal (keep running):

```sh
sudo ssocat -d -d \
  TUN,tun-name=utun20,iff-no-pi,iff-slip \
  TCP-LISTEN:7777,bind=SERVER_IP,reuseaddr
```

Server, second terminal, after `created macOS interface utun20` appears:

```sh
sudo ifconfig utun20 inet 10.42.0.1 10.42.0.2 netmask 255.255.255.255 up
```

Client, first terminal (keep running):

```sh
sudo ssocat -d -d \
  TUN,tun-name=utun20,iff-no-pi,iff-slip \
  TCP:SERVER_IP:7777
```

Client, second terminal, after the interface has been created:

```sh
sudo ifconfig utun20 inet 10.42.0.2 10.42.0.1 netmask 255.255.255.255 up
ping 10.42.0.1
```

The commands establish a point-to-point IP tunnel. They do not change the
system default route or enable IP forwarding. Closing `ssocat` destroys its
utun interface and the associated interface routes. Use one process per tunnel;
do not add `fork` to share a single utun among multiple clients.

TCP here is unencrypted and unauthenticated; use a trusted network, or configure
ssocat's OpenSSL addresses and certificate verification for a secure transport.

On macOS, `TUN:address/prefix`, `tun-device`, `tun-type=tap`, and `iff-no-pi=0`
are rejected explicitly. Configure local and peer addresses with `ifconfig` as
above. If `tun-name` is omitted, macOS picks a free interface and `-d -d` logs
its name. The macOS four-byte address-family header is stripped/added locally;
only IP packets framed as SLIP are carried over TCP, matching Linux with
`iff-no-pi,iff-slip`.

### Validation

`brew test gmerlino/ssocat/ssocat` checks that OpenSSL, TUN and SLIP are available
and performs a local stream echo. It does not create a privileged interface.

The repository's `tests/run-macos-tests.sh SOURCE_TREE [BINARY]` runs packet
conversion tests and real localhost TCP tests using a test-only datagram socket
in place of the privileged utun socket. `SOURCE_TREE` must contain the patched,
configured and compiled source (including `libxio.a`); `BINARY` defaults to the
installed `ssocat`. The shim is built in a temporary directory and is never
installed. Tests cover IPv4/IPv6, SLIP escaping, split/coalesced TCP frames, and
two ssocat processes in both directions.

To check an actual kernel interface, run from this repository:

```sh
sudo /opt/homebrew/bin/python3 tests/test_real_utun.py
```

This test creates a temporary utun and an ICMP peer speaking SLIP over localhost
TCP, configures only `198.19.254.1 -> 198.19.254.2`, and sends three pings whose
payload includes SLIP special bytes. It refuses to run if that test subnet is
already visible in addresses or routes. The interface is closed on exit. Root
is required; a successful simulated test is not a substitute for this test.
