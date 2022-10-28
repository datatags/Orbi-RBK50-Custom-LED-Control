#!/bin/sh

while true
do
    # 54 = red, 53 = green, 57 = blue, 60 = white
	# Update color every iteration for when it's overwritten by a scheduled task
    gpio -n gpio_write -c 54 -s 1
    gpio -n gpio_write -c 57 -s 1
    i2cset -y 0 0x68 0x02 0x7f i
    #echo 2 PARTIAL
    sleep 0.25
    i2cset -y 0 0x68 0x02 0xff i
    #echo 2 ON
    sleep 0.25
    for i in 0 1 2 3 4 5 6
    do
        i2cset -y 0 0x68 0xa$((i%8+2)) 0x00 0xff i
        #echo $((i%8+2)) OFF
        #echo $((i%8+3)) ON
        sleep 0.25
    done
    # also set global PWM to max
    i2cset -y 0 0x68 0xc9 0x7f 0xff i
    #echo 9 PARTIAL
    sleep 0.25
    i2cset -y 0 0x68 0x09 0x00 i
    #echo 2 ON
    sleep 0.25
done
