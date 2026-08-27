TARVERSION =		20210501-e0b4275f34-v1
RELEASE_BASE_COMMIT =	2ed5ea5a06df7f669d20d88729c625981a0de7bc
BUILD_HEAD_REF =	sysroot/20210501
BUILD_HEAD_COMMIT =	e0b4275f346eda86b39157cd7dd3cc889a1f6988
BUILD_HISTORY_DEPTH =	2
GATE_VERSION =		sysroot/20210501-0-ge0b4275f346e
BUILDER_RELEASE =	r151038
BUILDER_IMAGE_URL =	https://downloads.omnios.org/media/r151038/omnios-r151038an.iso
BUILDER_IMAGE_SHA256 = 67d767f23d9498e01a9c5ef2f4fd690937bea433deefc2a068ea4343a13fdb46
BUILD_HOST =		OmniOS r151038
# Image-wide incorporations remain supplied by the pinned builder image.  The
# lock captures the runtime dependencies actually selected on that baseline.
TOOLCHAIN_INSTALL_REJECTS =
GATE_COMPILER_NAME =	gcc7
GATE_CC =		/opt/gcc-7/bin/gcc
GATE_CXX =		/opt/gcc-7/bin/g++
SHIM_CC =		/opt/gcc-7/bin/gcc
SHIM_LD =		/usr/bin/ld
SHIM_COMPILER_PACKAGE = developer/gcc7
SHIM_LINKER_PACKAGE = developer/linker
GATE_LINT_MODE =	reproducible-stub
GATE_PREFIX_MAP_FLAG =	-fdebug-prefix-map
GATE_COMPILER_PACKAGE = developer/gcc7
GATE_JDK_PACKAGE =	runtime/java/openjdk11
GATE_JAVA_ROOT =	/usr/jdk/openjdk11.0
MF2TAR_RUST_TOOLCHAIN = 1.94.1
MF2TAR_CARGO_LOCK_SHA256 = e380d06971a59c26b82f1cd824d216180f37b9e960af4ed4235f20dba12bd7f2
GATE_TOOL_PACKAGES =	SUNWcs \
			package/pkg \
			shell/ksh93 \
			system/extended-system-utilities \
			compress/bzip2 \
			compress/gzip \
			compress/zip \
			runtime/perl \
			web/curl \
			developer/build/onbld \
			$(GATE_COMPILER_PACKAGE) \
			developer/build/gnu-make \
			developer/illumos-tools \
			$(GATE_JDK_PACKAGE) \
			developer/versioning/git
CLOSED_BINS_BASE_URL =	https://mirrors.omnios.org/illumos-gate
CLOSED_BINS_ARCHIVE =	on-closed-bins.i386.tar.bz2
CLOSED_BINS_SHA256 =	18e82bace8481dca62586e4bdff7f6b44fc63b41443799929e4d4b2187e98535
CLOSED_BINS_ND_ARCHIVE = on-closed-bins-nd.i386.tar.bz2
CLOSED_BINS_ND_SHA256 = da3ca1ea24972ba6a01169265d8d38a45789ed7cc45334bfe026c108b1d2ff56
SOURCE_DATE_EPOCH ?=	1762459338
LIBGCC_VERSION =	4_8_0

# Compatibility names used by older callers.
GATE_BRANCH =		$(BUILD_HEAD_REF)
GATE_COMMIT =		$(BUILD_HEAD_COMMIT)

INCLUDE_PACKAGES =	system/header \
			system/library \
			system/library/math \
			system/library/c-runtime \
			system/library/security/gss
