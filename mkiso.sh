#!/bin/bash

[[ $# -gt 0 ]] || {
	echo "Usage: $0 <mode> [options]"
	exit 1
}
