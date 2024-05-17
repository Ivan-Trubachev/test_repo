#define _GNU_SOURCE
/*---------------------------------------------------------------------------*/
#include "tools-utils.h"

#include <stdio.h>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#include <errno.h>
#include <sys/time.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <signal.h>
/*---------------------------------------------------------------------------*/
#define BAUDRATE B115200
#define BAUDRATE_S "115200"

speed_t b_rate = BAUDRATE;
/*---------------------------------------------------------------------------*/
#ifdef linux
#define MODEMDEVICE "/dev/ttyS0"
#else
#define MODEMDEVICE "/dev/com1"
#endif /* linux */
/*---------------------------------------------------------------------------*/
#define SLIP_END      0300
#define SLIP_ESC      0333
#define SLIP_ESC_END  0334
#define SLIP_ESC_ESC  0335

#define SLIP_ESC_XON  0336
#define SLIP_ESC_XOFF 0337
#define XON           17
#define XOFF          19

#define CSNA_INIT     0x01

#define BUFSIZE         40
#define HCOLS           20
#define ICOLS           18

#define MODE_START_DATE  0
#define MODE_DATE        1
#define MODE_START_TEXT  2
#define MODE_TEXT        3
#define MODE_INT         4
#define MODE_HEX         5
#define MODE_SLIP_AUTO   6
#define MODE_SLIP        7
#define MODE_SLIP_HIDE   8

#define MODE_SEND_REQUEST_NONE  0
#define MODE_SEND_REQUEST       1
/*---------------------------------------------------------------------------*/
#ifndef O_SYNC
#define O_SYNC 0
#endif

