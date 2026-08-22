TARVERSION =		20181213-de6af22ae73b-v2
GATE_BRANCH =		sysroot/20181213
GATE_COMMIT =		de6af22ae73ba8d72672288621ff50b88f2cf5fd
BUILD_HOST =		OmniOS r151030 or newer illumos host
SOURCE_DATE_EPOCH ?=	1544726597
LIBGCC_VERSION =	4_8_0

INCLUDE_PACKAGES =	system/header \
			system/library \
			system/library/math \
			system/library/c-runtime \
			system/library/security/gss
