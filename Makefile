#
# Makefile for the generation of illumos sysroot archives.
#

MACH =			i386
MACH64 =		amd64

PROFILES =		$(wildcard profiles/*.mk)
AVAILABLE_RELEASES =	$(patsubst profiles/%.mk,%,$(PROFILES))

ifneq ($(RELEASE),)
PROFILE =		profiles/$(RELEASE).mk
ifeq ($(wildcard $(PROFILE)),)
$(error unknown RELEASE "$(RELEASE)" (available: $(AVAILABLE_RELEASES)))
endif
include $(PROFILE)
endif

ifneq ($(SOURCE_DATE_EPOCH),)
export SOURCE_DATE_EPOCH
endif

OUTPUT ?=		output
TARBASE ?=		illumos-sysroot-$(MACH)
TARVERSION ?=		custom-v$(shell date +%Y%m%d-%H%M%S)
TARFILE ?=		$(OUTPUT)/$(TARBASE)-$(TARVERSION).tar

#
# When producing the official archive, override TARVERSION; e.g.
#	gmake archive TARVERSION=de6af22ae73b-20181213-v1
#

USRLIB ?=		usr/lib
USRLIB64 ?=		usr/lib/$(MACH64)

MF2TAR ?=		$(PWD)/mf2tar/target/release/mf2tar

#
# A list of IPS packages to include in the sysroot archive.  Note that no
# dependency resolution is done, so if you need the dependencies for an
# included package you must enumerate them explicitly here as well.
#
INCLUDE_PACKAGES ?=	system/header \
			system/library \
			system/library/math \
			system/library/c-runtime \
			system/library/security/gss

#
# A list of paths to exclude, even if they appear in the packages listed above.
# This is useful in order to omit files from larger packages that contain
# things other than just headers and libraries, in order to keep the size of
# the sysroot archive down.
#
EXCLUDE_DIRS ?=		usr/share \
			etc \
			var \
			usr/bin \
			usr/sbin \
			usr/ccs \
			sbin \
			bin

LIBGCC_VERSION ?=	4_8_0
PREBUILT_SHIMS ?=	false
PREBUILT_SHIM_DIR ?=

#
# Shim libraries that we generate for artefacts that come from consolidations
# other than illumos-gate, but which are expected to appear in /usr/lib in
# every illumos distribution:
#
LIBGCC_32 =		shims/libgcc_s/$(MACH)/libgcc_s.so.1
LIBGCC_64 =		shims/libgcc_s/$(MACH64)/libgcc_s.so.1
LIBSSP_32 =		shims/libssp/$(MACH)/libssp.so.0.0.0
LIBSSP_64 =		shims/libssp/$(MACH64)/libssp.so.0.0.0

SHIM_TARGETS  =		$(LIBGCC_32) $(LIBGCC_64) $(LIBSSP_32) $(LIBSSP_64)

ifeq ($(PREBUILT_SHIMS),true)
LIBGCC_32 =		$(PREBUILT_SHIM_DIR)/$(USRLIB)/libgcc_s.so.1
LIBGCC_64 =		$(PREBUILT_SHIM_DIR)/$(USRLIB64)/libgcc_s.so.1
LIBSSP_32 =		$(PREBUILT_SHIM_DIR)/$(USRLIB)/libssp.so.0.0.0
LIBSSP_64 =		$(PREBUILT_SHIM_DIR)/$(USRLIB64)/libssp.so.0.0.0
SHIM_PREREQS =		check-prebuilt-shims
else
SHIM_PREREQS =		$(SHIM_TARGETS)
endif

.PHONY: all
all: archive

.PHONY: shims
shims: $(SHIM_PREREQS)

$(LIBGCC_32) $(LIBGCC_64):
	$(MAKE) -C shims/libgcc_s VERSION=$(LIBGCC_VERSION)

$(LIBSSP_32) $(LIBSSP_64):
	$(MAKE) -C shims/libssp

.PHONY: check-prebuilt-shims
check-prebuilt-shims:
	@if [ -z "$(PREBUILT_SHIM_DIR)" ]; then \
		printf 'ERROR: specify PREBUILT_SHIM_DIR when PREBUILT_SHIMS=true\n' >&2; \
		exit 1; \
	fi
	@for shim in \
		"$(LIBGCC_32)" \
		"$(LIBGCC_64)" \
		"$(LIBSSP_32)" \
		"$(LIBSSP_64)"; do \
		if [ ! -f "$$shim" ]; then \
			printf 'ERROR: missing prebuilt shim: %s\n' "$$shim" >&2; \
			exit 1; \
		fi; \
	done

.PHONY: $(MF2TAR)
$(MF2TAR):
	cd mf2tar && cargo build --release

$(OUTPUT):
	mkdir -p $@

.PHONY: check-pkgrepo
check-pkgrepo:
	@if [ -z "$(ILLUMOS_PKGREPO)" ] || \
		[ ! -d "$(ILLUMOS_PKGREPO)/file" ] || \
		[ ! -d "$(ILLUMOS_PKGREPO)/pkg" ]; then \
		printf 'ERROR: specify valid ILLUMOS_PKGREPO location with file/ and pkg/ directories\n' >&2; \
		exit 1; \
	fi

.PHONY: ident
ident:
	@printf 'release: %s\n' '$(if $(RELEASE),$(RELEASE),(none: custom build))'
	@printf 'tarversion: %s\n' '$(TARVERSION)'
	@printf 'gate branch: %s\n' '$(if $(GATE_BRANCH),$(GATE_BRANCH),(none))'
	@printf 'gate commit: %s\n' '$(if $(GATE_COMMIT),$(GATE_COMMIT),(none))'
	@printf 'build host: %s\n' '$(if $(BUILD_HOST),$(BUILD_HOST),(unspecified))'
	@printf 'source date epoch: %s\n' '$(if $(SOURCE_DATE_EPOCH),$(SOURCE_DATE_EPOCH),(current time))'
	@printf 'libgcc_s version: %s\n' '$(LIBGCC_VERSION)'
	@printf 'packages: %s\n' '$(INCLUDE_PACKAGES)'

.PHONY: print-packages
print-packages:
	@printf '%s\n' $(INCLUDE_PACKAGES)

.PHONY: archive
archive: check-pkgrepo $(SHIM_PREREQS) | $(OUTPUT) $(MF2TAR)
	$(MF2TAR) \
	    --repository $(ILLUMOS_PKGREPO) \
	    $(addprefix -P ,$(INCLUDE_PACKAGES)) \
	    $(addprefix -E ,$(EXCLUDE_DIRS)) \
	    \
	    --file $(USRLIB)/libgcc_s.so.1=$(LIBGCC_32) \
	    --file $(USRLIB64)/libgcc_s.so.1=$(LIBGCC_64) \
	    --link $(USRLIB)/libgcc_s.so=libgcc_s.so.1 \
	    --link $(USRLIB64)/libgcc_s.so=libgcc_s.so.1 \
	    \
	    --file $(USRLIB)/libssp.so.0.0.0=$(LIBSSP_32) \
	    --file $(USRLIB64)/libssp.so.0.0.0=$(LIBSSP_64) \
	    --link $(USRLIB)/libssp.so.0=libssp.so.0.0.0 \
	    --link $(USRLIB)/libssp.so=libssp.so.0.0.0 \
	    --link $(USRLIB64)/libssp.so.0=libssp.so.0.0.0 \
	    --link $(USRLIB64)/libssp.so=libssp.so.0.0.0 \
	    \
	    $(TARFILE)
	gzip -n < $(TARFILE) > $(TARFILE).gz

.PHONY: clean
clean:
	rm -rf $(PROTO) $(MAKE_STAMPS_DIR)
	$(MAKE) -C shims/libgcc_s clean
	$(MAKE) -C shims/libssp clean

.PHONY: clobber
clobber: clean
	cd mf2tar && cargo clean
	rm -rf $(OUTPUT)
