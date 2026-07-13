#!/bin/bash
# GNOME-on-Xorg session launcher for the xrdp RDP session (quick-task 260707-o7s, XRDP).
# This is /etc/xrdp/startwm.sh — xrdp-sesman exec()s it to start the user's desktop after a
# successful PAM login. Logic mirrors ansible/roles/dcv/files/dcv-gnome-session.sh (whose own
# header notes it was ported FROM the original xrdp startwm.sh): force an Xorg + software-
# rendered (llvmpipe, non-GPU) GNOME session so the RDP desktop actually renders instead of a
# blank/Wayland screen.
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Force Xorg session — GNOME 40+ defaults to Wayland; xorgxrdp's Xorg backend is X11 only.
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=GNOME
export GDK_BACKEND=x11
XDG_RUNTIME_DIR=/run/user/$(id -u)
export XDG_RUNTIME_DIR

# Software rendering — this is a non-GPU EC2 instance; llvmpipe avoids a blank/black screen.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

# Inherit system-wide profile (PATH, locale, etc.) if present.
if [ -f /etc/profile ]; then
    # shellcheck disable=SC1091
    . /etc/profile
fi

# Ensure the runtime dir exists (not created by systemd-logind for an xrdp session).
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

exec dbus-launch --exit-with-session gnome-session
