.PHONY: all clean add ci
all: add
	git-commit -a -m "commit on $(date)"
	git-repack -d

clean:
	-rm -f *~
	-rm -f entries/*~

add:
	git-add entries/*[0-9] Makefile

commit ci: add
	git-commit -a
