#!/usr/bin/env bash
# shellcheck disable=SC3043
last_command="${_}"  # IMPORTANT: This line must be at the start of the script before any other command otherwise it will not work

<<LICENSE
  Copyright (C) 2017-2018 ale5000
  SPDX-License-Identifer: GPL-3.0-or-later

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version, w/ zip exception.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
LICENSE
echo ''

detect_script_dir()
{
  local this_script

  # shellcheck disable=SC3028,SC2128
  if test "${#BASH_SOURCE}" -ge 1; then this_script="${BASH_SOURCE}"  # Expanding an array without an index gives the first element (it is intended)
  else
    local current_shell
    # shellcheck disable=SC2009
    current_shell="$(ps -o 'pid,comm' | grep -Fw "$$" | while IFS=' ' read -r _ current_shell; do echo "${current_shell}"; done || true)"

    if test -n "$0" && test -n "${current_shell}" && test "$0" != "${current_shell}" && test "$0" != "-${current_shell}"; then this_script="$0"
    elif test -n "${last_command}"; then this_script="${last_command}"
    else echo 'ERROR: The script filename cannot be found'; return 1; fi
  fi
  unset last_command

  this_script="$(realpath "${this_script}" 2>&-)" || return 1
  SCRIPT_DIR="$(dirname "${this_script}")" || return 1
}
detect_script_dir || return 1 2>&- || exit 1

# shellcheck disable=SC2154
if test -z "${CI}"; then printf '\033]0;%s\007' 'Building the flashable OTA zip...' && printf '\r                                             \r'; fi

ui_error()
{
  >&2 echo "ERROR: $1"
  test -n "$2" && exit "$2"
  exit 1
}

# Detect OS and set OS specific info
SEP='/'
PATHSEP=':'
UNAME=$(uname)
compare_start_uname()
{
  case "$UNAME" in
    "$1"*) return 0;;  # Found
  esac
  return 1  # NOT found
}

if compare_start_uname 'Linux'; then
  PLATFORM='linux'
elif compare_start_uname 'Windows_NT' || compare_start_uname 'MINGW32_NT-' || compare_start_uname 'MINGW64_NT-'; then
  PLATFORM='win'
  if [[ $(uname -o) == 'Msys' ]]; then
    :            # MSYS under Windows
  else
    PATHSEP=';'  # BusyBox under Windows
  fi
elif compare_start_uname 'Darwin'; then
  PLATFORM='macos'
#elif compare_start_uname 'FreeBSD'; then
  #PLATFORM='freebsd'
else
  ui_error 'Unsupported OS'
fi

# shellcheck source=SCRIPTDIR/scripts/common.sh
if test "${A5K_FUNCTIONS_INCLUDED:-false}" = 'false'; then . "${SCRIPT_DIR}/scripts/common.sh"; fi
# shellcheck source=SCRIPTDIR/conf.sh
. "${SCRIPT_DIR}/conf.sh"

# Check dependencies
which 'zip' || ui_error 'zip command is missing'

# Create the output dir
OUT_DIR="${SCRIPT_DIR}/output"
mkdir -p "${OUT_DIR}" || ui_error 'Failed to create the output dir'

# Create the temp dir
TEMP_DIR="$(mktemp -d -t ZIPBUILDER-XXXXXX)" || ui_error 'Failed to create our temp dir'
if test -z "${TEMP_DIR}"; then ui_error 'Failed to create our temp dir'; fi

