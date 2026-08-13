SHARED_FILES = $(shell find Shared -name "*.m")
SCRIPT_UI_FILES = Prefs/src/ARILabelScriptVisualEditorController.m

ARCHS = arm64 arm64e
# Current Xcode SDKs omit the private Preferences link stub used by the
# settings bundle. Default to the complete Theos SDK while keeping this
# overridable for builders that provide an equivalent newer SDK.
ATRIA_SDK_VERSION ?= 16.5
TARGET ?= iphone:clang:$(ATRIA_SDK_VERSION):15.0
THEOS_PACKAGE_SCHEME ?= rootless

TWEAK_NAME = Atria
BUNDLE_NAME = AtriaPrefs

Atria_FILES = $(shell find src -name "*.m" -o -name "*.xm") $(SHARED_FILES) $(SCRIPT_UI_FILES)
Atria_CFLAGS = -fobjc-arc
Atria_FRAMEWORKS = UIKit Foundation CoreGraphics CoreText
Atria_PREFS_INSTALL_PATH = /Library/PreferenceLoader/Preferences
Atria_PREFS_FILES = Prefs/layout/Library/PreferenceLoader/Preferences/AtriaPrefs.plist

AtriaPrefs_FILES = $(shell find Prefs/src -name "*.m") $(SHARED_FILES)
AtriaPrefs_CFLAGS = -fobjc-arc
AtriaPrefs_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers
AtriaPrefs_PRIVATE_FRAMEWORKS = Preferences
AtriaPrefs_LIBRARIES = colorpicker
AtriaPrefs_INSTALL_PATH = /Library/PreferenceBundles
AtriaPrefs_RESOURCE_DIRS = Prefs/Resources
AtriaPrefs_INFO_PLIST = Prefs/Resources/Info.plist
Atria_LDFLAGS += -ObjC -all_load

PACKAGE_ID = me.ancal.atria
PACKAGE_VERSION = 1.4.1k4
PACKAGE_TYPE = Tweaks
RELEASE_ARCHS = arm64 arm64e
RELEASE_DIR = release
RELEASE_ROOTLESS_SCHEME = rootless
RELEASE_ROOTHIDE_SCHEME = roothide
RELEASE_ROOTLESS_PREFIX = /var/jb
# The top-level default scheme is rootless, and Theos exports its install
# prefix to recursive makes. Explicitly clear it for every RootHide recursion
# so /var/jb cannot leak into staging or Mach-O install names.
RELEASE_ROOTHIDE_PREFIX =
RELEASE_ROOTLESS_PACKAGE_ARCH = iphoneos-arm64
RELEASE_ROOTHIDE_PACKAGE_ARCH = iphoneos-arm64e
RELEASE_ROOTLESS_DEB = $(PACKAGE_ID)_$(PACKAGE_VERSION)_$(RELEASE_ROOTLESS_PACKAGE_ARCH).deb
RELEASE_ROOTHIDE_DEB = $(PACKAGE_ID)_$(PACKAGE_VERSION)_$(RELEASE_ROOTHIDE_PACKAGE_ARCH).deb
RELEASE_STRIP_TOOL := $(shell xcrun -f strip 2>/dev/null)
# The first release pass must use the final schema too.  Building `all` with
# Theos's default debug schema and adding FINALPACKAGE only to `package` leaves
# the already-staged N_OSO/source-path symbols untouched.
# The top-level development invocation exports its DEBUG schema to recursive
# makes, including TARGET_STRIP=":". Override the schema and strip tool so a
# release recursion cannot inherit obj/debug or a no-op strip command.
RELEASE_BUILD_FLAGS = FINALPACKAGE=1 DEBUG=0 STRIP=1 \
	THEOS_SCHEMA=DEFAULT _THEOS_CLEANED_SCHEMA_SET= \
	TARGET_STRIP="$(RELEASE_STRIP_TOOL)" TARGET_STRIP_FLAGS=-x \
	ARCHS="$(RELEASE_ARCHS)"
