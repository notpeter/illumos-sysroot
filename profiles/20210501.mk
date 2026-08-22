TARVERSION =		20210501-e0b4275f34-v0
GATE_BRANCH =		sysroot/20210501
GATE_COMMIT =		e0b4275f346eda86b39157cd7dd3cc889a1f6988
BUILD_HOST =		OmniOS r151038
SOURCE_DATE_EPOCH ?=	1762459338
LIBGCC_VERSION =	4_8_0

INCLUDE_PACKAGES =	system/header \
			system/library \
			system/library/math \
			system/library/c-runtime \
			system/library/security/gss
