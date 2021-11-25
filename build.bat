@REM SPDX-FileCopyrightText: Copyright (C) 2016-2019, 2021 ale5000
@REM SPDX-License-Identifer: GPL-3.0-or-later
@REM SPDX-FileType: SOURCE

@echo off

TITLE Building the flashable OTA zip... 2> nul
SETLOCAL 2> nul
CHCP 858 >nul || ECHO "Changing the codepage failed"
"%~dp0tools\win\busybox.exe" sh "%~dp0build.sh" %*
ENDLOCAL 2> nul
SET "EXIT_CODE=%ERRORLEVEL%"
TITLE Done 2> nul

IF NOT "%~1" == "Gradle" PAUSE > nul

TITLE %ComSpec% 2> nul
IF %EXIT_CODE% NEQ 0 EXIT /B %EXIT_CODE%
SET "EXIT_CODE="
