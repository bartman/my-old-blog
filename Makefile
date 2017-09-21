.PHONY: all commit deploy full-deploy clean
all:
	${MAKE} commit
	${MAKE} deploy

commit: add
	git commit -m "commit on $(shell date)"

add:
	git add entries/*[0-9] Makefile

DEPLOY_HOST=bart@up
DEPLOY_DIR=blog

deploy:
	git ls-files > .filestosync
	rsync -avz --files-from=.filestosync ./ ${DEPLOY_HOST}:${DEPLOY_DIR}/

full-deploy:
	git archive --format=tar HEAD | ssh ${DEPLOY_HOST} tar -x -C ${DEPLOY_DIR}/ -vf -

clean:
	-rm -f *~
	-rm -f entries/*~
