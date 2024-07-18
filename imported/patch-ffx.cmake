# This file is part of the AMD Work Graph Mesh Node Sample.
#
# Copyright (C) 2024 Advanced Micro Devices, Inc.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files(the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and /or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions :
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# This scripts applies small modifications to the FidelityFX & Cauldron SDK
# Patches:
# - Update Microsoft Agility SDK to 714
# - patch camera component to allow for custom implementation

# Update Agility SDK
include(update-agilitysdk.cmake)

find_package(Git)

message(STATUS "Patching cameracomponent.h")
# Patch camera component
execute_process(COMMAND "${GIT_EXECUTABLE}" apply "${CMAKE_CURRENT_SOURCE_DIR}/cameracomponent.patch"
                WORKING_DIRECTORY "${FFX_ROOT}"
                ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE)

message(STATUS "Patching common.cmake")
# Patch bin output directory
execute_process(COMMAND "${GIT_EXECUTABLE}" apply "${CMAKE_CURRENT_SOURCE_DIR}/binoutput.patch"
                WORKING_DIRECTORY "${FFX_ROOT}"
                ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE)

message(STATUS "Patching dxil.dll copy")
# Patch copying of dxil.dll to output directory
execute_process(COMMAND "${GIT_EXECUTABLE}" apply "${CMAKE_CURRENT_SOURCE_DIR}/dxil.patch"
                WORKING_DIRECTORY "${FFX_ROOT}"
                #ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE)
