#!/usr/bin/env bash
# Remove everything the Docker track (track 0) created, so a module starts clean.
#   ./lab.sh reset docker                         the same, from anywhere in the repo
#   ./platform-engineering/0-docker/reset.sh      removes the course's containers, networks,
#                                                 volumes, images and the work folder
# It removes only what the course names: containers, networks and volumes whose names start
# with "course-", images in the "course/" and "localhost:5555/" repositories, and the work
# folder. Base images it pulled (alpine, nginx, golang and the others) stay, so the next
# module starts without downloads. It never prunes anything else on your Docker engine.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Removing the Docker track's containers, networks, volumes and images"
ids="$(docker ps -aq --filter 'name=^course-')"
[ -n "$ids" ] && docker rm -f $ids >/dev/null
# Compose projects of the course carry names that start with course-, and so do their
# containers, networks and volumes.
ids="$(docker network ls -q --filter 'name=^course-')"
[ -n "$ids" ] && docker network rm $ids >/dev/null
ids="$(docker volume ls -q --filter 'name=^course-')"
[ -n "$ids" ] && docker volume rm $ids >/dev/null
for ref in 'course/*' 'localhost:5555/*'; do
  imgs="$(docker image ls --filter "reference=$ref" --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' || true)"
  [ -n "$imgs" ] && docker image rm -f $imgs >/dev/null 2>&1
done
# Untagged leftovers of course builds, found by the label every course Dockerfile sets.
ids="$(docker image ls -q --filter 'label=lab.course=docker' | sort -u)"
[ -n "$ids" ] && docker image rm -f $ids >/dev/null 2>&1
rm -rf "$HERE/work"
left="$(docker ps -aq --filter 'name=^course-' | wc -l | tr -d ' ')"
if [ "$left" = 0 ]; then
  echo "Done. No course containers, networks or volumes are left."
else
  echo "Some course containers are still there: docker ps -a --filter name=^course-" >&2
  exit 1
fi
