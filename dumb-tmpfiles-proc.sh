#!/bin/bash

##
## This is a simple tmpfiles.d handler that is used for creating the
## filesystem hierarchy in baselayout, it's not a general purpose
## tmpfiles.d processor. It takes the UID and GID information from
## environment variables - for user foo-bar, the environment variable
## FOO_BAR_UID will be checked for the user ID and FOO_BAR_GID - for
## group ID. The destination directory where the entries will be
## created can be specified with the DESTDIR environment variable. If
## not specified, defaults to /.
##
## Flags:
##
## -h, --help
##     Print this help.
##
## -e <TYPES>, --exclude <TYPES>
##     Exclude entries of given types. Will be ignored for entries
##     being parent directories of not-ignored entries.
##
## -d, --dry-run
##     Print the commands instead of executing them.
##
## The command takes one positional parameter only - a path to a
## directory with tmpfiles.d config files.
##

set -euo pipefail

shopt -s extglob

: "${DESTDIR=}"

function fail {
    printf '%s\n' "${*}" >&2
    exit 1
}

THIS=${0}
EXCLUDE=''
DRY_RUN=''

function usage {
    grep -e '^##' "${THIS}" | sed -e 's/^##[[:space:]]*//'
}

while [[ -n ${1:-} ]]; do
    case ${1} in
        -d|--dry-run)
            DRY_RUN=x
            shift
            ;;
        -e|--exclude)
            EXCLUDE=${2}
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            fail "Unknown flag ${1@Q}"
            ;;
        *)
            break
            ;;
    esac
done

if [[ ${#} -ne 1 ]]; then
    usage
    fail "Expected exactly one parameter, got ${#}"
fi

TMPFILES_D=${1}

function id_to_numeric_or_empty {
    local -n ref=${1}
    local suffix=${2}
    local name

    if [[ ${ref} = - ]]; then
        ref=''
    else
        name="${ref^^}_${suffix}"
        name=${name//-/_}
        if [[ -z ${!name+isset} ]]; then
            fail "Need ${name@Q} env var for ${suffix} of ${ref}"
        fi
        ref=${!name}
    fi
}

mapfile -t ORDERED < <(grep --no-filename '^[^#]' "${TMPFILES_D}"/*.conf)
declare -A PATH_TO_ORDERED_INDEX=()

LINE_ARGS=('type' 'path' 'mode' 'user' 'group' 'age' 'arg')

for idx in "${!ORDERED[@]}"; do
    entry=${ORDERED["${idx}"]}
    read -r "${LINE_ARGS[@]}" <<<"${entry}"
    PATH_TO_ORDERED_INDEX["${path}"]=${idx}
done

function add_index {
    local idx=${1}; shift
    local parent_indices_array_ref_name=${1}; shift
    local indices_visited_map_ref_name=${1}; shift

    local -n indices_visited_map_ref=${indices_visited_map_ref_name}

    if [[ -n ${indices_visited_map_ref["${idx}"]:-} ]]; then
        # index already visited
        return 0
    fi

    local "${LINE_ARGS[@]}"
    read -r "${LINE_ARGS[@]}" <<<${ORDERED["${idx}"]}

    local parent_path=${path%/*}
    if [[ -n ${parent_path} ]]; then
        local parent_idx=${PATH_TO_ORDERED_INDEX["${parent_path}"]:-}
        if [[ -z ${parent_idx} ]]; then
            fail "no entry for ${parent_path@Q} in tmpfiles"
        fi

        add_index "${parent_idx}" "${parent_indices_array_ref_name}" "${indices_visited_map_ref_name}"
    fi

    local -n parent_indices_array_ref=${parent_indices_array_ref_name}

    indices_visited_map_ref["${idx}"]=x
    parent_indices_array_ref+=( "${idx}" )
}

declare -a indices_to_do=()
declare -A indices_visited=()

for current_idx in "${!ORDERED[@]}"; do
    entry=${ORDERED["${current_idx}"]}
    read -r "${LINE_ARGS[@]}" <<<"${entry}"
    if [[ ${EXCLUDE} = *"${type}"* ]]; then
        continue
    fi
    dpath=${DESTDIR}${path}
    if [[ -e ${dpath} ]]; then
        continue
    fi
    add_index  "${current_idx}" indices_to_do indices_visited
    current_idx=$((current_idx+1))
done

function do_or_do_not {
    if [[ -n ${DRY_RUN} ]]; then
        printf '%s\n' "${*}"
    else
        "${@}"
    fi
}

for idx in "${indices_to_do[@]}"; do
    line=${ORDERED["${idx}"]}
    read -r "${LINE_ARGS[@]}" <<<${line}
    dpath=${DESTDIR}${path}
    if [[ -e ${dpath} ]] && [[ ${type} != *+ ]]; then
        continue
    fi
    skip=
    case ${type} in
        d)
            flags=()
            if [[ ${mode} != - ]]; then
                flags+=( -m "${mode}" )
            fi
            do_or_do_not mkdir "${flags[@]}" "${dpath}"
            unset flags
            ;;
        L) do_or_do_not ln -snf "${arg}" "${dpath}";;
        L+)
            if [[ -e ${dpath} ]]; then
                if [[ -L ${dpath} ]] || [[ ! -d ${dpath} ]]; then
                    do_or_do_not rm -f "${dpath}"
                else
                    do_or_do_not rm -rf "${dpath}"
                fi
            fi
            do_or_do_not ln -snf "${arg}" "${dpath}"
            ;;
        C) do_or_do_not cp "${DESTDIR}${arg}" "${dpath}";;
        Z) skip=x;;
        *) fail "Unknown type ${type@Q} in line ${line@Q}";;
    esac
    if [[ -n ${skip} ]]; then continue; fi
    id_to_numeric_or_empty user UID
    id_to_numeric_or_empty group GID
    if [[ "${user}:${group}" != ':' ]]; then do_or_do_not chown "${user}:${group}" "${dpath}"; fi
done
