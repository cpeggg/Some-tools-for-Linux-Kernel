#!/bin/sh
COMMITMENT="$1"
LEN=$(echo -n "$COMMITMENT"|wc -c)
if [ "$LEN" = "0" ]
then 
	echo "\nUsage: $0 commitment\n"
	exit 1
fi
git add --all

git commit -m $COMMITMENT

git push -u origin master