# Theos falls back to dm.pl on macOS.  Without fauxsu/fakeroot, the local
# Archive::Tar version preserves the host's numeric 501:20 ownership even
# though it labels the entries root:wheel.  Use dpkg-deb's explicit numeric
# ownership mode for release archives.
RELEASE_PACKAGE_FLAGS = $(RELEASE_BUILD_FLAGS) \
	_THEOS_PLATFORM_DPKG_DEB="$(CURDIR)/tools/dpkg-deb-root-owner-group" \
	THEOS_PLATFORM_DEB_COMPRESSION_TYPE=xz
ADDITIONAL_OBJCFLAGS += -DPACKAGE_VERSION=\"$(PACKAGE_VERSION)\" -DPACKAGE_TYPE=\"$(PACKAGE_TYPE)\" -Wno-deprecated-declarations -Wno-vla-cxx-extension

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

INSTALL_TARGET_PROCESSES = SpringBoard

internal-stage:: stage-prefs

stage-prefs::
	mkdir -p "$(THEOS_STAGING_DIR)$(Atria_PREFS_INSTALL_PATH)"
	cp "$(Atria_PREFS_FILES)" "$(THEOS_STAGING_DIR)$(Atria_PREFS_INSTALL_PATH)/"

after-install::
	install.exec "sbreload"

.PHONY: stage-prefs verify-package-config verify-release-rootless verify-release-roothide release release-all release-rootless release-roothide release-files

before-package:: verify-package-config

verify-package-config:
	@test "$$(sed -n 's/^Package: //p' layout/DEBIAN/control)" = "$(PACKAGE_ID)" || { echo "error: Makefile PACKAGE_ID and control Package differ" >&2; exit 1; }
	@test "$$(sed -n 's/^Version: //p' layout/DEBIAN/control)" = "$(PACKAGE_VERSION)" || { echo "error: Makefile PACKAGE_VERSION and control Version differ" >&2; exit 1; }
	@test -x "$(RELEASE_STRIP_TOOL)" || { echo "error: Xcode strip tool not found" >&2; exit 1; }

release:
	$(MAKE) release-all

release-all:
	rm -rf $(RELEASE_DIR)
	$(MAKE) release-rootless
	$(MAKE) release-roothide
	$(MAKE) release-files

release-rootless:
	$(MAKE) clean $(RELEASE_BUILD_FLAGS) THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTLESS_SCHEME) THEOS_PACKAGE_INSTALL_PREFIX="$(RELEASE_ROOTLESS_PREFIX)"
	# Theos skips its top-level staging cleanup inside this recursive release
	# target. Reset it explicitly so a previous scheme can never leak into the
	# package, and create the rootless relocation destination used by deb.mk.
	rm -rf "$(THEOS_STAGING_DIR)" "$(_THEOS_STAGING_TMP)"
	mkdir -p "$(THEOS_STAGING_DIR)" "$(_THEOS_STAGING_TMP)/var/jb"
	rm -f packages/$(RELEASE_ROOTLESS_DEB)
	$(MAKE) all $(RELEASE_BUILD_FLAGS) THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTLESS_SCHEME) THEOS_PACKAGE_INSTALL_PREFIX="$(RELEASE_ROOTLESS_PREFIX)"
	# The build-session cleanup performed by `all` removes the scheme staging
	# directory. Recreate it immediately before deb.mk relocates /Library.
	mkdir -p "$(_THEOS_STAGING_TMP)/var/jb"
	$(MAKE) package $(RELEASE_PACKAGE_FLAGS) THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTLESS_SCHEME) THEOS_PACKAGE_INSTALL_PREFIX="$(RELEASE_ROOTLESS_PREFIX)"
	$(MAKE) verify-release-rootless

