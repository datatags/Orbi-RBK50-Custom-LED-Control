# Orbi-RBK50-Custom-LED-Control

This repo is about controlling the RGB status LED(s) on the top of the Netgear Orbi RBR50 and RBS50 (together known as RBK50.) Other models of Orbi may be functionally the same, but these are the devices I've tested with.

## Background

Each RBK50 has a status LED on top used to indicate various things, such as "starting up" or "failed to connect." When connected to the Orbi using SSH/telnet, you can set the LED color and pattern manually using `/sbin/ledcontrol`. `ledcontrol` is a compiled binary, but it appears to do its work by communicating with `/dev/atherosgpio`. `atherosgpio` is a device provided by a kernel module which will interact with the Orbi GPIO and I2C depending on what you want to do.

The status lights are controlled by GPIO and I2C together: the color is selected using GPIO, and brightness is set by communicating with the LED controller over I2C. The LED controller is a TLC59208F, whose datasheet can be found [here](https://www.ti.com/lit/ds/symlink/tlc59208f.pdf). The TLC59208F has 8 LED outputs, and there are in fact 8 LEDs for each color positioned under the top of the Orbi. As far as I can tell, the kernel module never controls the LEDs individually, and only uses the `GRPPWM` and `GRPFREQ` for setting the duty cycle and blinking frequency (see pg. 22 in the datasheet.)

When communicating with the TLC59208F, the I2C address is 0x27 (on my Orbis at least.) However, the device is "locked" by a loaded driver, so other tools don't want to communicate with it. `i2cset` has a flag that can override this, but it's easier just to use a different address, 0x68, that the device also listens on. (This is known as the "all-call" address in the datasheet, and all TLC59208F chips listen on this address by default.)

Since the kernel module doesn't appear to allow individual control of the LEDs, that's exactly what I wanted to do. Problem is, the `atherosgpio` kernel module locks the GPIO pins from control by other programs in the standard way. Fortunately though, the Orbi already has a tool (`gpio`) that uses the kernel module to set GPIO pins directly.

## Basic control

So, how do we do it? Well, first, environment. My Orbis are, at the time of writing, running [Voxel's Firmware](http://www.voxel-firmware.com/Downloads/Voxel/html/orbi.html) `v9.2.5.2.24SF`, so I don't know if the tools I used exist in stock firmware. I had to build the latest version of `i2c-tools` rather than just using the provided one due to [this bug](https://stackoverflow.com/q/52530009/).

There appear to be four colors for each LED that can be set with the GPIO pins: white (60), red (54), green (53), and blue (57) ([source](https://git.openwrt.org/?p=openwrt/openwrt.git;a=commitdiff;h=2cb24b3f3cd89692f3c0bd137f3f560ada359bfa)). Setting these GPIO pins will set that color for all eight LEDs; there doesn't appear to be a way to control the colors individually. As mentioned previously, these can't be set using the normal methods, but you can use the Orbi-specific (or Netgear-specific?) `gpio` tool to control them.

**For example, to set all LEDs to green, you can run** `gpio -n gpio_write -c 53 -s 1`

(Side note, this same command works for setting the power LEDs as well: red (64), green (63)) This command writes to GPIO pin 53, setting it to on (1). But if you run that command on its own, likely nothing will happen because the LED controller is turned off. To turn the controller on, and set other properties of it, we have to communicate over I2C. Each individual LED channel is already set on by the Orbi, so we just have to write to the group control register.

**For example, to set all LEDs to full brightness, you can run** `i2cset -y 0 0x68 0x0a 0xff`

This command (without asking for confirmation due to `-y`) will write to the device on bus 0, address `0x68` (default "all-call" address for chip), register `0x0a` (group duty cycle), setting it to `0xff` (max value.) Running both commands together should provide you with a solid green light on top of the Orbi.

You may notice that the light will turn off on its own after a period of time. This appears to be caused by some sort of background task that resets the light every once in a while. If you want, you can rename or remove `ledcontrol` to prevent this from happening, since it seems to be one of two binaries that interact with `atherosgpio` directly, the other being the `gpio` tool.

## Advanced control

Alright, so now we know how to control all the lights together. But we set out to be able to control them invididually, so let's look at how to do that. (If you're already familiar with I2C and `i2cset`, you will be able to figure all this out from the datasheet. If you aren't familiar with I2C, read on.)

Going back to the [TLC59208F datasheet](https://www.ti.com/lit/ds/symlink/tlc59208f.pdf), on page 21, it mentions the registers we can write to for individual LEDs. For example, to turn the first LED off, we can use a command like: `i2cset -y 0 0x68 0x02 0x00`. Here, `-y` means don't ask for confirmation, `0` is the I2C bus, `0x68` is the "all-call" address for the controller, `0x02` is the brightness register for the first LED, and `0x00` is the value we're writing to it. Setting a value between 0x00 and 0xff would give varying degrees of brightness.

Conveniently, the chip also provides a way to write to several registers at once by writing to "higher-numbered" registers. The three highest bits determine what should happen when executing multiple writes, and according to page 19 of the datasheet, if we want to write to only the brightness registers, we can set the three highest bits to 0b101. Putting it all together, if we want to write to all 8 brightness registers at once, we can use a command like `i2cset -y 0 0x68 0xa2 0x11 0x22 0x33 0x44 0x55 0x66 0x77 0x88 i`, where 0x11..0x88 are the values we want to put in each register. `i` is the mode to use when writing multiple blocks. For this command specifically, the built-in version of `i2cset` **will not work**, you will need to either build a more recent version, or stick to writing one register at a time.

What about the blinking feature? To switch from group brightness control (duty cycle) to group blinking, we need to set bit 5 in register 0x01 (according to datasheet page 21.) Since we don't want to update the other bits, we can use `i2cset`'s mask function. For example: `i2cset -y -m 0x20 0 0x68 0x01 0xff`. `0x20` is 0b10000 in hex. I used `0xff` as the write value for simplicity, but you could use any number with bit 5 set. Once this is done, you can control the blink speed with register 0x0b.

## Script control

Setting the brightness by hand is fine, but I wanted to make some sort of fancy animation that could run on a loop. The easiest way to do that is to write a shell script, which is all I've done so far.

`right-left.sh` runs the LEDs from right to left, by default in a magenta color (red + blue). LEDs 1 and 8 get an additional step of 50% brightness because I think it looks better. The last step has all lights off, before the cycle repeats.

`test_ring.sh` does a similar pattern to running `ledcontrol` with the `-s ring` argument, but with this script you can change the oscillation speed. By default it steps by values of 1, but you can pass another number to change it. The higher the step value, the faster it will go. Note that the script does not have a `sleep` command in it; it simply runs as fast as it can given the time it takes to send I2C data.

If you write any cool scripts of your own, please submit a PR; I'd love to try your scripts as well!

## Running without the kernel module

As I was writing this, I discovered it is possible to stop the `atherosgpio` kernel module from loading by using the `overlay` folder (see Voxel firmware `QuickStart.txt`) to modify `/sbin/init-gpio`. That's apparently the script that loads the kernel module, so putting a corresponding file in `overlay` with that step commented out does prevent the kernel module from loading, and the status light continues blinking white indefinitely. Making this change does allow you to access the GPIO pins in the normal way (i.e. `echo 57 > /sys/class/gpio/export`), but `ledcontrol` and `gpio` will not work at all.

You can also detach the TLC59208F from the driver using this command: `echo 0-0027 > /sys/bus/i2c/drivers/tlc59208f/unbind`. (I guess the device name comes from the chip having address 0x27 on bus 0.) This doesn't appear to prevent `atherosgpio` from communicating with it anyway, so I'm not sure what the purpose of this driver is.
