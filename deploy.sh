#!/bin/bash
set -e -x
case $1 in
	full)
		git archive --format=tar HEAD | ssh bart@up tar -x -C blog -vf -
		;;
	update)
		git ls-files > .filestosync
		rsync -avz --files-from=.filestosync ./ bart@up:blog/
		;;
	*)
		cat <<END
full      - use git archive, ssh and tar on remove
update    - use rsync
END
		;;
esac
