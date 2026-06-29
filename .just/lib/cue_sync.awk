# cue_sync.awk - state-aware [about] block updater for cue-sync-from-github
#
# Invoked by the cue-sync-from-github recipe in .just/cue-verify.just and by
# the test runner .just/lib/cue_sync_test.sh. Keeping the program in a single
# file guarantees both callers run identical awk logic; a change here is
# automatically exercised by both paths. See issue #196.
#
# Variables expected from -v:
#   desc   - escaped description string (quotes already backslashed)
#   topics - TOML topics array literal, e.g. ["a", "b"]
#
# State-aware: handles three cases for each key (description, topics):
#   1. Active line (e.g. `topics = [...]`)        -> replace in place
#   2. Commented line (e.g. `# topics = [...]`)   -> replace in place
#   3. Missing line                               -> insert inside [about] block
# The `[#[:space:]]*` prefix tolerates a leading `#` and optional space so
# commented-out keys are still matched and rewritten. Missing keys are
# inserted at the end of the `[about]` block, *before* any trailing blank
# line that separates it from the next section. This is achieved by
# buffering blank lines while inside `[about]` and flushing them only
# after any pending missing-key insertions, so the inserted key lands
# adjacent to the preceding key (e.g. `license`) rather than after the
# blank line (which would visually attach it to the next `[section]`).
# Missing keys are flushed either when the next `[section]` begins or at
# EOF (END block), preserving the original field order of any other keys
# in [about]. See issue #165 for the failure modes this addresses.
function flush_blanks() { if (blanks != "") { printf "%s", blanks; blanks="" } }
/^\[about\]/ { in_about=1; flush_blanks(); print; next }
/^\[/ && !/^\[about\]/ {
    if (in_about) {
        if (!desc_written)   { print "description = \"" desc "\""; desc_written=1 }
        if (!topics_written) { print "topics = " topics; topics_written=1 }
    }
    in_about=0
    flush_blanks()
    print
    next
}
in_about && /^[#[:space:]]*description[[:space:]]*=/ { flush_blanks(); print "description = \"" desc "\""; desc_written=1; next }
in_about && /^[#[:space:]]*topics[[:space:]]*=/      { flush_blanks(); print "topics = " topics; topics_written=1; next }
in_about && /^[[:space:]]*$/ { blanks=blanks "\n"; next }
{ flush_blanks(); print }
END {
    if (in_about) {
        if (!desc_written)   { print "description = \"" desc "\""; desc_written=1 }
        if (!topics_written) { print "topics = " topics; topics_written=1 }
    }
    flush_blanks()
}