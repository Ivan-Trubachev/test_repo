CXX = $(CC)
CXXFLAGS = -Wall -Wextra -pedantic

all: test_app

test_app: test_app.o
	$(CXX) $(CXXFLAGS) -o $@ $^ -lgps -lm

test_app.o: test_app.c
	$(CXX) $(CXXFLAGS) -c $<

clean:
	rm -f test_app test_app.o