release-roothide:
	$(MAKE) clean $(RELEASE_BUILD_FLAGS) THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTHIDE_SCHEME) THEOS_PACKAGE_INSTALL_PREFIX="$(RELEASE_ROOTHIDE_PREFIX)"
	# RootHide packages deliberately retain rootful-looking archive paths; its
	# package manager maps them into the active, randomized jailbreak root.
	rm -rf "$(THEOS_STAGING_DIR)" "$(_THEOS_STAGING_TMP)"
	mkdir -p "$(THEOS_STAGING_DIR)" "$(_THEOS_STAGING_TMP)"
	rm -f packages/$(RELEASE_ROOTHIDE_DEB)
	$(MAKE) all $(RELEASE_BUILD_FLAGS) THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTHIDE_SCHEME) THEOS_PACKAGE_INSTALL_PREFIX="$(RELEASE_ROOTHIDE_PREFIX)"
	$(MAKE) package $(RELEASE_PACKAGE_FLAGS) THEOS_PACKAGE_SCHEME=$(RELEASE_ROOTHIDE_SCHEME) THEOS_PACKAGE_INSTALL_PREFIX="$(RELEASE_ROOTHIDE_PREFIX)"
	$(MAKE) verify-release-roothide

verify-release-rootless:
	@test "$$(dpkg-deb -f packages/$(RELEASE_ROOTLESS_DEB) Package)" = "$(PACKAGE_ID)"
	@test "$$(dpkg-deb -f packages/$(RELEASE_ROOTLESS_DEB) Version)" = "$(PACKAGE_VERSION)"
	@test "$$(dpkg-deb -f packages/$(RELEASE_ROOTLESS_DEB) Architecture)" = "$(RELEASE_ROOTLESS_PACKAGE_ARCH)"
	@dpkg-deb --fsys-tarfile packages/$(RELEASE_ROOTLESS_DEB) | perl -MArchive::Tar -e 'my $$tar = Archive::Tar->new; $$tar->read(\*STDIN) or die "error: cannot read data tar\n"; for my $$file ($$tar->get_files) { die sprintf("error: %s has uid:gid %d:%d\n", $$file->full_path, $$file->uid, $$file->gid) if $$file->uid != 0 || $$file->gid != 0; }'
	@for member in \
		./var/jb/Library/MobileSubstrate/DynamicLibraries/Atria.dylib \
		./var/jb/Library/PreferenceBundles/AtriaPrefs.bundle/AtriaPrefs; do \
		object="$$(mktemp /tmp/atria-rootless-verify.XXXXXX)" || exit 1; \
		symbols="$$object.nm"; \
		if ! dpkg-deb --fsys-tarfile packages/$(RELEASE_ROOTLESS_DEB) | tar -xOf - "$$member" > "$$object"; then \
			rm -f "$$object" "$$symbols"; exit 1; \
		fi; \
		if ! xcrun nm -ap "$$object" > "$$symbols"; then \
			rm -f "$$object" "$$symbols"; exit 1; \
		fi; \
		if grep -q ' OSO ' "$$symbols"; then \
			echo "error: $$member contains N_OSO debug paths" >&2; \
			rm -f "$$object" "$$symbols"; exit 1; \
		fi; \
		rm -f "$$object" "$$symbols"; \
	done
	@payload="$$(dpkg-deb --fsys-tarfile packages/$(RELEASE_ROOTLESS_DEB) | tar -tf -)"; \
		test "$$(printf '%s\n' "$$payload" | grep -Ec '^(\./)?var/jb/Library/MobileSubstrate/DynamicLibraries/Atria\.dylib$$')" = 1; \
		test "$$(printf '%s\n' "$$payload" | grep -Ec '^(\./)?var/jb/Library/PreferenceBundles/AtriaPrefs\.bundle/AtriaPrefs$$')" = 1; \
		! printf '%s\n' "$$payload" | grep -Eq '^(\./)?Library/'; \
		! printf '%s\n' "$$payload" | grep -Eq '^(\./)?var/mobile/'

