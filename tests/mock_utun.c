/* Test-only utun substitute: inherited datagram socket, real TCP unchanged. */
#include <sys/socket.h>
#include <sys/kern_control.h>
#include <sys/sys_domain.h>
#include <net/if_utun.h>
#include <sys/ioctl.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
static int mockfd = -1;
static int test_socket(int domain, int type, int protocol) {
 if (domain == PF_SYSTEM && protocol == SYSPROTO_CONTROL) {
  mockfd = dup(atoi(getenv("TEST_UTUN_FD"))); return mockfd;
 }
 return socket(domain,type,protocol);
}
static int test_ioctl(int fd, unsigned long req, ...) {
 va_list ap; void *arg; va_start(ap,req); arg=va_arg(ap,void*); va_end(ap);
 if(fd==mockfd && req==CTLIOCGINFO) { ((struct ctl_info*)arg)->ctl_id=123; return 0; }
 return ioctl(fd,req,arg);
}
static int test_connect(int fd, const struct sockaddr *addr, socklen_t len) {
 if(fd==mockfd) return 0;
 return connect(fd,addr,len);
}
static int test_getsockopt(int fd,int level,int opt,void *val,socklen_t *len) {
 if(fd==mockfd && level==SYSPROTO_CONTROL && opt==UTUN_OPT_IFNAME) {
  const char name[]="utun-test"; if(*len<sizeof(name)) return -1;
  memcpy(val,name,sizeof(name)); *len=sizeof(name); return 0;
 }
 return getsockopt(fd,level,opt,val,len);
}
#define INTERPOSE(new,old) __attribute__((used)) static struct { const void *replacement; const void *original; } pair_##old __attribute__((section("__DATA,__interpose"))) = {(const void*)new,(const void*)old};
INTERPOSE(test_socket,socket)
INTERPOSE(test_ioctl,ioctl)
INTERPOSE(test_connect,connect)
INTERPOSE(test_getsockopt,getsockopt)
