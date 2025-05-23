/*
 * Copyright (c) 2001, Adam Dunkels.
 * Copyright (c) 2009, 2010 Joakim Eriksson, Niclas Finne, Dogan Yazar.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote
 *    products derived from this software without specific prior
 *    written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
 * GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * This file is part of the uIP TCP/IP stack.
 *
 *
 */

 /* Below define allows importing saved output into Wireshark as "Raw IP" packet type */
#define WIRESHARK_IMPORT_FORMAT 1

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>

#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/uio.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

#include <err.h>

#include "tools-utils.h"

#ifndef BAUDRATE
#define BAUDRATE B115200
#endif
speed_t b_rate = BAUDRATE;

int verbose = 2;
const char *ipaddr;
const char *netmask;
int slipfd = 0;
uint16_t basedelay=0,delaymsec=0;
uint32_t startsec,startmsec,delaystartsec,delaystartmsec;
int timestamp = 0, flowcontrol=0, showprogress=0, flowcontrol_xonxoff=0;

int ssystem(const char *fmt, ...)
     __attribute__((__format__ (__printf__, 1, 2)));
void write_to_serial(void *inbuf, int len);

void slip_send(unsigned char c);
void slip_send_char(unsigned char c);

#define PROGRESS(s) if(showprogress) fprintf(stderr, s)

char tundev[1024] = { "" };

/* IPv6 required minimum MTU */
#define MIN_DEVMTU 1500
int devmtu = MIN_DEVMTU;

int
ssystem(const char *fmt, ...) __attribute__((__format__ (__printf__, 1, 2)));

int
ssystem(const char *fmt, ...)
{
  char cmd[128];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(cmd, sizeof(cmd), fmt, ap);
  va_end(ap);
  printf("%s\n", cmd);
  fflush(stdout);
  return system(cmd);
}

#define SLIP_END      0300
#define SLIP_ESC      0333
#define SLIP_ESC_END  0334
#define SLIP_ESC_ESC  0335

#define SLIP_ESC_XON  0336
#define SLIP_ESC_XOFF 0337
#define XON           17
#define XOFF          19

/* get sockaddr, IPv4 or IPv6: */
void *
get_in_addr(struct sockaddr *sa)
{
  if(sa->sa_family == AF_INET) {
    return &(((struct sockaddr_in*)sa)->sin_addr);
  }
  return &(((struct sockaddr_in6*)sa)->sin6_addr);
}
void
stamptime(void)
{
  static long startsecs=0,startmsecs=0;
  long secs,msecs;
  struct timeval tv;
  time_t t;
  struct tm *tmp;
  char timec[20];

  gettimeofday(&tv, NULL) ;
  msecs=tv.tv_usec/1000;
  secs=tv.tv_sec;
  if (startsecs) {
    secs -=startsecs;
    msecs-=startmsecs;
    if (msecs<0) {secs--;msecs+=1000;}
    fprintf(stderr,"%04lu.%03lu ", secs, msecs);
  } else {
    startsecs=secs;
    startmsecs=msecs;
    t=time(NULL);
    tmp=localtime(&t);
    strftime(timec,sizeof(timec),"%T",tmp);
//    fprintf(stderr,"\n%s.%03lu ",timec,msecs);
    fprintf(stderr,"\n%s ",timec);
  }
}

int
is_sensible_string(const unsigned char *s, int len)
{
  int i;
  for(i = 1; i < len; i++) {
    if(s[i] == 0 || s[i] == '\r' || s[i] == '\n' || s[i] == '\t') {
      continue;
    } else if(s[i] < ' ' || '~' < s[i]) {
      return 0;
    }
  }

  /* Edge-case: printable characters in flow label */
  if(len >= 2 && (s[0] & 0xF0) == 0x60 
              && (s[1] == '\r' || s[1] == '\n' || s[1] == '\t')) {
    return 0;
  }

  return 1;
}

/*
 * Read from serial, when we have a packet write it to tun. No output
 * buffering, input buffered by stdio.
 */
