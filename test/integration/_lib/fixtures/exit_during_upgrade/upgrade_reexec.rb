#!/bin/sh

if [ "$1" = "--with-state-fd" ]; then
  sleep 6
fi
exec bundle exec --keep-file-descriptors einhorn "$@"
