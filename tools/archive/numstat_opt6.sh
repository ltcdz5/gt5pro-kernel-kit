#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git diff --diff-filter=d --numstat 7a244ff18 FETCH_HEAD | sort -k1,1rn | awk '{printf "%6d + %6d -   %s\n", $1, $2, $3}'
