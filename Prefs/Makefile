ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:13.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AtriaPrefs
AtriaPrefs_FILES = $(shell find src -type f -name '*.m' | sort)
AtriaPrefs_CFLAGS += -fobjc-arc
AtriaPrefs_FRAMEWORKS = UIKit
AtriaPrefs_PRIVATE_FRAMEWORKS = Preferences
AtriaPrefs_RESOURCE_DIRS = Resources
AtriaPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp layout/Library/PreferenceLoader/Preferences/*.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(ECHO_END)
