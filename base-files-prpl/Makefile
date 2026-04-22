#
# Copyright (C) 2009 OpenWrt.org
# Copyright (C) 2020-2024, MaxLinear, Inc.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
# $Id: $

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=base-files-prpl
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SUBMENU:=Base Files
  SECTION:=base
  CATEGORY:=MaxLinear
  TITLE:=Common files for MaxLinear URX CPE Systems running prplOs
  URL:=http://www.maxlinear.com/
  MAINTAINER:=MaxLinear Inc
endef

define Package/$(PKG_NAME)/description
 This package contains files and system scripts for prplOs,
 common for all MaxLinear CPE Targets.
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	echo -ne UPDK_9.2.10-ED > $(1)/etc/version
	date +%H%M-%d%b%y > $(1)/etc/timestamp
	LUA_VERSION=`grep -E '^CONFIG_PACKAGE_lua[0-9]+\.[0-9]+=y' $(TOPDIR)/.config | sed -E 's/CONFIG_PACKAGE_lua([0-9]+\.[0-9]+)=y/\1/'`; \
	if [ -n "$$$$LUA_VERSION" ]; then \
		mkdir -p $(1)/usr/local/lib/lua/$$$$LUA_VERSION/; \
		mv -vf $(1)/usr/lib/lua/swupdate_handlers.lua $(1)/usr/local/lib/lua/$$$$LUA_VERSION/; \
	fi
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

