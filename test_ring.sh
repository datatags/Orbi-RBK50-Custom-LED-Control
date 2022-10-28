#!/bin/sh
set -e
# First arg, or 1 if not provided
STEP=${1:-1}
echo Running with step size $STEP
while true
do
    i=0
    while [[ $i -lt 256 ]]
    do
        i2cset -y 0 0x68 0x0a 0x$(printf '%x' $i)
        i=$((i+STEP))
    done
    # Value no longer valid, revert one step
    i=$((i-STEP))
    while [[ $i -gt 0 ]]
    do
        i2cset -y 0 0x68 0x0a 0x$(printf '%x' $i)
        i=$((i-STEP))
    done
done