void
serial_to_tun(FILE *inslip, int outfd)
{
  static union {
    unsigned char inbuf[2000];
  } uip;
  static int inbufptr = 0;
  int ret,i;
  unsigned char c;

#ifdef linux
  ret = fread(&c, 1, 1, inslip);
  if(ret == -1 || ret == 0) err(1, "serial_to_tun: read");
  goto after_fread;
#endif

 read_more:
  if(inbufptr >= sizeof(uip.inbuf)) {
     if(timestamp) stamptime();
     fprintf(stderr, "*** dropping large %d byte packet\n",inbufptr);
	 inbufptr = 0;
  }
  ret = fread(&c, 1, 1, inslip);
#ifdef linux
 after_fread:
#endif
  if(ret == -1) {
    err(1, "serial_to_tun: read");
  }
  if(ret == 0) {
    clearerr(inslip);
    return;
  }
  PROGRESS(".");
  switch(c) {
  case SLIP_END:
    if(inbufptr > 0) {
      if(uip.inbuf[0] == '!') {
	if(uip.inbuf[1] == 'M') {
	  /* Read gateway MAC address and autoconfigure tap0 interface */
	  char macs[24];
	  int i, pos;
	  for(i = 0, pos = 0; i < 16; i++) {
	    macs[pos++] = uip.inbuf[2 + i];
	    if((i & 1) == 1 && i < 14) {
	      macs[pos++] = ':';
	    }
	  }
          if(timestamp) stamptime();
	  macs[pos] = '\0';
//	  printf("*** Gateway's MAC address: %s\n", macs);
	  fprintf(stderr,"*** Gateway's MAC address: %s\n", macs);
          if (timestamp) stamptime();
	  ssystem("ifconfig %s down", tundev);
          if (timestamp) stamptime();
	  ssystem("ifconfig %s hw ether %s", tundev, &macs[6]);
          if (timestamp) stamptime();
	  ssystem("ifconfig %s up", tundev);
	}
      } else if(uip.inbuf[0] == '?') {
	if(uip.inbuf[1] == 'P') {
          /* Prefix info requested */
          struct in6_addr addr;
	  int i;
	  char *s = strchr(ipaddr, '/');
	  if(s != NULL) {
	    *s = '\0';
	  }
          inet_pton(AF_INET6, ipaddr, &addr);
          if(timestamp) stamptime();
          fprintf(stderr,"*** Address:%s => %02x%02x:%02x%02x:%02x%02x:%02x%02x\n",
		 ipaddr,
		 addr.s6_addr[0], addr.s6_addr[1],
		 addr.s6_addr[2], addr.s6_addr[3],
		 addr.s6_addr[4], addr.s6_addr[5],
		 addr.s6_addr[6], addr.s6_addr[7]);
	  slip_send('!');
	  slip_send('P');
	  for(i = 0; i < 8; i++) {
	    /* need to call the slip_send_char for stuffing */
	    slip_send_char(addr.s6_addr[i]);
	  }
	  slip_send(SLIP_END);
        }
#define DEBUG_LINE_MARKER '\r'
      } else if(uip.inbuf[0] == DEBUG_LINE_MARKER) {
	fwrite(uip.inbuf + 1, inbufptr - 1, 1, stdout);
      } else if(is_sensible_string(uip.inbuf, inbufptr)) {
        if(verbose==1) {   /* strings already echoed below for verbose>1 */
          if (timestamp) stamptime();
          fwrite(uip.inbuf, inbufptr, 1, stdout);
        }
      } else {
        if(verbose>2) {
          if (timestamp) stamptime();
          printf("Packet from SLIP of length %d - write TUN\n", inbufptr);
          if (verbose>4) {
#if WIRESHARK_IMPORT_FORMAT
            printf("0000");
	        for(i = 0; i < inbufptr; i++) printf(" %02x",uip.inbuf[i]);
#else
            printf("         ");
            for(i = 0; i < inbufptr; i++) {
              printf("%02x", uip.inbuf[i]);
              if((i & 3) == 3) printf(" ");
              if((i & 15) == 15) printf("\n         ");
            }
#endif
            printf("\n");
          }
        }

#ifdef __APPLE__
        /* Fake IFF_NO_PI on macOS by sending a 4 byte header containing AF_INET6 */
        u_int32_t type = htonl(AF_INET6);
        struct iovec iv[2];

        iv[0].iov_base = &type;
        iv[0].iov_len = sizeof(type);
        iv[1].iov_base = uip.inbuf;
        iv[1].iov_len = inbufptr;

        if(writev(outfd, iv, 2) != (sizeof(type) + inbufptr)) {
          err(1, "serial_to_tun: writev");
        }
#else
        if(write(outfd, uip.inbuf, inbufptr) != inbufptr) {
          err(1, "serial_to_tun: write");
        }
#endif

      }
      inbufptr = 0;
    }
    break;

  case SLIP_ESC:
    if(fread(&c, 1, 1, inslip) != 1) {
      clearerr(inslip);
      /* Put ESC back and give up! */
      ungetc(SLIP_ESC, inslip);
      return;
    }

    switch(c) {
    case SLIP_ESC_END:
      c = SLIP_END;
      break;
    case SLIP_ESC_ESC:
      c = SLIP_ESC;
      break;
    case SLIP_ESC_XON:
      c = XON;
      break;
    case SLIP_ESC_XOFF:
      c = XOFF;
      break;
    }
    /* FALLTHROUGH */
  default:
    uip.inbuf[inbufptr++] = c;

    /* Echo lines as they are received for verbose=2,3,5+ */
    /* Echo all printable characters for verbose==4 */
    if((verbose==2) || (verbose==3) || (verbose>4)) {
      if(c=='\n') {
        if(is_sensible_string(uip.inbuf, inbufptr)) {
          if (timestamp) stamptime();
          fwrite(uip.inbuf, inbufptr, 1, stdout);
          inbufptr=0;
        }
      }
    } else if(verbose==4) {
      if(c == 0 || c == '\r' || c == '\n' || c == '\t' || (c >= ' ' && c <= '~')) {
	fwrite(&c, 1, 1, stdout);
        if(c=='\n') if(timestamp) stamptime();
      }
    }

    break;
  }

  goto read_more;
}

