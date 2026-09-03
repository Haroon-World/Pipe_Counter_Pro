@echo off
title Pipe Counter Pro
cd /d "%~dp0"
python desktop_gui.py
if errorlevel 1 pause