# Empty our temp dir (should be already empty, but we must be sure)
rm -rf "${TEMP_DIR:?}"/* || ui_error 'Failed to empty our temp dir'

# Set filename and version
VER=$(cat "$SCRIPT_DIR/zip-content/inc/VERSION.dat")
FILENAME="$NAME-v$VER"
if test -n "${OPENSOURCE_ONLY}"; then FILENAME="$FILENAME-OSS"; fi

. "$SCRIPT_DIR/addition.sh"

# Download files if they are missing
mkdir -p "$SCRIPT_DIR/cache"

oss_files_to_download | while IFS='|' read LOCAL_FILENAME LOCAL_PATH DL_HASH DL_URL; do
  dl_file "$LOCAL_PATH" "$LOCAL_FILENAME" "$DL_HASH" "$DL_URL"
done
STATUS="$?"; if test "$STATUS" -ne 0; then exit "$STATUS"; fi

if test -z "${OPENSOURCE_ONLY}"; then
  files_to_download | while IFS='|' read LOCAL_FILENAME LOCAL_PATH DL_HASH DL_URL; do
    dl_file "$LOCAL_PATH" "$LOCAL_FILENAME" "$DL_HASH" "$DL_URL"
  done
  STATUS="$?"; if test "$STATUS" -ne 0; then exit "$STATUS"; fi

  dl_file 'misc/keycheck' 'keycheck-arm' '77d47e9fb79bf4403fddab0130f0b4237f6acdf0' 'https://github.com/someone755/kerneller/raw/9bb15ca2e73e8b81e412d595b52a176bdeb7c70a/extract/tools/keycheck'
else
  echo 'Skipped not OSS files!'
fi

# Copy data
cp -rf "$SCRIPT_DIR/zip-content" "$TEMP_DIR/" || ui_error 'Failed to copy data to the temp dir'
cp -rf "$SCRIPT_DIR"/LIC* "$TEMP_DIR/zip-content/" || ui_error 'Failed to copy the license to the temp dir'
cp -rf "$SCRIPT_DIR"/CHANGELOG* "$TEMP_DIR/zip-content/" || ui_error 'Failed to copy the changelog to the temp dir'

if test -n "${OPENSOURCE_ONLY}"; then
  touch "$TEMP_DIR/zip-content/OPENSOURCE-ONLY"
else
  files_to_download | while IFS='|' read LOCAL_FILENAME LOCAL_PATH _; do
    mkdir -p "$TEMP_DIR/zip-content/$LOCAL_PATH"
    cp -f "$SCRIPT_DIR/cache/$LOCAL_PATH/$LOCAL_FILENAME" "$TEMP_DIR/zip-content/$LOCAL_PATH/" || ui_error "Failed to copy to the temp dir the file => '$LOCAL_PATH/$LOCAL_FILENAME'"
  done
  STATUS="$?"; if test "$STATUS" -ne 0; then exit "$STATUS"; fi

  mkdir -p "$TEMP_DIR/zip-content/misc/keycheck"
  cp -f "$SCRIPT_DIR/cache/misc/keycheck/keycheck-arm" "$TEMP_DIR/zip-content/misc/keycheck/" || ui_error "Failed to copy to the temp dir the file => 'misc/keycheck/keycheck-arm'"
fi

# Useful for reproducible builds
find "$TEMP_DIR/zip-content/" -exec touch -c -t 197911300100.00 '{}' + || ui_error 'Failed to set modification date'

# Remove the previously built files (if they exist)
rm -f "$OUT_DIR/${FILENAME}".zip* || ui_error 'Failed to remove the previously built files'
rm -f "$OUT_DIR/${FILENAME}-signed".zip* || ui_error 'Failed to remove the previously built files'

# Compress and sign
cd "$TEMP_DIR/zip-content" || ui_error 'Failed to change the folder'
zip -r9X -ic "$TEMP_DIR/flashable.zip" . -i "*" || ui_error 'Failed compressing'  # Note: There are quotes around the wildcard to use the zip globbing instead of the shell globbing
FILENAME="$FILENAME-signed"

# Sign and zipalign
mkdir -p "$TEMP_DIR/zipsign"
java -Djava.io.tmpdir="$TEMP_DIR/zipsign" -jar "$SCRIPT_DIR/tools/zipsigner.jar" "$TEMP_DIR/flashable.zip" "$TEMP_DIR/$FILENAME.zip" || ui_error 'Failed signing and zipaligning'

echo ''
zip -T "$TEMP_DIR/$FILENAME.zip" || ui_error 'The zip is corrupted'
cp -f "$TEMP_DIR/$FILENAME.zip" "$OUT_DIR/$FILENAME.zip" || ui_error 'Failed to copy the final file'

cd "$OUT_DIR" || ui_error 'Failed to change the folder'

# Cleanup remnants
rm -rf "$TEMP_DIR" &
pid="$!"

# Create checksum files
echo ''
sha256sum "$FILENAME.zip" > "$OUT_DIR/$FILENAME.zip.sha256" || ui_error 'Failed to compute the sha256 hash'
echo 'SHA-256:'
cat "$OUT_DIR/$FILENAME.zip.sha256"

echo ''
md5sum "$FILENAME.zip" > "$OUT_DIR/$FILENAME.zip.md5" || ui_error 'Failed to compute the md5 hash'
echo 'MD5:'
cat "$OUT_DIR/$FILENAME.zip.md5"

cd "$INIT_DIR" || ui_error 'Failed to change back the folder'

echo ''
echo 'Done.'

wait "$pid"
exit "$?"