unsigned char slip_buf[2000];
unsigned int slip_end, slip_begin;

void
slip_send_char(unsigned char c)
{
  switch(c) {
  case SLIP_END:
    slip_send(SLIP_ESC);
    slip_send(SLIP_ESC_END);
    break;
  case SLIP_ESC:
    slip_send(SLIP_ESC);
    slip_send(SLIP_ESC_ESC);
    break;
  case XON:
    if(flowcontrol_xonxoff) {
      slip_send(SLIP_ESC);
      slip_send(SLIP_ESC_XON);
    } else {
      slip_send(c);
    }
    break;
  case XOFF:
    if(flowcontrol_xonxoff) {
      slip_send(SLIP_ESC);
      slip_send(SLIP_ESC_XOFF);
    } else {
      slip_send(c);
    }
    break;
  default:
    slip_send(c);
    break;
  }
}

void
slip_send(unsigned char c)
{
  if(slip_end >= sizeof(slip_buf)) {
    err(1, "slip_send overflow");
  }
  slip_buf[slip_end] = c;
  slip_end++;
}

int
slip_empty()
{
  return slip_end == 0;
}

void
slip_flushbuf(int fd)
{
  int n;

  if(slip_empty()) {
    return;
  }

  n = write(fd, slip_buf + slip_begin, (slip_end - slip_begin));

  if(n == -1 && errno != EAGAIN) {
    err(1, "slip_flushbuf write failed");
  } else if(n == -1) {
    PROGRESS("Q");		/* Outqueueis full! */
  } else {
    slip_begin += n;
    if(slip_begin == slip_end) {
      slip_begin = slip_end = 0;
    }
  }
}

void
write_to_serial(void *inbuf, int len)
{
  u_int8_t *p = inbuf;
  int i;

  if(verbose>2) {
    if (timestamp) stamptime();
    printf("Packet from TUN of length %d - write SLIP\n", len);
    if (verbose>4) {
#if WIRESHARK_IMPORT_FORMAT
      printf("0000");
	  for(i = 0; i < len; i++) printf(" %02x", p[i]);
#else
      printf("         ");
      for(i = 0; i < len; i++) {
        printf("%02x", p[i]);
        if((i & 3) == 3) printf(" ");
        if((i & 15) == 15) printf("\n         ");
      }
#endif
      printf("\n");
    }
  }

  /* It would be ``nice'' to send a SLIP_END here but it's not
   * really necessary.
   */
  /* slip_send(SLIP_END); */

  for(i = 0; i < len; i++) {
    switch(p[i]) {
    case SLIP_END:
      slip_send(SLIP_ESC);
      slip_send(SLIP_ESC_END);
      break;
    case SLIP_ESC:
      slip_send(SLIP_ESC);
      slip_send(SLIP_ESC_ESC);
      break;
    case XON:
      if(flowcontrol_xonxoff) {
        slip_send(SLIP_ESC);
        slip_send(SLIP_ESC_XON);
      } else {
        slip_send(p[i]);
      }
      break;
    case XOFF:
      if(flowcontrol_xonxoff) {
        slip_send(SLIP_ESC);
        slip_send(SLIP_ESC_XOFF);
      } else {
        slip_send(p[i]);
      }
      break;
    default:
      slip_send(p[i]);
      break;
    }
  }
  slip_send(SLIP_END);
  PROGRESS("t");
}


