.PHONY: all clean add ci
all:
	@echo make clean add commit ci

clean:
	-rm -f *~
	-rm -f entries/*~

add:
	git-add entries/*[0-9]

commit ci: add
	git-commit -a
