.PHONY: all clean add ci
all: add
	git commit -a -m "commit on $(shell date)"
	git gc

clean:
	-rm -f *~
	-rm -f entries/*~

add:
	git add entries/*[0-9] Makefile

commit ci: add
	git commit -a
