#!/usr/bin/env bash

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

# Detect script dir (with absolute path)
INIT_DIR=$(pwd)
BASEDIR=$(dirname "$0")
if [[ "${BASEDIR:0:1}" == '/' ]] || [[ "$PLATFORM" == 'win' && "${BASEDIR:1:1}" == ':' ]]; then
  :  # If already absolute leave it as is
else
  if [[ "$BASEDIR" == '.' ]]; then BASEDIR=''; else BASEDIR="/$BASEDIR"; fi
  if [[ "$INIT_DIR" != '/' ]]; then BASEDIR="$INIT_DIR$BASEDIR"; fi
fi
WGET_CMD='wget'
TOOLS_DIR="${BASEDIR}${SEP}tools${SEP}${PLATFORM}"
PATH="${TOOLS_DIR}${PATHSEP}${PATH}"

verify_sha1()
{
  local file_name="$1"
  local hash="$2"
  local file_hash=$(sha1sum "$file_name" | cut -d ' ' -f 1)

  if [[ $hash != "$file_hash" ]]; then return 1; fi  # Failed
  return 0  # Success
}

corrupted_file()
{
  rm -f "$1" || echo 'Failed to remove the corrupted file.'
  ui_error "The file '$1' is corrupted."
}

dl_file()
{
  if [[ ! -e "$BASEDIR/cache/$1/$2" ]]; then
    mkdir -p "$BASEDIR/cache/$1"
    "$WGET_CMD" -O "$BASEDIR/cache/$1/$2" -U 'Mozilla/5.0 (X11; Linux x86_64; rv:63.0) Gecko/20100101 Firefox/63.0' "$4" || ui_error "Failed to download the file => 'cache/$1/$2'."
    echo ''
  fi
  verify_sha1 "$BASEDIR/cache/$1/$2" "$3" || corrupted_file "$BASEDIR/cache/$1/$2"
}

. "$BASEDIR/conf.sh"

# Check dependencies
which 'zip' || ui_error 'zip command is missing'

# Create the output dir
OUT_DIR="$BASEDIR/output"
mkdir -p "$OUT_DIR" || ui_error 'Failed to create the output dir'

# Create the temp dir
TEMP_DIR=$(mktemp -d -t ZIPBUILDER-XXXXXX) || ui_error 'Failed to create our temp dir'
if test -z "$TEMP_DIR"; then ui_error 'Failed to create our temp dir'; fi

# Empty our temp dir (should be already empty, but we must be sure)
rm -rf "$TEMP_DIR"/* || ui_error 'Failed to empty our temp dir'

# Set filename and version
VER=$(cat "$BASEDIR/zip-content/inc/VERSION")
FILENAME="$NAME-v$VER"
if test -n "${OPENSOURCE_ONLY}"; then FILENAME="$FILENAME-OSS"; fi

. "$BASEDIR/addition.sh"

# Download files if they are missing
mkdir -p "$BASEDIR/cache"

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
cp -rf "$BASEDIR/zip-content" "$TEMP_DIR/" || ui_error 'Failed to copy data to the temp dir'
cp -rf "$BASEDIR"/LIC* "$TEMP_DIR/zip-content/" || ui_error 'Failed to copy the license to the temp dir'
cp -rf "$BASEDIR"/CHANGELOG* "$TEMP_DIR/zip-content/" || ui_error 'Failed to copy the changelog to the temp dir'

if test -n "${OPENSOURCE_ONLY}"; then
  touch "$TEMP_DIR/zip-content/OPENSOURCE-ONLY"
else
  files_to_download | while IFS='|' read LOCAL_FILENAME LOCAL_PATH _; do
    mkdir -p "$TEMP_DIR/zip-content/$LOCAL_PATH"
    cp -f "$BASEDIR/cache/$LOCAL_PATH/$LOCAL_FILENAME" "$TEMP_DIR/zip-content/$LOCAL_PATH/" || ui_error "Failed to copy to the temp dir the file => '$LOCAL_PATH/$LOCAL_FILENAME'"
  done
  STATUS="$?"; if test "$STATUS" -ne 0; then exit "$STATUS"; fi

  mkdir -p "$TEMP_DIR/zip-content/misc/keycheck"
  cp -f "$BASEDIR/cache/misc/keycheck/keycheck-arm" "$TEMP_DIR/zip-content/misc/keycheck/" || ui_error "Failed to copy to the temp dir the file => 'misc/keycheck/keycheck-arm'"
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
java -Djava.io.tmpdir="$TEMP_DIR/zipsign" -jar "$BASEDIR/tools/zipsigner.jar" "$TEMP_DIR/flashable.zip" "$TEMP_DIR/$FILENAME.zip" || ui_error 'Failed signing and zipaligning'

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
