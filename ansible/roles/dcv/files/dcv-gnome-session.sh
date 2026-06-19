#!/bin/bash
# GNOME Xorg session launcher for the Amazon DCV VIRTUAL session (Phase 13 DCV-03 gap-closure).
# Ported from ansible/roles/xrdp/templates/startwm.sh.j2 (the proven GNOME-on-Xorg recipe).
#
# WHY THIS EXISTS (CRITICAL-2): `dcv create-session --type virtual` with NO --init starts the
# DCV default init, which on AL2023/GNOME 40+ can hand the operator a blank screen or attempt a
# Wayland session Xdcv cannot back. This script forces an Xorg + software-rendered GNOME session
# so the virtual session renders a usable desktop. Wired via `dcv create-session --init` in
# templates/dcv-virtual-session.service.j2.
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Force Xorg session — GNOME 40+ defaults to Wayland; Xdcv (the DCV virtual X server) is X11 only.
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

# Ensure the runtime dir exists (not created by systemd-logind for a DCV virtual session).
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

exec dbus-launch --exit-with-session gnome-session