/*
 * Read from tun, write to slip.
 */
int
tun_to_serial(int infd)
{
  struct {
    unsigned char inbuf[2000];
  } uip;
  int size;

  if((size = read(infd, uip.inbuf, 2000)) == -1) err(1, "tun_to_serial: read");
  
#ifdef __APPLE__
#define UTUN_HEADER_LEN 4
  /* Fake IFF_NO_PI on macOS by ignoring the first 4 bytes containing AF_INET6 */
  if(size <= UTUN_HEADER_LEN) err(1, "tun_to_serial: read too small");

  size -= UTUN_HEADER_LEN;
  write_to_serial(uip.inbuf + UTUN_HEADER_LEN, size);
#undef UTUN_HEADER_LEN
#else
  write_to_serial(uip.inbuf, size);
#endif
  return size;
}

void
stty_telos(int fd)
{
  struct termios tty;
  speed_t speed = b_rate;
  int i;

  if(tcflush(fd, TCIOFLUSH) == -1) err(1, "tcflush");

  if(tcgetattr(fd, &tty) == -1) err(1, "tcgetattr");

  cfmakeraw(&tty);

  /* Nonblocking read. */
  tty.c_cc[VTIME] = 0;
  tty.c_cc[VMIN] = 0;
  if (flowcontrol)
    tty.c_cflag |= CRTSCTS;
  else
    tty.c_cflag &= ~CRTSCTS;
  tty.c_iflag &= ~IXON;
  if(flowcontrol_xonxoff) {
    tty.c_iflag |= IXOFF | IXANY;
  } else {
    tty.c_iflag &= ~IXOFF & ~IXANY;
  }
  tty.c_cflag &= ~HUPCL;
  tty.c_cflag &= ~CLOCAL;

  cfsetispeed(&tty, speed);
  cfsetospeed(&tty, speed);

  if(tcsetattr(fd, TCSAFLUSH, &tty) == -1) err(1, "tcsetattr");

#if 1
  /* Nonblocking read and write. */
  /* if(fcntl(fd, F_SETFL, O_NONBLOCK) == -1) err(1, "fcntl"); */

  tty.c_cflag |= CLOCAL;
  if(tcsetattr(fd, TCSAFLUSH, &tty) == -1) err(1, "tcsetattr");

  i = TIOCM_DTR;
  if(ioctl(fd, TIOCMBIS, &i) == -1) err(1, "ioctl");
#endif

  usleep(10*1000);		/* Wait for hardware 10ms. */

  /* Flush input and output buffers. */
  if(tcflush(fd, TCIOFLUSH) == -1) err(1, "tcflush");
}

int
devopen(const char *dev, int flags)
{
  char t[1024];
  strcpy(t, "/dev/");
  strncat(t, dev, sizeof(t) - 5);
  return open(t, flags);
}

#ifdef linux
#include <linux/if.h>
#include <linux/if_tun.h>

int
tun_alloc(char *dev, int tap)
{
  struct ifreq ifr;
  int fd, err;

  if( (fd = open("/dev/net/tun", O_RDWR)) < 0 ) {
    perror("can not open /dev/net/tun");
    return -1;
  }

  memset(&ifr, 0, sizeof(ifr));

  /* Flags: IFF_TUN   - TUN device (no Ethernet headers)
   *        IFF_TAP   - TAP device
   *
   *        IFF_NO_PI - Do not provide packet information
   */
  ifr.ifr_flags = (tap ? IFF_TAP : IFF_TUN) | IFF_NO_PI;
  if(*dev != 0) {
    strncpy(ifr.ifr_name, dev, sizeof(ifr.ifr_name) - 1);
    ifr.ifr_name[sizeof(ifr.ifr_name) - 1] = '\0';
  }

  if((err = ioctl(fd, TUNSETIFF, (void *) &ifr)) < 0 ) {
    close(fd);
    fprintf(stderr, "can not tunsetiff to %s (flags=%08x): %s\n", dev, ifr.ifr_flags,
            strerror(errno));
    return err;
  }

  /* get resulting tunnel name */
  strcpy(dev, ifr.ifr_name);
  return fd;
}

