# vim:noexpandtab:sw=2 ts=2

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))
ROOT_TEST:=$(dir $(lastword $(MAKEFILE_LIST)))

@echo "mkfile_path: $(mkfile_path)"
@echo "current_dir: $(current_dir)"
ROOT=$(ROOT_TEST)

DIFF_OPTIONS=
DIFF_OPTIONS+=-I "Created with"

# CMP:=cmp
# DIFF:=diff $(DIFF_OPTIONS)

# Cygwin or Linux
echo "ROOT: $(ROOT)"
DIFF := "$(ROOT)test/usp_diff.sh"
CMP := "$(ROOT)test/usp_cmp.sh"