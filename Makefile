.PHONY: all clean add ci
all: add
	touch .blog
	git commit -a -m "commit on $(shell date)"
	GIT_EXEC_PATH= /usr/bin/git gc
	git push

clean:
	-rm -f *~
	-rm -f entries/*~

add:
	git add entries/*[0-9] Makefile

commit ci: add
	git commit -a
