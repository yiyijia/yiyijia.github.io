#!/bin/sh

if [ -e /dev/cgroup/cpu/plugin ]
then
	for pid in $(cat /dev/cgroup/cpu/plugin/tasks); do
		kill -9 $pid
	done
fi