#elif defined __APPLE__
#include <sys/sys_domain.h>
#include <sys/kern_control.h>
#include <net/if_utun.h>

/* 
 * Reference for utun on macOS:
 * http://newosxbook.com/src.jl?tree=listings&file=17-15-utun.c 
 */
int
tun_alloc(char *dev, int tap)
{
  struct sockaddr_ctl sc;
  struct ctl_info ctlInfo;
  int fd;
  unsigned int tunif;

  if(tap) {
    err(1, "tun_alloc: TAP is not supported with utun on macOS");
    return -1;
  }

  if(sscanf(dev, "utun%u", &tunif) != 1 || tunif >= UINT8_MAX) {
    err(1, "tun_alloc: invalid utun interface specified");
    return -1;
  }

  memset(&ctlInfo, 0, sizeof(ctlInfo));
  if(strlcpy(ctlInfo.ctl_name, UTUN_CONTROL_NAME, sizeof(ctlInfo.ctl_name)) >=
      sizeof(ctlInfo.ctl_name)) {
    fprintf(stderr, "UTUN_CONTROL_NAME too long");
    return -1;
  }

  fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
   
  if(fd == -1) {
    perror("socket(SYSPROTO_CONTROL)");
    return -1;
  }

  if(ioctl(fd, CTLIOCGINFO, &ctlInfo) == -1) {
    perror("ioctl(CTLIOCGINFO)");
    close(fd);
    return -1;
  }

  sc.sc_id = ctlInfo.ctl_id;
  sc.sc_len = sizeof(sc);
  sc.sc_family = AF_SYSTEM;
  sc.ss_sysaddr = AF_SYS_CONTROL;
  sc.sc_unit = tunif + 1;

  /*
   * If the connect is successful, a utun%d device will be created, where "%d"
   * is our unit number -1
   */

  if(connect(fd, (struct sockaddr *)&sc, sizeof(sc)) == -1) {
    perror("connect(AF_SYS_CONTROL)");
    close(fd);
    return -1;
  }

  return fd;
}
#else
int
tun_alloc(char *dev, int tap)
{
  return devopen(dev, O_RDWR);
}
#endif

void
cleanup(void)
{
#ifndef __APPLE__
  if (timestamp) stamptime();
  ssystem("ip -6 route | grep %s", tundev);
  if (timestamp) stamptime();
  ssystem("ip link set dev %s down", tundev);
#ifndef linux
  ssystem("sysctl -w net.ipv6.conf.all.forwarding=1");
#endif
  if (timestamp) stamptime();
  ssystem("ip -6 route | grep %s", tundev);
#else
  // __APPLE__
  {
    if (timestamp) stamptime();
    ssystem("ifconfig %s inet6 %s remove", tundev, ipaddr);
    if (timestamp) stamptime();
    ssystem("ifconfig %s down", tundev);
  }
#endif
}

void
sigcleanup(int signo)
{
  fprintf(stderr, "signal %d\n", signo);
  exit(0);			/* exit(0) will call cleanup() */
}

static int got_sigalarm;

void
sigalarm(int signo)
{
  got_sigalarm = 1;
  return;
}

void
sigalarm_reset()
{
#ifdef linux
#define TIMEOUT (997*1000)
#else
#define TIMEOUT (2451*1000)
#endif
  ualarm(TIMEOUT, TIMEOUT);
  got_sigalarm = 0;
}

