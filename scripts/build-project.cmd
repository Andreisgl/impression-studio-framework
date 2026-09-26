@echo off
rem Copyright 2026 Andrei Segal
rem SPDX-License-Identifier: Apache-2.0
rem Runs build-project.ps1 with the execution policy bypassed for this one process, so no
rem PowerShell settings need to change. Arguments and the exit code pass through.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-project.ps1" %*
exit /b %ERRORLEVEL%
