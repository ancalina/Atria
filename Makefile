ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:13.0

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Atria
Atria_FILES = $(shell find src -type f \( -name '*.m' -o -name '*.xm' \) | sort)
Atria_CFLAGS += -fobjc-arc
Atria_LIBRARIES = substrate
Atria_FRAMEWORKS = UIKit CoreText

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Prefs

include $(THEOS_MAKE_PATH)/aggregate.mk