void
ifconf(const char *tundev, const char *ipaddr)
{
#ifdef linux
  if (timestamp) stamptime();
  ssystem("ip link set dev %s up", tundev);
  if (timestamp) stamptime();
  ssystem("ip link set mtu %d dev %s", devmtu, tundev);
  if (timestamp) stamptime();
  ssystem("ip a add %s dev %s", ipaddr, tundev);

/* radvd needs a link local address for routing */
#if 0
/* fe80::1/64 is good enough */
  ssystem("ifconfig %s add fe80::1/64", tundev);
#elif 1
/* Generate a link local address a la sixxs/aiccu */
/* First a full parse, stripping off the prefix length */
  {
    char lladdr[40];
    char c, *ptr=(char *)ipaddr;
    uint16_t digit,ai,a[8],cc,scc,i;
    for(ai=0; ai<8; ai++) {
      a[ai]=0;
    }
    ai=0;
    cc=scc=0;
    while((c=*ptr++) != 0) {
      if(c=='/') break;
      if(c==':') {
	if(cc)
	  scc = ai;
	cc = 1;
	if(++ai>7) break;
      } else {
	cc=0;
	digit = c-'0';
	if (digit > 9)
	  digit = 10 + (c & 0xdf) - 'A';
	a[ai] = (a[ai] << 4) + digit;
      }
    }
    /* Get # elided and shift what's after to the end */
    cc=8-ai;
    for(i=0;i<cc;i++) {
      if ((8-i-cc) <= scc) {
	a[7-i] = 0;
      } else {
	a[7-i] = a[8-i-cc];
	a[8-i-cc]=0;
      }
    }
    sprintf(lladdr,"fe80::%x:%x:%x:%x",a[1]&0xfefd,a[2],a[3],a[7]);
    if (timestamp) stamptime();
    ssystem("ip a add %s/64 dev %s", lladdr, tundev);
  }
#endif /* link local */
#elif defined(__APPLE__)
  {
	char * itfaddr = strdup(ipaddr);
	char * prefix = index(itfaddr, '/');
	if ( prefix != NULL ) {
		*prefix = '\0';
		prefix++;
	} else {
		prefix = "64";
	}
    if (timestamp) stamptime();
    ssystem("ifconfig %s inet6 mtu %d up", tundev, devmtu);
    if (timestamp) stamptime();
    ssystem("ifconfig %s inet6 %s add", tundev, ipaddr );
    if (timestamp) stamptime();
    ssystem("sysctl -w net.inet6.ip6.forwarding=1");
    free(itfaddr);
  }
#else
 // Not linux and not __APPLE__
  if (timestamp) stamptime();
  ssystem("ifconfig %s inet `hostname` %s mtu %d up", tundev, ipaddr, devmtu);
  if (timestamp) stamptime();
  ssystem("sysctl -w net.inet.ip.forwarding=1");
#endif /* !linux */

  if (timestamp) stamptime();
  ssystem("ip link show %s\n", tundev);
}