verify-release-roothide:
	@test "$$(dpkg-deb -f packages/$(RELEASE_ROOTHIDE_DEB) Package)" = "$(PACKAGE_ID)"
	@test "$$(dpkg-deb -f packages/$(RELEASE_ROOTHIDE_DEB) Version)" = "$(PACKAGE_VERSION)"
	@test "$$(dpkg-deb -f packages/$(RELEASE_ROOTHIDE_DEB) Architecture)" = "$(RELEASE_ROOTHIDE_PACKAGE_ARCH)"
	@dpkg-deb --fsys-tarfile packages/$(RELEASE_ROOTHIDE_DEB) | perl -MArchive::Tar -e 'my $$tar = Archive::Tar->new; $$tar->read(\*STDIN) or die "error: cannot read data tar\n"; for my $$file ($$tar->get_files) { die sprintf("error: %s has uid:gid %d:%d\n", $$file->full_path, $$file->uid, $$file->gid) if $$file->uid != 0 || $$file->gid != 0; }'
	@for member in \
		./Library/MobileSubstrate/DynamicLibraries/Atria.dylib \
		./Library/PreferenceBundles/AtriaPrefs.bundle/AtriaPrefs; do \
		object="$$(mktemp /tmp/atria-roothide-verify.XXXXXX)" || exit 1; \
		symbols="$$object.nm"; \
		if ! dpkg-deb --fsys-tarfile packages/$(RELEASE_ROOTHIDE_DEB) | tar -xOf - "$$member" > "$$object"; then \
			rm -f "$$object" "$$symbols"; exit 1; \
		fi; \
		if ! xcrun nm -ap "$$object" > "$$symbols"; then \
			rm -f "$$object" "$$symbols"; exit 1; \
		fi; \
		if grep -q ' OSO ' "$$symbols"; then \
			echo "error: $$member contains N_OSO debug paths" >&2; \
			rm -f "$$object" "$$symbols"; exit 1; \
		fi; \
		rm -f "$$object" "$$symbols"; \
	done
	@payload="$$(dpkg-deb --fsys-tarfile packages/$(RELEASE_ROOTHIDE_DEB) | tar -tf -)"; \
		test "$$(printf '%s\n' "$$payload" | grep -Ec '^(\./)?Library/MobileSubstrate/DynamicLibraries/Atria\.dylib$$')" = 1; \
		test "$$(printf '%s\n' "$$payload" | grep -Ec '^(\./)?Library/PreferenceBundles/AtriaPrefs\.bundle/AtriaPrefs$$')" = 1; \
		! printf '%s\n' "$$payload" | grep -Eq '^(\./)?var/jb/'; \
		! printf '%s\n' "$$payload" | grep -Eq '^(\./)?var/mobile/'
	@command -v strings >/dev/null
	@for member in \
		Library/MobileSubstrate/DynamicLibraries/Atria.dylib \
		Library/PreferenceBundles/AtriaPrefs.bundle/AtriaPrefs; do \
		hits="$$(dpkg-deb --fsys-tarfile packages/$(RELEASE_ROOTHIDE_DEB) | \
			tar -xOf - "$$member" | strings -a | grep -F -c '/var/jb' || true)"; \
		if test "$$hits" != 0; then \
			echo "error: RootHide binary $$member contains /var/jb" >&2; \
			exit 1; \
		fi; \
	done
release-files:
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	cp packages/$(RELEASE_ROOTLESS_DEB) $(RELEASE_DIR)/
	cp packages/$(RELEASE_ROOTHIDE_DEB) $(RELEASE_DIR)/
	cd $(RELEASE_DIR) && shasum -a 256 \
		$(RELEASE_ROOTLESS_DEB) \
		$(RELEASE_ROOTHIDE_DEB) > SHA256SUMS
