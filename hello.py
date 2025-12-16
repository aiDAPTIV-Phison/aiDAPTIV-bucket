#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Simple script to print hello message
"""

import os

print("hello")

# 建立 start-service.ps1
start_service_content = '''Write-Host "Start Service"
'''
with open("start-service.ps1", "w", encoding="utf-8") as f:
    f.write(start_service_content)

# 建立 stop-service.ps1
stop_service_content = '''Write-Host "Stop Service"
'''
with open("stop-service.ps1", "w", encoding="utf-8") as f:
    f.write(stop_service_content)

