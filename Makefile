SHARED_FILES = $(shell find Shared -name "*.m")
SCRIPT_UI_FILES = Prefs/src/ARILabelScriptVisualEditorController.m Prefs/src/ARILabelScriptBlockEditorController.m

ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

TWEAK_NAME = Atria
BUNDLE_NAME = AtriaPrefs

Atria_FILES = $(shell find src -name "*.m" -o -name "*.xm") $(SHARED_FILES) $(SCRIPT_UI_FILES)
Atria_CFLAGS = -fobjc-arc
Atria_FRAMEWORKS = UIKit Foundation CoreGraphics
Atria_PREFS_INSTALL_PATH = /Library/PreferenceLoader/Preferences
Atria_PREFS_FILES = Prefs/layout/Library/PreferenceLoader/Preferences/AtriaPrefs.plist

AtriaPrefs_FILES = $(shell find Prefs/src -name "*.m") $(SHARED_FILES)
AtriaPrefs_CFLAGS = -fobjc-arc
AtriaPrefs_FRAMEWORKS = UIKit Foundation
AtriaPrefs_PRIVATE_FRAMEWORKS = Preferences
AtriaPrefs_LIBRARIES = colorpicker
AtriaPrefs_LDFLAGS += -F$(THEOS)/sdks/iPhoneOS14.5.sdk/System/Library/PrivateFrameworks
AtriaPrefs_INSTALL_PATH = /Library/PreferenceBundles
AtriaPrefs_RESOURCE_DIRS = Prefs/Resources
AtriaPrefs_INFO_PLIST = Prefs/Resources/Info.plist
Atria_LDFLAGS += -F$(THEOS)/sdks/iPhoneOS14.5.sdk/System/Library/PrivateFrameworks -ObjC -all_load

PACKAGE_VERSION = 1.4.1k3
PACKAGE_TYPE = Tweaks
ROOTLESS_PACKAGE_ID = com.yourepo.ancal.atria
ROOTHIDE_PACKAGE_ID = me.ancal.atria
PACKAGE_ID = $(ROOTLESS_PACKAGE_ID)
RELEASE_ARCHS = arm64 arm64e
RELEASE_DIR = release
RELEASE_ROOTLESS_SCHEME = rootless
RELEASE_ROOTHIDE_SCHEME = roothide
RELEASE_ROOTLESS_DEB = $(ROOTLESS_PACKAGE_ID)_$(PACKAGE_VERSION)_iphoneos-arm64.deb
RELEASE_ROOTHIDE_DEB = $(ROOTHIDE_PACKAGE_ID)_$(PACKAGE_VERSION)_iphoneos-arm64e.deb
ROOTHIDE_BUILD_DEB = $(ROOTLESS_PACKAGE_ID)_$(PACKAGE_VERSION)_iphoneos-arm64e.deb
ADDITIONAL_OBJCFLAGS += -DPACKAGE_VERSION=\"$(PACKAGE_VERSION)\" -DPACKAGE_TYPE=\"$(PACKAGE_TYPE)\" -Wno-deprecated-declarations -Wno-vla-cxx-extension

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

INSTALL_TARGET_PROCESSES = SpringBoard

internal-stage:: stage-prefs stage-jbroot-links

stage-prefs::
	mkdir -p $(THEOS_STAGING_DIR)/$(Atria_PREFS_INSTALL_PATH)
	cp $(Atria_PREFS_FILES) $(THEOS_STAGING_DIR)/$(Atria_PREFS_INSTALL_PATH)

stage-jbroot-links::
	if [ -d "$(THEOS_STAGING_DIR)/$(AtriaPrefs_INSTALL_PATH)/AtriaPrefs.bundle" ] && [ ! -e "$(THEOS_STAGING_DIR)/$(AtriaPrefs_INSTALL_PATH)/AtriaPrefs.bundle/.jbroot" ]; then ln -s / "$(THEOS_STAGING_DIR)/$(AtriaPrefs_INSTALL_PATH)/AtriaPrefs.bundle/.jbroot"; fi

after-install::
	install.exec "sbreload"

.PHONY: release release-all release-rootless release-roothide repack-roothide-package release-files ensure-scheme-stage restore-control-package-id

before-package:: ensure-scheme-stage

ensure-scheme-stage::
	$(ECHO_NOTHING)if [ -n "$(THEOS_PACKAGE_INSTALL_PREFIX)" ]; then mkdir -p "$(_THEOS_SCHEME_STAGE)"; fi$(ECHO_END)

restore-control-package-id:
	perl -0pi -e 's/^Package: .*/Package: $(ROOTLESS_PACKAGE_ID)/m' layout/DEBIAN/control

release:
	$(MAKE) release-all

release-all:
	rm -rf $(RELEASE_DIR)
	$(MAKE) release-rootless
	$(MAKE) release-roothide
	$(MAKE) release-files
	$(MAKE) restore-control-package-id

release-rootless:
	rm -rf .theos packages/$(RELEASE_ROOTLESS_DEB)
	$(MAKE) all ARCHS="$(RELEASE_ARCHS)" THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTLESS_SCHEME)
	$(MAKE) package FINALPACKAGE=1 ARCHS="$(RELEASE_ARCHS)" THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTLESS_SCHEME)

release-roothide:
	rm -rf .theos packages/$(ROOTHIDE_BUILD_DEB) packages/$(RELEASE_ROOTHIDE_DEB)
	$(MAKE) all ARCHS="$(RELEASE_ARCHS)" THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTHIDE_SCHEME)
	$(MAKE) package FINALPACKAGE=1 ARCHS="$(RELEASE_ARCHS)" THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTHIDE_SCHEME)
	$(MAKE) repack-roothide-package

repack-roothide-package:
	rm -rf .theos/repack-roothide
	mkdir -p .theos/repack-roothide
	dpkg-deb -R packages/$(ROOTHIDE_BUILD_DEB) .theos/repack-roothide
	perl -0pi -e 's/^Package: .*/Package: $(ROOTHIDE_PACKAGE_ID)/m' .theos/repack-roothide/DEBIAN/control
	dpkg-deb -b .theos/repack-roothide packages/$(RELEASE_ROOTHIDE_DEB)

release-files:
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	cp packages/$(RELEASE_ROOTLESS_DEB) $(RELEASE_DIR)/
	cp packages/$(RELEASE_ROOTHIDE_DEB) $(RELEASE_DIR)/
	shasum -a 256 \
		$(RELEASE_DIR)/$(RELEASE_ROOTLESS_DEB) \
		$(RELEASE_DIR)/$(RELEASE_ROOTHIDE_DEB) > $(RELEASE_DIR)/SHA256SUMS
