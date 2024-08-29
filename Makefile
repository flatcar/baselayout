# baselayout Makefile
# Copyright 2006-2011 Gentoo Foundation
# Copyright 2014 The CoreOS Authors
# Distributed under the terms of the GNU General Public License v2

LIBDIRS ?= lib

DESTDIR =
ETC_DIRS = env.d
LIB_DIRS = modprobe.d pam.d sysctl.d tmpfiles.d
SHARE_DIRS = baselayout vim

MKDIR = mkdir -m 0755 -p

all: baselayout/shadow baselayout/gshadow

baselayout/shadow: baselayout/passwd Makefile
	awk 'BEGIN {FS = ":"} { print $$1 ":*:15887:0:::::" }' <$< >$@

baselayout/gshadow: baselayout/group Makefile
	awk 'BEGIN {FS = ":"} { print $$1 ":*::" $$4 }' <$< >$@

clean:
	rm -f baselayout/shadow baselayout/gshadow

install:
	mkdir -m 0755 -p $(DESTDIR)/etc
	cp -PR $(ETC_DIRS) $(DESTDIR)/etc
	mkdir -m 0755 -p $(DESTDIR)/usr/lib
	cp -PR $(LIB_DIRS) $(DESTDIR)/usr/lib
	mkdir -m 0755 -p $(DESTDIR)/usr/share
	cp -PR $(SHARE_DIRS) $(DESTDIR)/usr/share
	# no secrets in our shadow or sudoers but this is the proper way
	chmod 0440 $(DESTDIR)/usr/share/baselayout/sudoers
	chmod 0640 $(DESTDIR)/usr/share/baselayout/*shadow
	# FHS compatibility symlinks stuff
	ln -snf /var/tmp $(DESTDIR)/usr/tmp
	# backwards compatibility for /etc/motd
	ln -snf /run/flatcar/motd $(DESTDIR)/usr/share/baselayout/motd

layout:
	for d in bin local local/bin; do $(MKDIR) "$(DESTDIR)/usr/$${d}" || exit 1; done
	for d in $(LIBDIRS); do $(MKDIR) "$(DESTDIR)/usr/$${d}" "$(DESTDIR)/usr/local/$${d}" || exit 1; done
	for d in bin $(LIBDIRS); do ln -snf "usr/$${d}" "$(DESTDIR)/$${d}" || exit 1; done
	for d in usr usr/local; do ln -snf bin "$(DESTDIR)/$${d}/sbin" || exit 1; done
	# created by systemd's tmpfiles.d/tmp.conf but that is installed later
	mkdir -m 1777 -p $(DESTDIR)/tmp $(DESTDIR)/var/tmp

.PHONY: all clean install layout
