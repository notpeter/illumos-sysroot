TARVERSION =		20181213-de6af22ae73b-v3
RELEASE_BASE_COMMIT =	de6af22ae73ba8d72672288621ff50b88f2cf5fd
BUILD_HEAD_REF =	sysroot/20181213
BUILD_HEAD_COMMIT =	6265851cb0eea0e24c694164ca91635b4d414876
BUILD_HISTORY_DEPTH =	7
GATE_VERSION =		sysroot/20181213-0-g6265851cb0ee
BUILDER_RELEASE =	r151030
BUILDER_IMAGE_URL =	https://downloads.omnios.org/media/r151030/omnios-r151030ap.iso
BUILDER_IMAGE_SHA256 = 7c1936c6394af381b2541b35b55a817d2e8b2dea16478b30faaa5a63f9914006
BUILD_HOST =		OmniOS r151030
GATE_COMPILER_NAME =	gcc4
GATE_CC =		/opt/gcc-4.4.4/bin/gcc
GATE_CXX =		/opt/gcc-4.4.4/bin/g++
SHIM_CC =		/opt/gcc-7/bin/gcc
SHIM_LD =		/usr/bin/ld
SHIM_COMPILER_PACKAGE = developer/gcc7
SHIM_LINKER_PACKAGE = developer/linker
GATE_LINT_MODE =	reproducible-stub
GATE_PREFIX_MAP_FLAG =	-fdebug-prefix-map
GATE_COMPILER_PACKAGE = developer/gcc44
GATE_JDK_PACKAGE =	developer/java/openjdk8
GATE_JAVA_ROOT =	/usr/java
# Image-wide incorporations remain supplied by the pinned builder image.  The
# lock captures the runtime dependencies actually selected on that baseline.
TOOLCHAIN_INSTALL_REJECTS =
MF2TAR_RUST_TOOLCHAIN = 1.94.1
MF2TAR_CARGO_LOCK_SHA256 = e380d06971a59c26b82f1cd824d216180f37b9e960af4ed4235f20dba12bd7f2
GATE_TOOL_PACKAGES =	SUNWcs \
			package/pkg \
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
SOURCE_DATE_EPOCH ?=	1544726597
LIBGCC_VERSION =	4_8_0

# Compatibility names used by older callers.
GATE_BRANCH =		$(BUILD_HEAD_REF)
GATE_COMMIT =		$(BUILD_HEAD_COMMIT)

INCLUDE_PACKAGES =	system/header \
			system/library \
			system/library/math \
			system/library/c-runtime \
			system/library/security/gss

# The published v2 carries path-dependent proprietary Sun lint output.  It is
# not a runtime library and cannot be rebuilt from the durable open toolchain.
PROFILE_EXCLUDE_PATHS = lib/llib-lm.ln \
			lib/amd64/llib-lm.ln \
			usr/lib/llib-lm.ln \
			usr/lib/amd64/llib-lm.ln
