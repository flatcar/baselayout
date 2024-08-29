# baselayout Makefile
# Copyright 2006-2011 Gentoo Foundation
# Copyright 2014 The CoreOS Authors
# Distributed under the terms of the GNU General Public License v2

# used in "all" and "layout" targets
LIBDIRS ?= lib

INSTALL       ?= install
INSTALL_DIR    = $(INSTALL) -m 0755 -d
INSTALL_EXE    = $(INSTALL) -m 0755
INSTALL_FILE   = $(INSTALL) -m 0644
INSTALL_SECURE = $(INSTALL) -m 0600

DESTDIR =

all: lib/tmpfiles.d/baselayout-usr.conf share/baselayout/shadow share/baselayout/gshadow

lib/tmpfiles.d/baselayout-usr.conf: Makefile
	for d in $(LIBDIRS); do \
		echo "L+	/$${d}	-	-	-	-	usr/$${d}"; \
	done >$@

share/baselayout/shadow: share/baselayout/passwd Makefile
	awk 'BEGIN {FS = ":"} { print $$1 ":*:15887:0:::::" }' <$< >$@

share/baselayout/gshadow: share/baselayout/group Makefile
	awk 'BEGIN {FS = ":"} { print $$1 ":*::" $$4 }' <$< >$@

clean:
	rm -f lib/tmpfiles.d/baselayout-usr.conf share/baselayout/shadow share/baselayout/gshadow

install:
	if [[ -d bin ]]; then \
		$(INSTALL_DIR) $(DESTDIR)/usr/bin; \
		cp -pPR bin/* $(DESTDIR)/usr/bin/; \
	fi
	$(INSTALL_DIR) $(DESTDIR)/etc
	cp -pPR etc/* $(DESTDIR)/etc/
	$(INSTALL_DIR) $(DESTDIR)/usr/lib
	cp -pPR lib/* $(DESTDIR)/usr/lib/
	$(INSTALL_DIR) $(DESTDIR)/usr/share
	cp -pPR share/* $(DESTDIR)/usr/share/
	# no secrets in our shadow or sudoers but this is the proper way
	chmod 0440 $(DESTDIR)/usr/share/baselayout/sudoers
	chmod 0640 $(DESTDIR)/usr/share/baselayout/*shadow
	# FHS compatibility symlinks stuff
	ln -snf /var/tmp $(DESTDIR)/usr/tmp
	# backwards compatibility for /etc/motd
	ln -snf /run/flatcar/motd $(DESTDIR)/usr/share/baselayout/motd

layout:
	for d in bin local local/bin; do $(INSTALL_DIR) "$(DESTDIR)/usr/$${d}" || exit 1; done
	for d in $(LIBDIRS); do $(INSTALL_DIR) "$(DESTDIR)/usr/$${d}" "$(DESTDIR)/usr/local/$${d}" || exit 1; done
	for d in bin $(LIBDIRS); do ln -snf "usr/$${d}" "$(DESTDIR)/$${d}" || exit 1; done
	for d in usr usr/local; do ln -snf bin "$(DESTDIR)/$${d}/sbin" || exit 1; done
	# created by systemd's tmpfiles.d/tmp.conf but that is installed later
	$(INSTALL) -m 1777 -d $(DESTDIR)/tmp $(DESTDIR)/var/tmp

.PHONY: all clean install layout