#define OPEN_FLAGS (O_RDWR | O_NOCTTY | O_NDELAY | O_SYNC)
/*---------------------------------------------------------------------------*/
static unsigned char rxbuf[2048];
static unsigned char slip_buf[2000];
static int slip_end, slip_begin;
static int flowcontrol=0, flowcontrol_xonxoff=0;
/*---------------------------------------------------------------------------*/
static int
usage(int result)
{
  printf("Usage: slipcmd [-bSPEED] [-H] [-X] [-sn] [-Rr] [SERIALDEVICE]\n");
  printf("       -sn to hide SLIP packages\n");
  printf("       -b baudrate  115200 (default),230400,460800,921600\n");
  printf("       -H  hardware CTS/RTS flow control (default disabled)\n");
  printf("       -X  software XON/XOFF flow control (default disabled)\n");
  printf("       -Rr send SLIP request r\n");
  return result;
}
/*---------------------------------------------------------------------------*/
void
slip_send(int fd, unsigned char c)
{
  if(slip_end >= sizeof(slip_buf)) {
    perror("slip_send overflow");
  }
  slip_buf[slip_end] = c;
  slip_end++;
}
/*---------------------------------------------------------------------------*/
void
slip_send_char(int fd, unsigned char c)
{
  switch(c) {
  case SLIP_END:
    slip_send(fd, SLIP_ESC);
    slip_send(fd, SLIP_ESC_END);
    break;
  case SLIP_ESC:
    slip_send(fd, SLIP_ESC);
    slip_send(fd, SLIP_ESC_ESC);
    break;
  case XON:
    if(flowcontrol_xonxoff) {
      slip_send(fd, SLIP_ESC);
      slip_send(fd, SLIP_ESC_XON);
    } else {
      slip_send(fd, c);
    }
    break;
  case XOFF:
    if(flowcontrol_xonxoff) {
      slip_send(fd, SLIP_ESC);
      slip_send(fd, SLIP_ESC_XOFF);
    } else {
      slip_send(fd, c);
    }
    break;
  default:
    slip_send(fd, c);
    break;
  }
}
/*---------------------------------------------------------------------------*/
int
slip_empty()
{
  return slip_end == 0;
}
/*---------------------------------------------------------------------------*/
void
slip_flushbuf(int fd)
{
  int n;

  if(slip_empty()) {
    return;
  }

  n = write(fd, slip_buf + slip_begin, (slip_end - slip_begin));

  if(n == -1 && errno != EAGAIN) {
    perror("slip_flushbuf write failed");
  } else if(n == -1) {
    perror("out queue is full!");
  } else {
    slip_begin += n;
    if(slip_begin == slip_end) {
      slip_begin = slip_end = 0;
    }
  }
}
/*---------------------------------------------------------------------------*/
static void
intHandler(int sig)
{
  exit(0);
}
/*---------------------------------------------------------------------------*/
int
main(int argc, char **argv)
{
  signal(SIGINT, intHandler);

  struct termios options;
  fd_set mask, smask;
  int fd;
  int baudrate = BUNKNOWN;
  char *device = MODEMDEVICE;
  unsigned char buf[BUFSIZE];
  unsigned char mode = MODE_START_TEXT;
  unsigned char rmode = MODE_SEND_REQUEST_NONE;
  char *request = NULL;
  int nfound, flags = 0;
  unsigned char lastc = '\0';

  int index = 1;
  while(index < argc) {
    if(argv[index][0] == '-') {
      switch(argv[index][1]) {
      case 'b':
        baudrate = atoi(&argv[index][2]);
        break;
      case 's':
        switch(argv[index][2]) {
        case 'n':
          mode = MODE_SLIP_HIDE;
          break;   
        }
        break;
      case 'H':
      	flowcontrol=1;
      break;
      case 'X':
      	flowcontrol_xonxoff=1;
      break;
      case 'R':
        if(strlen(&argv[index][2])) {
          request = &argv[index][2];
        } 
        rmode = MODE_SEND_REQUEST;
        break;  
      case 'h':
        return usage(0);
      default:
        fprintf(stderr, "unknown option '%c'\n", argv[index][1]);
        return usage(1);
      }
      index++;
    } else {
      device = argv[index++];
      if(index < argc) {
        fprintf(stderr, "too many arguments\n");
        return usage(1);
      }
    }
  }

  if(baudrate != BUNKNOWN) {
    b_rate = select_baudrate(baudrate);
    if(b_rate == 0) {
      fprintf(stderr, "unknown baudrate %d\n", baudrate);
      exit(-1);
    }
  }

  /* minimize trace in hidden mode */
  if (mode != MODE_SLIP_HIDE) {
    fprintf(stderr, "connecting to %s", device);
  }

  fd = open(device, OPEN_FLAGS);

  if(fd < 0) {
    fprintf(stderr, "\n");
    perror("open");
    exit(-1);
  }

  /* minimize trace in hidden mode */
  if (mode != MODE_SLIP_HIDE) {
    fprintf(stderr, " [OK]\n");
  }

  if(fcntl(fd, F_SETFL, 0) < 0) {
    perror("could not set fcntl");
    exit(-1);
  }

  if(tcgetattr(fd, &options) < 0) {
    perror("could not get options");
    exit(-1);
  }

  cfsetispeed(&options, b_rate);
  cfsetospeed(&options, b_rate);

  /* Enable the receiver and set local mode */
  options.c_cflag |= (CLOCAL | CREAD);
  /* Mask the character size bits and turn off (odd) parity */
  options.c_cflag &= ~(CSIZE | PARENB | PARODD);
  /* Select 8 data bits */
  options.c_cflag |= CS8;

  /* Raw input */
  options.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP
                       | INLCR | IGNCR | ICRNL | IXON);
  options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
  /* Raw output */
  options.c_oflag &= ~OPOST;
  
  /* Flow control */
  if(flowcontrol)
    options.c_cflag |= CRTSCTS;
  else
    options.c_cflag &= ~CRTSCTS;
  options.c_iflag &= ~IXON;
  if(flowcontrol_xonxoff) {
    options.c_iflag |= IXOFF | IXANY;
  } else {
    options.c_iflag &= ~IXOFF & ~IXANY;
  }  

  if(tcsetattr(fd, TCSANOW, &options) < 0) {
    perror("could not set options");
    exit(-1);
  }

  FD_ZERO(&mask);
  FD_SET(fd, &mask);

  /* Send SLIP request */
  if(rmode && strlen(request) != 0) {
    int i = 0;
    while(request[i++]) {
      slip_send(fd, request[i - 1]);
    } 
    slip_send(fd, SLIP_END);
    slip_flushbuf(fd);
  }
  
  /* Waiting answer forever ( external timeout in use) */
  index = 0;
  for(;;) {
    smask = mask;
    nfound = select(FD_SETSIZE, &smask, (fd_set *)0, (fd_set *)0, (struct timeval *)0);
    if(nfound < 0) {
      if(errno == EINTR) {
        fprintf(stderr, "interrupted system call\n");
        continue;
      }
      /* something is very wrong! */
      perror("select");
      exit(1);
    }

    if(FD_ISSET(fd, &smask)) {
      int i, n = read(fd, buf, sizeof(buf));
      if(n < 0) {
        perror("could not read");
        exit(-1);
      }
      if(n == 0) {
        errno = EBADF;
        perror("serial device disconnected");
        exit(-1);
      }

      for(i = 0; i < n; i++) {
        switch(mode) {
        case MODE_SLIP_AUTO:
        case MODE_SLIP_HIDE:
          if(!flags && (buf[i] != SLIP_END)) {
            /* Not a SLIP packet? */
            printf("%c", buf[i]);
            break;
          }
          /* response received */
          if (rmode && (index > 0) && (mode == MODE_SLIP_HIDE)) {
            /* Response must include the same second character as in request */
            if ((buf[i] == SLIP_END) && (flags != 2) && (rxbuf[1] == request[0 + 1])) {
              fprintf(stdout, "%s\n", rxbuf);
              usleep(1000);
              fflush(NULL);
              usleep(6000);
              exit(0);
            }
          }
                   
        /* continue to slip only mode */
        case MODE_SLIP:
          switch(buf[i]) {
          case SLIP_ESC:
            lastc = SLIP_ESC;
            break;

          case SLIP_END:
            if(index > 0) {
              if(flags != 2 && mode != MODE_SLIP_HIDE) {
                /* not overflowed: show packet */
              }
              lastc = '\0';
              index = 0;
              flags = 0;
            } else {
              flags = !flags;
            }
            break;

          default:
            if(lastc == SLIP_ESC) {
              lastc = '\0';
              /* Previous read byte was an escape byte, so this byte will be
                 interpreted differently from others. */
              switch(buf[i]) {
              case SLIP_ESC_END:
                buf[i] = SLIP_END;
                break;
              case SLIP_ESC_ESC:
                buf[i] = SLIP_ESC;
                break;
              }
            }
            
            rxbuf[index++] = buf[i];
            if(index >= sizeof(rxbuf)) {
              fprintf(stderr, "**** slip overflow\n");
              index = 0;
              flags = 2;
            }
            break;
          }
          break;
        }
      }  
      fflush(stdout);
    }
  }
}
