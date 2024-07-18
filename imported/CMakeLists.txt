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

include(FetchContent)

FetchContent_Declare(
    ffxsdk
    GIT_REPOSITORY https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK
    GIT_TAG        55ff22bb6981a9b9c087b9465101769fc0acd447 # fsr3-v3.0.4
)

FetchContent_GetProperties(ffxsdk)

# manually import FidelityFX SDK
if (NOT ffxsdk_POPULATED)
    message(STATUS "Downloading FidelityFX SDK")
    FetchContent_Populate(ffxsdk)
    message(STATUS "Downloaded FidelityFX SDK to ${ffxsdk_SOURCE_DIR}")

    # set root directory of FidelityFX SDK for patches
    set(FFX_ROOT ${ffxsdk_SOURCE_DIR})
    # Apply patches to FidelityFX SDK
    include(patch-ffx.cmake)

    # don't build any FFX samples
    set(BUILD_TYPE FFX_NONE)
    # build FFX SDK with Cauldron backend
    set(FFX_API CAULDRON)
    # enable FSR2 in FFX SDK.
    set(FFX_FSR2 ON)
    # FFX_FSR is required for FFX_FSR2, but also enables FFX sample, which also requires FFX_FSR1
    set(FFX_FSR  ON)
    set(FFX_FSR1 ON)

    # FFX uses CMAKE_HOME_DIRECTORY as root directory for all internal paths
    # since FFX is not the top-level repository here, we need to change CMAKE_HOME_DIRECTORY such that all the paths still match up
    set(CMAKE_HOME_DIRECTORY ${ffxsdk_SOURCE_DIR})
    add_subdirectory(${ffxsdk_SOURCE_DIR} ${ffxsdk_BINARY_DIR})
    
    # Move FFX_FSR sample to folder in solution
    set_target_properties(FFX_FSR PROPERTIES FOLDER "FFX Samples")
endif()

# set root directory of FidelityFX SDK
set(FFX_ROOT ${ffxsdk_SOURCE_DIR} PARENT_SCOPE)

# propagate configurations to top level; only DX12 is supported for this sample 
set(CMAKE_CONFIGURATION_TYPES "DebugDX12;ReleaseDX12;RelWithDebInfoDX12" PARENT_SCOPE)