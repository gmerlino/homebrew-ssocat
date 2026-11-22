#include "xiosysincludes.h"
#include "xioopen.h"
#include "xio-tun.h"
#include <assert.h>

xiofile_t *sock1 = NULL;

int main(void) {
   int sv[2];
   struct single tun;
   uint8_t packet[64], wire[256], got[256], fragment[256];
   ssize_t n, encoded, consumed;
   int version;
   assert(socketpair(AF_UNIX, SOCK_DGRAM, 0, sv) == 0);
   memset(&tun, 0, sizeof(tun));
   tun.fd = sv[0]; tun.para.tun.slip = true; tun.para.tun.no_pi = true;
   for (version = 4; version <= 6; version += 2) {
      uint32_t family = htonl(version == 4 ? AF_INET : AF_INET6);
      memset(packet, 0, sizeof(packet));
      packet[0] = version == 4 ? 0x45 : 0x60;
      packet[2] = 0; packet[3] = sizeof(packet);
      packet[40] = 0xc0; packet[41] = 0xdb;
      memcpy(wire, &family, 4); memcpy(wire+4, packet, sizeof(packet));
      assert(send(sv[1], wire, sizeof(packet)+4, 0) == sizeof(packet)+4);
      encoded = xioread_tun(&tun, wire, sizeof(wire));
      assert(encoded == sizeof(packet)+3);
      assert(wire[encoded-1] == 0xc0);
      assert(wire[40] == 0xdb && wire[41] == 0xdc);
      assert(wire[42] == 0xdb && wire[43] == 0xdd);
      memcpy(fragment, wire, encoded);
      errno = 0;
      assert(xiowrite_tun(&tun, fragment, 41) == -1 && errno == EAGAIN);
      assert(memcmp(fragment, wire, encoded) == 0);
      consumed = xiowrite_tun(&tun, fragment, encoded);
      assert(consumed == encoded);
      n = recv(sv[1], got, sizeof(got), 0);
      assert(n == sizeof(packet)+4);
      assert(memcmp(got, &family, 4) == 0);
      assert(memcmp(got+4, packet, sizeof(packet)) == 0);
      /* Empty SLIP frame followed by two coalesced packets. */
      fragment[0] = 0xc0;
      memcpy(fragment+1, wire, encoded); memcpy(fragment+1+encoded, wire, encoded);
      assert(xiowrite_tun(&tun, fragment, 1+2*encoded) == 1+2*encoded);
      for (int i=0; i<2; i++) {
         assert(recv(sv[1], got, sizeof(got), 0) == sizeof(packet)+4);
         assert(memcmp(got+4, packet, sizeof(packet)) == 0);
      }
      printf("PASS IPv%d SLIP encode/decode, fragmented escape, coalesced frames, utun header\n", version);
   }
   close(sv[0]); close(sv[1]);
   return 0;
}