int
main(int argc, char **argv)
{
  int c;
  int tunfd, maxfd;
  int ret;
  fd_set rset, wset;
  FILE *inslip;
  const char *siodev = NULL;
  const char *host = NULL;
  const char *port = NULL;
  const char *prog;
  int baudrate = -2;
  int ipa_enable = 0;
  int tap = 0;
  slipfd = 0;

  prog = argv[0];
  setvbuf(stdout, NULL, _IOLBF, 0); /* Line buffered output. */

  while((c = getopt(argc, argv, "B:HILPhXM:s:t:v::d::a:p:T")) != -1) {
    switch(c) {
    case 'B':
      baudrate = atoi(optarg);
      break;

    case 'H':
      flowcontrol=1;
      break;

    case 'X':
      flowcontrol_xonxoff=1;
      break;

    case 'L':
      timestamp=1;
      break;

    case 'M':
      devmtu=atoi(optarg);
      if(devmtu > MIN_DEVMTU) {
        devmtu = MIN_DEVMTU;
      }
      break;

    case 'P':
      showprogress=1;
      break;

    case 's':
      if(strncmp("/dev/", optarg, 5) == 0) {
        siodev = optarg + 5;
      } else {
        siodev = optarg;
      }
      break;

    case 'I':
      ipa_enable = 1;
      fprintf(stderr, "Will inquire about IP address using IPA=\n");
      break;

    case 't':
      if(strncmp("/dev/", optarg, 5) == 0) {
        strncpy(tundev, optarg + 5, sizeof(tundev) - 1);
      } else {
        strncpy(tundev, optarg, sizeof(tundev) - 1);
      }
      tundev[sizeof(tundev) - 1] = '\0';
      break;

    case 'a':
      host = optarg;
      break;

    case 'p':
      port = optarg;
      break;

    case 'd':
      basedelay = 10;
      if (optarg) basedelay = atoi(optarg);
      break;

    case 'v':
      verbose = 2;
      if (optarg) verbose = atoi(optarg);
      break;

#ifndef __APPLE__
    case 'T':
      tap = 1;
      break;
#endif

    case '?':
    case 'h':
    default:
fprintf(stderr,"usage:  %s [options] ipaddress\n", prog);
fprintf(stderr,"example: tunslip6 -L -v2 -s ttyUSB1 fd00::1/64\n");
fprintf(stderr,"Options are:\n");
#ifndef __APPLE__
fprintf(stderr," -B baudrate    9600,19200,38400,57600,115200 (default),230400,460800,921600\n");
#else
fprintf(stderr," -B baudrate    9600,19200,38400,57600,115200 (default),230400\n");
#endif
fprintf(stderr, " -P             Show progress\n");
fprintf(stderr, " -H             Hardware CTS/RTS flow control (default disabled)\n");
fprintf(stderr, " -I             Inquire IP address\n");
fprintf(stderr, " -X             Software XON/XOFF flow control (default disabled)\n");
fprintf(stderr, " -L             Log output format (adds time stamps)\n");
fprintf(stderr, " -s siodev      Serial device (default /dev/ttyUSB0)\n");
fprintf(stderr, " -M             Interface MTU (default and min: 1280)\n");
#ifdef __APPLE__
fprintf(stderr, " -t tundev      Name of interface (default utun10)\n");
#else
fprintf(stderr, " -T             Make tap interface (default is tun interface)\n");
fprintf(stderr, " -t tundev      Name of interface (default tap0 or tun0)\n");
#endif
#ifdef __APPLE__
fprintf(stderr, " -v level       Verbosity level\n");
#else
fprintf(stderr, " -v[level]      Verbosity level\n");
#endif
fprintf(stderr, "    -v0         No messages\n");
fprintf(stderr, "    -v1         Encapsulated SLIP debug messages\n");
fprintf(stderr, "    -v2         Printable strings after they are received (default)\n");
fprintf(stderr, "    -v3         Printable strings and SLIP packet notifications\n");
fprintf(stderr, "    -v4         All printable characters as they are received\n");
fprintf(stderr, "    -v5         All SLIP packets in hex\n");
#ifndef __APPLE__
fprintf(stderr, "    -v          Equivalent to -v2\n");
#endif
#ifdef __APPLE__
fprintf(stderr, " -d basedelay   Minimum delay between outgoing SLIP packets.\n");
#else
fprintf(stderr, " -d[basedelay]  Minimum delay between outgoing SLIP packets.\n");
#endif
fprintf(stderr, "                Actual delay is basedelay*(#6LowPAN fragments) milliseconds.\n");
#ifndef __APPLE__
fprintf(stderr, "                -d is equivalent to -d10.\n");
#endif
fprintf(stderr, " -a serveraddr  \n");
fprintf(stderr, " -p serverport  \n");
exit(1);
      break;
    }
  }
  argc -= (optind - 1);
  argv += (optind - 1);

  if(argc != 2 && argc != 3) {
    err(1, "usage: %s [-B baudrate] [-P] [-H] [-I] [-X] [-L] [-s siodev] [-M] [-T] [-t tundev] "
#ifdef __APPLE__
           "[-v level] [-d basedelay] "
#else
           "[-v [level]] [-d [basedelay]] "
#endif
           "[-a serveraddr] [-p serverport] ipaddress", prog);
  }
  ipaddr = argv[1];

  if(baudrate != -2) { /* -2: use default baudrate */
    b_rate = select_baudrate(baudrate);
    if(b_rate == 0) {
      err(1, "unknown baudrate %d", baudrate);
    }
  }

#ifdef __APPLE__
  if(*tundev == '\0') {
    /* utun0-3 are in use on Big Sur, so use utun10 as default */

    strcpy(tundev, "utun10");
  }
#endif

  if(host != NULL) {
    struct addrinfo hints, *servinfo, *p;
    int rv;
    char s[INET6_ADDRSTRLEN];

    if(port == NULL) {
      port = "60001";
    }

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    if((rv = getaddrinfo(host, port, &hints, &servinfo)) != 0) {
      err(1, "getaddrinfo: %s", gai_strerror(rv));
    }

    /* loop through all the results and connect to the first we can */
    for(p = servinfo; p != NULL; p = p->ai_next) {
      if((slipfd = socket(p->ai_family, p->ai_socktype,
                          p->ai_protocol)) == -1) {
        perror("client: socket");
        continue;
      }

      if(connect(slipfd, p->ai_addr, p->ai_addrlen) == -1) {
        perror("client: connect");
        close(slipfd);
        continue;
      }
      break;
    }

    if(p == NULL) {
      err(1, "can't connect to ``%s:%s''", host, port);
    }

    fcntl(slipfd, F_SETFL, O_NONBLOCK);

    inet_ntop(p->ai_family, get_in_addr((struct sockaddr *)p->ai_addr),
              s, sizeof(s));
    fprintf(stderr, "slip connected to ``%s:%s''\n", s, port);

    /* all done with this structure */
    freeaddrinfo(servinfo);

  } else {
    if(siodev != NULL) {
      slipfd = devopen(siodev, O_RDWR | O_NONBLOCK);
      if(slipfd == -1) {
	err(1, "can't open siodev ``/dev/%s''", siodev);
      }
    } else {
      static const char *siodevs[] = {
        "ttyUSB0", "cuaU0", "ucom0" /* linux, fbsd6, fbsd5 */
      };
      int i;
      for(i = 0; i < 3; i++) {
        siodev = siodevs[i];
        slipfd = devopen(siodev, O_RDWR | O_NONBLOCK);
        if(slipfd != -1) {
          break;
        }
      }
      if(slipfd == -1) {
        err(1, "can't open siodev");
      }
    }
    if (timestamp) stamptime();
    fprintf(stderr, "********SLIP started on ``/dev/%s''\n", siodev);
    stty_telos(slipfd);
  }
  slip_send(SLIP_END);
  inslip = fdopen(slipfd, "r");
  if(inslip == NULL) err(1, "main: fdopen");

  tunfd = tun_alloc(tundev, tap);
  if(tunfd == -1) err(1, "main: open /dev/tun");
  if (timestamp) stamptime();
  fprintf(stderr, "opened %s device ``/dev/%s''\n",
          tap ? "tap" : "tun", tundev);

  atexit(cleanup);
  signal(SIGHUP, sigcleanup);
  signal(SIGTERM, sigcleanup);
  signal(SIGINT, sigcleanup);
  signal(SIGALRM, sigalarm);
  ifconf(tundev, ipaddr);

  while(1) {
    maxfd = 0;
    FD_ZERO(&rset);
    FD_ZERO(&wset);

    if(got_sigalarm && ipa_enable) {
      /* Send "?IPA". */
      slip_send('?');
      slip_send('I');
      slip_send('P');
      slip_send('A');
      slip_send(SLIP_END);
      got_sigalarm = 0;
    }

    if(!slip_empty()) {		/* Anything to flush? */
      FD_SET(slipfd, &wset);
    }

    FD_SET(slipfd, &rset);	/* Read from slip ASAP! */
    if(slipfd > maxfd) maxfd = slipfd;

    /* We only have one packet at a time queued for slip output. */
    if(slip_empty()) {
      FD_SET(tunfd, &rset);
      if(tunfd > maxfd) maxfd = tunfd;
    }

    ret = select(maxfd + 1, &rset, &wset, NULL, NULL);
    if(ret == -1 && errno != EINTR) {
      err(1, "select");
    } else if(ret > 0) {
      if(FD_ISSET(slipfd, &rset)) {
        serial_to_tun(inslip, tunfd);
      }

      if(FD_ISSET(slipfd, &wset)) {
	slip_flushbuf(slipfd);
	if(ipa_enable) sigalarm_reset();
      }

      /* Optional delay between outgoing packets */
      /* Base delay times number of 6lowpan fragments to be sent */
      if(delaymsec) {
       struct timeval tv;
       int dmsec;
       gettimeofday(&tv, NULL) ;
       dmsec=(tv.tv_sec-delaystartsec)*1000+tv.tv_usec/1000-delaystartmsec;
       if(dmsec<0) delaymsec=0;
       if(dmsec>delaymsec) delaymsec=0;
      }
      if(delaymsec==0) {
        if(slip_empty() && FD_ISSET(tunfd, &rset)) {
          tun_to_serial(tunfd);
          slip_flushbuf(slipfd);
          if(ipa_enable) sigalarm_reset();
          if(basedelay) {
            struct timeval tv;
            gettimeofday(&tv, NULL) ;
 //         delaymsec=basedelay*(1+(size/120));//multiply by # of 6lowpan packets?
            delaymsec=basedelay;
            delaystartsec =tv.tv_sec;
            delaystartmsec=tv.tv_usec/1000;
          }
        }
      }
    }
  }
}
