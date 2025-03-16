TARGET := iphone:clang:latest:11.0

PACKAGE_VERSION = 1.3

GO_EASY_ON_ME = 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TrollDecrypt

TrollDecrypt_FILES = $(wildcard ./*.m) $(wildcard SSZipArchive/*.m) $(wildcard SSZipArchive/minizip/*.c) $(wildcard SSZipArchive/minizip/aes/*.c)

TrollDecrypt_FILES += $(wildcard ./*.m)

TrollDecrypt_FRAMEWORKS = UIKit CoreGraphics MobileCoreServices

TrollDecrypt_CFLAGS = -fobjc-arc

TrollDecrypt_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

#after-stage::
##	mkdir -p $(THEOS_STAGING_DIR)/Payload
	#ldid -Sentitlements.plist #$(THEOS_STAGING_DIR)/Applications/TrollDecrypt.app/TrollDecrypt
	#cp -a $(THEOS_STAGING_DIR)/Applications/* $(THEOS_STAGING_DIR)/Payload
	#mv $(THEOS_STAGING_DIR)/Payload .
	#zip -q -r TrollDecrypt.tipa Payload
