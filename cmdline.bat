@REM SPDX-FileCopyrightText: (c) 2016 ale5000
@REM SPDX-License-Identifier: GPL-3.0-or-later
@REM SPDX-FileType: SOURCE

@echo off
SETLOCAL 2> nul

REM Fix the working directory when using "Run as administrator"
IF "%CD%" == "%windir%\system32" CD /D "%~dp0"

SET "LANG=C.UTF-8"

SET "BB_FIX_BACKSLASH=1"
SET "PATH=.;%PATH%"
SET "PATHEXT=.SH;%PATHEXT%"
SET "HOME=%~dp0"
SET "SCRIPT_DIR=%~dp0"

SET "DO_INIT_CMDLINE=1"
"%~dp0tools\win\busybox.exe" ash -s -c ". '%~dp0includes\common.sh' || exit 1" "ash" %*

ENDLOCAL 2> nul
