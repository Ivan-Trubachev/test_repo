APPS = hello_world2
LIB_SRCS = 
DEPEND = 

all: $(APPS)

CFLAGS += -Wall -Werror -O2

$(APPS) : % : %.c 
	$(CC) $(CFLAGS) $< -o $@

clean:
	rm -f $(APPS)
