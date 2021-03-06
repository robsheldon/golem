#!/bin/bash

# This is a special part of the "golem" script management system. It is not a
# good example of how to write a proper golem script because this file gets
# sourced instead of being executed in the normal way. The import function
# needs to be closely coupled with the rest of the script environment to
# properly manage the cache. Trying to convert this into a normal golem
# command script would be Very Difficult.

##
# Update the command script cache.
# 
_cache_update ()
{
    filename="$1"
    file_basename="$(path_basename "$filename")"
    if [ "$file_basename" = "import_script" ]; then
        fail "You have tried to import the import script. The infinite recursion that would result would cause a singularity that would eventually expand into all of time and space. That is probably not what you intended, so have this error message instead."
    fi
    # Delete any copies of this file currently in the cache.
    find -P "$scriptdir/.cache" -maxdepth 1 -name "$file_basename.*" -delete
    # Also delete any previous "-failed" scripts (files that did not successfully
    # get imported).
    find -P "$scriptdir/scripts" -maxdepth 1 -name "$file_basename.*-failed" -delete
    sourcefiles=("$scriptdir"/scripts/"$file_basename".*)
    if [ ${#sourcefiles[@]} -gt 1 ]; then
        fail "There are multiple files in the $scriptdir/scripts matching the pattern $file_basename.*. There should be only one match for that pattern. Please rename some of them."
    fi
    if [ ${#sourcefiles[@]} -lt 1 ] || [ "${sourcefiles[0]}" = "$scriptdir/scripts/$file_basename.*" ]; then
        # TODO: It would be pretty cool if the .cache directory weren't already
        # cleaned up at this point and a cached copy of this file could be
        # retrieved if some disaster had befallen the hapless user.
        fail "The original source file matching \"$file_basename\" has disappeared."
    fi
    sourcefile="${sourcefiles[0]}"
    # What happens next depends on the file extension for the source file.
    sourcetype=$(path_extension "$sourcefile")
    cachedfile=""
    warning="# Do not modify this file! This file is automatically generated from the source\\n# file at $sourcefile.\\n# Modify that file instead.\\n\\n"
    sudowarmup="# This script appears to require sudo, so make sure the user has the necessary access.\\n# If they do, then run a sudo command now so that script execution doesn't trip\\n# on a password prompt later.\\nif ! groups | grep -qw '\\(sudo\\|root\\)'; then\\n    fail \"It looks like this command script requires superuser access and you're not in the 'sudo' group\"\\nelif [ \"\$(sudo whoami </dev/null)\" != \"root\" ]; then\\n    fail \"Your 'sudo' command seems to be broken\"\\nfi\\n\\n"
    case "$sourcetype" in
        .sh)
            shellcheck=$(command -v shellcheck)
            if [ -n "$shellcheck" ]; then
                # Run shellcheck on the source file before using it, if available.
                if ! $shellcheck "$sourcefile" >/dev/null 2>&1; then
                    fail "The command script in $sourcefile isn't passing shellcheck. Please run \"shellcheck $sourcefile\", fix it, and then try again."
                fi
            fi
            # Shellcheck succeeded or is not available.
            cachedfile="$scriptdir/.cache/$file_basename.sh"
            # Nuke the 'sudo warmup' if it's not needed for this script.
            if ! grep -q '^[[:space:]]*sudo ' "$sourcefile"; then
                sudowarmup=""
            fi
            # Inject the golem public code into this shell script.
            # See https://unix.stackexchange.com/a/193498 for an explanation of
            # this line noise.
            sed -n "/^# begin-golem-injected-code$/,/^# end-golem-injected-code$/p" "$scriptpath" | xargs -0 printf "\\n$warning\\n%s\\n$sudowarmup" | sed '/^\s*[^#]\+/{;r /dev/stdin
                N;:l;$!n;$!bl;};${;/^$/!{;s/\\n$//;};//d;}' "$sourcefile" <(printf \\n) >"$cachedfile"
            if [ -n "$shellcheck" ]; then
                # Run shellcheck one more time on the completed cached file.
                if ! $shellcheck "$cachedfile" >/dev/null 2>&1; then
                    fail "There was a conflict between \"$sourcefile\" and the golem code that gets added to command scripts. Please run \"shellcheck $cachedfile\" and then try again."
                fi
            fi
        ;;
        .mdsh)
            # If mdsh is present, then markdown files ending in ".mdsh" can be
            # executed as commands if they pass all the sanity checks.
            mdsh=$(command -v mdsh)
            if [ -z "$mdsh" ]; then
                fail "mdsh is not installed or available in the current \$PATH. See https://github.com/bashup/mdsh for more information."
            fi
            shellcheck=$(command -v shellcheck)
            if [ -z "$shellcheck" ]; then
                fail "shellcheck is required for converting markdown documents to shell scripts. See https://github.com/koalaman/shellcheck for more information."
            fi
            # We really want to avoid getting a half-broken shell script in
            # the cache directory, so a temporary file is used here.
            tempfile=$(mktemp /tmp/golem.XXXXXX)
            # The next line constructs a special mdsh function to handle "bash"
            # language blocks; it natively only handles "shell" language blocks.
            # That function gets injected into the top of the input and then
            # passed to mdsh.
            if ! echo -e '```shell @mdsh\nmdsh-compile-bash(){ printf "%s" "$1";}\n```\n\n' | cat - "$sourcefile" | $mdsh --compile - >"$tempfile" 2>&1; then
                rm "$tempfile"
                fail "mdsh was unable to parse this file: \"$sourcefile\""
            fi
            # mdsh may parse the file as a raw block; make sure that didn't happen.
            if ! grep -q -v '^\s*\(mdsh_raw[a-zA-Z_:-]*+=.*\)\?$' "$tempfile"; then
                rm "$tempfile"
                fail "mdsh did not correctly parse this file: \"$sourcefile\". Make sure it has code blocks beginning with \"\`\`\`bash\"."
            fi
            # So far, so good. Make sure the file has a "#!" near the top.
            # This is required for shellcheck to work properly.
            firstline=$(grep -v -m 1 '^\s*\(#[^!].*\)\?$' "$tempfile")
            if [[ ! "$firstline" =~ "^#!" ]]; then
                # Add an execution tag here.
                sed -i '1s:^:#!/bin/bash\n\n:' "$tempfile"
            fi
            # Copy the file out of /tmp now; it should be possible for the user
            # to review the compiled file if any errors are encountered after
            # this point.
            cat "$tempfile" > "$sourcefile-failed"
            rm "$tempfile"
            tempfile="$sourcefile-failed"
            # Shellcheck it. This is -required- for scripts imported through mdsh.
            if ! $shellcheck "$tempfile" >/dev/null 2>&1; then
                fail "The file converted by mdsh did not pass shellcheck. You can review the compiled file at \"$tempfile\"."
            fi
            # Nuke the 'sudo warmup' if it's not needed for this script.
            if ! grep -q '^[[:space:]]*sudo ' "$tempfile"; then
                sudowarmup=""
            fi
            # Use the sed line noise to generate the file in the cache.
            cachedfile="$scriptdir/.cache/$file_basename.sh"
            sed -n "/^# begin-golem-injected-code$/,/^# end-golem-injected-code$/p" "$scriptpath" | xargs -0 printf "\\n$warning\\n%s\\n$sudowarmup" | sed '/^\s*[^#]\+/{;r /dev/stdin
                N;:l;$!n;$!bl;};${;/^$/!{;s/\\n$//;};//d;}' "$tempfile" <(printf \\n) >"$cachedfile"
            if ! $shellcheck "$cachedfile" >/dev/null 2>&1; then
                mv "$cachedfile" "$tempfile"
                fail "\"$sourcefile\" was successfully converted to a shell script by mdsh but failed a shellcheck test when golem functions were added to it. You can review the compiled file at \"$tempfile\"."
                cachedfile=""
            fi
            # The markdown script passed all tests. Nice!
            rm "$tempfile"
            ;;
        *)
            # All other file types: just copy the file into the cache and hope
            # the user knows what they're doing.
            filename=$(path_filename "$sourcefile")
            cachedfile="$scriptdir/.cache/$filename"
            cp "$sourcefile" "$cachedfile"
        ;;
    esac
    if [ -n "$cachedfile" ]; then
        chmod 0775 "$cachedfile"
        touch -r "$sourcefile" "$cachedfile"
    fi
    echo "$cachedfile"
    return 0
}


##
# Delete a command script from the cache, if it exists, and re-import it from
# a source. The source may be in the golem "scripts" directory, or may be an
# external script file that is to be added to the scripts directory and the
# command script cache.
_import_script () {
    invocation="$*"
    # Read parameters.
    sourcefile="$1"; shift
    destcmd=""
    if [ $# -gt 0 ] && [ "$1" = "as" ]; then
        shift
    fi
    if [ $# -gt 0 ]; then
        destcmd="$1"
        shift
    fi
    if [ $# -gt 0 ]; then
        fail "Wrong parameter count in _import_script. Invocation was: $invocation"
    fi
    if [ -z "$destcmd" ]; then
        # If no "as <command>" was provided, then this is an internal cache update.
        cached=$(_cache_update "$sourcefile")
        if [ -f "$cached" ]; then
            echo "Successfully imported $sourcefile"
        else
            fail "$cached"
        fi
    else
        # Ensure the sourcefile exists.
        if [ ! -f "$sourcefile" ]; then
            fail "file does not exist: $sourcefile"
        elif [ ! -r "$sourcefile" ]; then
            fail "file exists but is not readable: $sourcefile" 
        fi
        destfile=$(echo "$destcmd" | sed 's/ \+/_/g')
        matched=$(find -P "$scriptdir/scripts" -maxdepth 1 -name "$destfile.*")
        if [ -n "$matched" ]; then
            matched=$(path_filename "$matched")
            if ! ask "\"$destcmd\" matches the file \"$matched\" in scripts/. Do you want to replace this file?"; then
                echo "Canceled."
                exit 1
            else
                rm "$scriptdir/scripts/$matched"
            fi
        fi
        dest_ext=$(path_extension "$sourcefile")
        if ! cp "$sourcefile" "$scriptdir/scripts/$destfile$dest_ext"; then
            fail "Copy failed."
        fi
        cached=$(_cache_update "$destfile")
        if [ -f "$cached" ]; then
            echo "Successfully imported \"$destcmd\" as \"$destfile$dest_ext\""
        else
            fail "$cached"
        fi
    fi
}
