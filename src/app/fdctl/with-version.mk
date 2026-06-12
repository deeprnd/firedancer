include src/app/fdctl/version.mk
FD_WITH_AGAVE ?= 0

ifeq ($(FD_WITH_AGAVE),1)
# These constants should match the Agave rust source code
# agave/version/src/v4.rs
AGAVE_IDENTIFIER_ALPHA := alpha
AGAVE_IDENTIFIER_BETA  := beta
AGAVE_IDENTIFIER_RELEASE_CANDIDATE := rc
AGAVE_ENCODE_TAG_ALPHA := 3
AGAVE_ENCODE_TAG_BETA  := 2
AGAVE_ENCODE_TAG_RELEASE_CANDIDATE := 1
AGAVE_ENCODE_TAG_STABLE := 0
AGAVE_PRERELEASE_BITS_OFFSET := 14

AGAVE_PRERELEASE_TAG := $(AGAVE_ENCODE_TAG_STABLE)

# get the agave version
AGAVE_VERSION := $(shell $(GREP) -Po "(?<=^version = \").*(?=\")" "agave/Cargo.toml")
# If the Agave submodule is not checked out, the above command fails
ifeq ($(AGAVE_VERSION),)
AGAVE_VERSION := 9.9.99
endif

# parse the agave semver
SEMVER_VERSION := $(firstword $(subst -, ,$(AGAVE_VERSION)))
AGAVE_VERSION_MAJOR := $(word 1,$(subst ., ,$(SEMVER_VERSION)))
AGAVE_VERSION_MINOR := $(word 2,$(subst ., ,$(SEMVER_VERSION)))
AGAVE_VERSION_PATCH := $(word 3,$(subst ., ,$(SEMVER_VERSION)))

# try to parse the prerelease version
SEMVER_PRERELEASE := $(word 2,$(subst -, ,$(AGAVE_VERSION)))
ifneq ($(SEMVER_PRERELEASE),)
  AGAVE_PRERELEASE_STRING  := $(word 1,$(subst ., ,$(SEMVER_PRERELEASE)))
  AGAVE_PRERELEASE_VERSION := $(word 2,$(subst ., ,$(SEMVER_PRERELEASE)))
endif

# if this is a prerelease, update the patch and set the tag
ifneq ($(AGAVE_PRERELEASE_STRING),)
  AGAVE_VERSION_PATCH := $(AGAVE_PRERELEASE_VERSION)
  ifeq ($(AGAVE_PRERELEASE_STRING),$(AGAVE_IDENTIFIER_RELEASE_CANDIDATE))
    AGAVE_PRERELEASE_TAG := $(AGAVE_ENCODE_TAG_RELEASE_CANDIDATE)
  else ifeq ($(AGAVE_PRERELEASE_STRING),$(AGAVE_IDENTIFIER_BETA))
    AGAVE_PRERELEASE_TAG := $(AGAVE_ENCODE_TAG_BETA)
  else ifeq ($(AGAVE_PRERELEASE_STRING),$(AGAVE_IDENTIFIER_ALPHA))
    AGAVE_PRERELEASE_TAG := $(AGAVE_ENCODE_TAG_ALPHA)
  endif
endif

# Frankendancer versioning is always major 0, the first full Firedancer
# release will be version 1.0
FIREDANCER_VERSION_MAJOR := $(VERSION_MAJOR)

# The minor version is a Firedancer specific version number, indicating
# which release candidate branch this is. Different Firedancer release
# branches could point to the same Agave patch.
FIREDANCER_VERSION_MINOR := $(VERSION_MINOR)$(shell printf "%02d" $(VERSION_PATCH))

# Agave version v4 encodes the prerelease bits in the minor version.
# We do the same to make sure the prerelease information does not get
# lost.  This is a no-op when the prerelease is Stable == 0.
FIREDANCER_VERSION_MINOR := $(shell echo $$(( $(FIREDANCER_VERSION_MINOR) | ($(AGAVE_PRERELEASE_TAG) << $(AGAVE_PRERELEASE_BITS_OFFSET)) )) )

# For Frankendancer, we stuff the entire Agave version that we are
# linking to in the patch version.  This transforms, for example, a full
# Agave version of "4.1.7" to a patch version of "40107".  If it is a
# prerelease like "4.1.0-beta.7", we use the prerelease version as the
# agave patch version and the frankendancer patch again becomes "40107"
# (NOT "40100").  The minor version carries the information that it is
# a prerelease even when the patch versions are the same.
FIREDANCER_VERSION_PATCH := $(shell printf "%d%02d%02d" $(AGAVE_VERSION_MAJOR) $(AGAVE_VERSION_MINOR) $(AGAVE_VERSION_PATCH))

export FIREDANCER_VERSION_MAJOR
export FIREDANCER_VERSION_MINOR
export FIREDANCER_VERSION_PATCH

# See src/flamenco/gossip/fd_gossip_message.h
# We adapt that logic to Frankendancer's unique versioning scheme which
# squeezes Agave's version into the patch number
FIREDANCER_VERSION_MINOR_ACTUAL := $(VERSION_MINOR)$(shell printf "%02d" $(VERSION_PATCH))
ifneq ($(AGAVE_PRERELEASE_TAG),0)
FIREDANCER_VERSION_CSTR := $(FIREDANCER_VERSION_MAJOR).$(FIREDANCER_VERSION_MINOR_ACTUAL).0-$(AGAVE_PRERELEASE_STRING).$(FIREDANCER_VERSION_PATCH)
else
FIREDANCER_VERSION_CSTR := $(FIREDANCER_VERSION_MAJOR).$(FIREDANCER_VERSION_MINOR).$(FIREDANCER_VERSION_PATCH)
endif
export FIREDANCER_VERSION_CSTR
