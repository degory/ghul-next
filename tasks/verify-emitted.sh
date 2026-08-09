#!/bin/bash
# Verify every assembly the integration suite emitted.
#
# Run the suite first with artifacts kept, or this sees only the
# failures — a passing test deletes what it built:
#
#   GHUL_TEST_KEEP_ARTIFACTS=1 dotnet ghul-test integration-tests
#   tasks/verify-emitted.sh
#
# Two checks, because neither covers the other. ILVerify decodes each
# body and resolves every token, which is far more thorough about the
# IL a method contains than reading tables would be; it says nothing
# about a method that contains none, and reports an assembly whose
# every method row points at nothing as fully verified. `mdump --verify`
# covers that.
#
# By default only assemblies from *passing* tests are checked. A failing
# test's assembly is expected to be wrong, and is often stale — left
# from an earlier run that got as far as emitting something. Pass --all
# to include them anyway.
set -u

cd "$(dirname "$0")/.."

only_passing=1

if [ "${1:-}" = "--all" ]; then
    only_passing=0
fi

framework=$(ls -d /usr/lib/dotnet/shared/Microsoft.NETCore.App/*/ 2>/dev/null | sort -V | tail -1)

if [ -z "$framework" ]; then
    echo "no shared framework found; ILVerify needs one to resolve references" >&2
    exit 2
fi

mdump=tools/mdump/bin/Debug/net10.0/mdump.dll

if [ ! -f "$mdump" ]; then
    echo "building mdump" >&2
    dotnet build tools/mdump/mdump.ghulproj -v:q -nologo || exit 2
fi

# ILVerify enforces full verifiability, which is stricter than what the
# runtime rejects. These two are emitted deliberately and by both back
# ends, so reporting them would bury everything else.
noise='ThisUninitReturn|InitLocals'

checked=0
violations=0

for assembly in integration-tests/*/*/binary.exe; do
    [ -f "$assembly" ] || continue

    directory=$(dirname "$assembly")

    if [ "$only_passing" = 1 ] && [ -f "$directory/failed" ]; then
        continue
    fi

    checked=$((checked + 1))

    if ! dotnet "$mdump" --verify "$assembly"; then
        violations=$((violations + 1))
    fi

    output=$(cd "$directory" && ilverify binary.exe -r "$framework/*.dll" -r "*.dll" 2>&1 |
        grep '^\[IL\]: Error' | grep -Ev "\[($noise)\]")

    if [ -n "$output" ]; then
        echo "$output" | sed "s|^|$directory |"
        violations=$((violations + 1))
    fi
done

echo "checked $checked assemblies, $violations with findings"

[ "$violations" = 0 ]
