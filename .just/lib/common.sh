#!/usr/bin/env bash
# Shared utilities for template sync system

# Validate a manifest filepath before any filesystem use
# (guards update_from_template against path traversal from a
# compromised or misconfigured manifest; see #347)
validate_filepath() {
	local filepath="$1"

	# The sync system is chartered to manage only the .just/ tree
	[[ "$filepath" == .just/* ]] || return 1
	# Reject backslashes and embedded quotes (also break jq interpolation)
	[[ ! "$filepath" =~ [\\\"] ]] || return 1
	# Reject any .. path segment (whole segments only; a filename
	# like "..." is odd but legal, not a traversal)
	local -a segments=()
	IFS='/' read -ra segments <<< "$filepath"
	local segment
	for segment in "${segments[@]}"; do
		[[ "$segment" == ".." ]] && return 1
	done

	return 0
}

# Platform-compatible checksum computation
compute_checksum() {
	local file="$1"
	if command -v sha256sum &>/dev/null; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum &>/dev/null; then
		shasum -a 256 "$file" | awk '{print $1}'
	else
		echo "Error: Neither sha256sum nor shasum found" >&2
		exit 1
	fi
}
