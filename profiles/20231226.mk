TARVERSION =		20231226-ae676b1204fb-v1
RELEASE_BASE_COMMIT =	ae676b1204fb703d5b394f9f8d947ef6210f3c3f
BUILD_HEAD_REF =	ae676b1204fb703d5b394f9f8d947ef6210f3c3f
BUILD_HEAD_COMMIT =	ae676b1204fb703d5b394f9f8d947ef6210f3c3f
BUILD_HISTORY_DEPTH =	1
GATE_VERSION =		sysroot/20231226-0-gae676b1204fb
BUILDER_RELEASE =	r151046
BUILDER_IMAGE_URL =	https://downloads.omnios.org/media/r151046/omnios-r151046.cloud.vmdk
BUILDER_IMAGE_SHA256 = 5f0e86f1f95b97df8fce63d6acfbf38f49fa4fe41b9e5ed9c7313f10fc180b3c
BUILD_HOST =		OmniOS r151046
# Image-wide incorporations remain supplied by the pinned builder image.  The
# lock captures the runtime dependencies actually selected on that baseline.
TOOLCHAIN_INSTALL_REJECTS =
GATE_COMPILER_NAME =	gcc10
GATE_CC =		/opt/gcc-10/bin/gcc
GATE_CXX =		/opt/gcc-10/bin/g++
SHIM_CC =		/opt/gcc-10/bin/gcc
SHIM_LD =		/usr/bin/ld
SHIM_COMPILER_PACKAGE = developer/gcc10
SHIM_LINKER_PACKAGE = developer/linker
GATE_LINT_MODE =	reproducible-stub
GATE_PREFIX_MAP_FLAG =	-ffile-prefix-map
GATE_COMPILER_PACKAGE = developer/gcc10
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
SOURCE_DATE_EPOCH ?=	1703608857
LIBGCC_VERSION =	4_8_0

# Compatibility names used by older callers.
GATE_BRANCH =		$(BUILD_HEAD_REF)
GATE_COMMIT =		$(BUILD_HEAD_COMMIT)

INCLUDE_PACKAGES =	system/header \
			system/library \
			system/library/math \
			system/library/c-runtime \
			system/library/security/gss
