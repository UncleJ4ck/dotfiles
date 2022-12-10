#!/bin/sh

HDMI=$(xrandr | grep "HDMI-.-. connected" | awk '{print $1, $2}')
DVI=$(xrandr | grep "DVI-I-.-. connected" | awk '{print $1, $2}')
eDP=$(xrandr | grep "eDP-. connected" | awk '{print $1, $2}')

function multiple_screens() {
	xrandr --output eDP-1 --off --output HDMI-3-0 --primary --mode 1920x1080 --pos 1920x0 --rotate normal --output DVI-I-2-2 --mode 1920x1080 --pos 0x0 --rotate normal --output DVI-I-1-1 --mode 1280x1024 --pos 3840x56 --rotate normal
}

function single_screen() {
	xrandr --output eDP-1 --primary --mode 1920x1080 --pos 0x0 --rotate normal --output HDMI-3-0 --off --output DVI-I-2-2 --off --output DVI-I-1-1 --off
}

if [[ ! -n "$HDMI" ]] || [[ ! -n "$DVI" ]]  
then
	echo "$eDP is displaying"
	single_screen 
elif [[ -n "$HDMI" ]] && [[ -n "$DVI" ]]  
then
	echo "$HDMI"
	echo "$DVI are displaying"
	multiple_screens	
fi
