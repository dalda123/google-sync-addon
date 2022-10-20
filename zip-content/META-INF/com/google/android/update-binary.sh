#!/sbin/sh
# -*- coding: utf-8 -*-
# SPDX-FileCopyrightText: (c) 2016 ale5000
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileType: SOURCE

# shellcheck disable=SC3043
# SC3043: In POSIX sh, local is undefined

set -u
# shellcheck disable=SC3040
set -o pipefail || true
umask 022

### GLOBAL VARIABLES ###

export OUTFD="${2:?}"
export ZIPFILE="${3:?}"

### FUNCTIONS AND CODE ###

echo 'PRELOADER 1'

# Detect whether we are in boot mode
_updatebin_detect_bootmode()
{
  if test -n "${BOOTMODE:-}"; then return; fi
  BOOTMODE=false
  # shellcheck disable=SC2009
  ps | grep zygote | grep -qv grep && BOOTMODE=true
  # shellcheck disable=SC2009
  "${BOOTMODE:?}" || {
    ps -A 2> /dev/null | grep zygote | grep -qv grep && BOOTMODE=true
  }
  export BOOTMODE
}

_show_text_on_recovery()
{
  if test "${BOOTMODE:?}" = 'true'; then
    printf '%s\n' "${1?}"
    return
  elif test -e "/proc/self/fd/${OUTFD:?}"; then
    printf 'ui_print %s\nui_print\n' "${1?}" >> "/proc/self/fd/${OUTFD:?}"
  else
    printf 'ui_print %s\nui_print\n' "${1?}" 1>&"${OUTFD:?}"
  fi
}

ui_error()
{
  ERROR_CODE=79
  if test -n "${2:-}"; then ERROR_CODE="${2:?}"; fi
  _show_text_on_recovery "ERROR: ${1:?}"
  printf 1>&2 '\033[1;31m%s\033[0m\n' "ERROR ${ERROR_CODE:?}: ${1:?}"
  abort '' 2> /dev/null || exit "${ERROR_CODE:?}"
}

set_perm()
{
  local uid="${1:?}"
  local gid="${2:?}"
  local mod="${3:?}"
  shift 3
  chown "${uid:?}:${gid:?}" "${@:?}" || chown "${uid:?}.${gid:?}" "${@:?}" || ui_error "chown failed on: $*"
  chmod "${mod:?}" "${@:?}" || ui_error "chmod failed on: $*"
}

package_extract_file()
{
  unzip -opq "${ZIPFILE:?}" "${1:?}" 1> "${2:?}" || ui_error "Failed to extract the file '${1}' from this archive"
  if ! test -e "${2:?}"; then ui_error "Failed to extract the file '${1}' from this archive"; fi
}

_updatebin_detect_bootmode
_updatebin_we_mounted_tmp=false

# Workaround: Create (if needed) and mount the temp folder if it isn't already mounted
{
  _updatebin_is_mounted()
  {
    local _mount_result
    {
      test -e '/proc/mounts' && _mount_result="$(cat /proc/mounts)"
    } || _mount_result="$(mount 2> /dev/null)" || ui_error '_updatebin_is_mounted has failed'

    case "${_mount_result:?}" in
      *[[:blank:]]"${1:?}"[[:blank:]]*) return 0 ;; # Mounted
      *) ;;                                         # NOT mounted
    esac
    return 1 # NOT mounted
  }

  TMPDIR="${TMPDIR:-}"
  if test -n "${TMPDIR?}"; then
    : # Already ready
  elif _updatebin_is_mounted '/tmp'; then
    TMPDIR='/tmp'
  elif _updatebin_is_mounted '/dev/tmp'; then
    TMPDIR='/dev/tmp'
  else
    _updatebin_we_mounted_tmp=true

    _show_text_on_recovery 'WARNING: Creating (if needed) and mounting the temp folder...'
    printf 1>&2 '\033[0;33m%s\033[0m\n' 'WARNING: Creating (if needed) and mounting the temp folder...'
    if test ! -e '/tmp'; then
      mkdir -p -- '/tmp' || ui_error 'Failed to create the temp folder'
      set_perm 0 0 0755 '/tmp'
    fi

    mount -t tmpfs -o rw -- tmpfs '/tmp' || ui_error 'Failed to mount the temp folder'
    set_perm 0 2000 0775 '/tmp'

    if ! _updatebin_is_mounted '/tmp'; then ui_error 'The temp folder CANNOT be mounted'; fi
    TMPDIR='/tmp'
  fi
  unset -f _updatebin_is_mounted || ui_error 'Failed to unset _updatebin_is_mounted'

  if test ! -e "${TMPDIR:?}"; then
    ui_error 'The temp folder is missing'
  fi
  export TMPDIR
}

# Seed the RANDOM variable
RANDOM="${$:?}${$:?}"

# shellcheck disable=SC3028
{
  if test "${RANDOM:?}" = "${$:?}${$:?}"; then ui_error "\$RANDOM is not supported"; fi # Both BusyBox and Toybox support $RANDOM
  _updatebin_our_main_script="${TMPDIR:?}/${RANDOM:?}-customize.sh"
}

STATUS=1
UNKNOWN_ERROR=1

package_extract_file 'customize.sh' "${_updatebin_our_main_script:?}"
# shellcheck source=SCRIPTDIR/../../../../customize.sh
. "${_updatebin_our_main_script:?}" || ui_error "Failed to source customize.sh"
rm -f "${_updatebin_our_main_script:?}" || ui_error "Failed to delete customize.sh"
unset _updatebin_our_main_script

if test "${_updatebin_we_mounted_tmp:?}" = true; then
  umount '/tmp' || ui_error 'Failed to unmount the temp folder'
fi

if test "${STATUS:?}" -ne 0; then ui_error "Installation script failed with error ${STATUS}" "${STATUS}"; fi
if test "${UNKNOWN_ERROR:?}" -ne 0; then ui_error 'Installation failed with an unknown error'; fi
