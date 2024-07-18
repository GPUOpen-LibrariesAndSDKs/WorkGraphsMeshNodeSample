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

# This script will download the Microsoft Agility SDK & DirectX Shader compiler from the official NuGet package repository
# Update these URLs and perform a clean build if you wish to use a newer version of these packages.
set(AGILITY_SDK_URL "https://www.nuget.org/api/v2/package/Microsoft.Direct3D.D3D12/1.715.0-preview")
set(DXC_URL "https://www.nuget.org/api/v2/package/Microsoft.Direct3D.DXC/1.8.2404.55-mesh-nodes-preview")

# Check if Agility SDK NuGet package was already downloaded
if (NOT EXISTS ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK.zip)
    message(STATUS "Downloading Agility SDK from ${AGILITY_SDK_URL}")

    file(DOWNLOAD ${AGILITY_SDK_URL} ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK.zip STATUS DOWNLOAD_RESULT)

    list(GET DOWNLOAD_RESULT 0 DOWNLOAD_RESULT_CODE)
    if(NOT DOWNLOAD_RESULT_CODE EQUAL 0)
        message(FATAL_ERROR "Failed to download Agility SDK! Error: ${DOWNLOAD_RESULT}.")
    endif()

    message(STATUS "Successfully downloaded Agility SDK")
else()
    message(STATUS "Found local copy of ${AGILITY_SDK_URL} in ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK.zip. Skipping download.")
endif()

message(STATUS "Extracting Agility SDK")

# extract agility SDK zip
file(ARCHIVE_EXTRACT
    INPUT ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK.zip
    DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK)

# validate agility SDK binaries
if(NOT EXISTS ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/bin/x64/D3D12Core.dll OR
   NOT EXISTS ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/bin/x64/d3d12SDKLayers.dll)
    message(FATAL_ERROR "Failed to extract Agility SDK!")
endif()

message(STATUS "Successfully extracted Agility SDK")

set(CAULDRON_AGILITY_SDK_PATH ${FFX_ROOT}/framework/cauldron/framework/libs/agilitysdk)

# copy Agility SDK binaries
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/bin/x64/D3D12Core.dll ${CAULDRON_AGILITY_SDK_PATH}/bin/x64/D3D12Core.dll)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/bin/x64/D3D12Core.pdb ${CAULDRON_AGILITY_SDK_PATH}/bin/x64/D3D12Core.pdb)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/bin/x64/d3d12SDKLayers.dll ${CAULDRON_AGILITY_SDK_PATH}/bin/x64/d3d12SDKLayers.dll)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/bin/x64/d3d12SDKLayers.pdb ${CAULDRON_AGILITY_SDK_PATH}/bin/x64/d3d12SDKLayers.pdb)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/bin/x64/d3dconfig.exe ${CAULDRON_AGILITY_SDK_PATH}/bin/x64/d3dconfig.exe)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/bin/x64/d3dconfig.pdb ${CAULDRON_AGILITY_SDK_PATH}/bin/x64/d3dconfig.pdb)

# copy Agility SDK headers
file(COPY ${CMAKE_CURRENT_BINARY_DIR}/agilitySDK/build/native/include DESTINATION ${CAULDRON_AGILITY_SDK_PATH})

message(STATUS "Successfully copied Agility SDK to Cauldron source")

# Check if DXC NuGet package was already downloaded
if (NOT EXISTS ${CMAKE_CURRENT_BINARY_DIR}/dxc.zip)
    message(STATUS "Downloading DirectX Shader Compiler from ${DXC_URL}")

    file(DOWNLOAD ${DXC_URL} ${CMAKE_CURRENT_BINARY_DIR}/dxc.zip STATUS DOWNLOAD_RESULT)

    list(GET DOWNLOAD_RESULT 0 DOWNLOAD_RESULT_CODE)
    if(NOT DOWNLOAD_RESULT_CODE EQUAL 0)
        message(FATAL_ERROR "Failed to download DirectX Shader Compiler! Error: ${DOWNLOAD_RESULT}.")
    endif()

    message(STATUS "Successfully downloaded DirectX Shader Compiler")
else()
    message(STATUS "Found local copy of ${DXC_URL} in ${CMAKE_CURRENT_BINARY_DIR}/dxc.zip. Skipping download.")
endif()

message(STATUS "Extracting DirectX Shader Compiler")

# extract dxc zip
file(ARCHIVE_EXTRACT
    INPUT ${CMAKE_CURRENT_BINARY_DIR}/dxc.zip
    DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/dxc)

# validate DXC binaries
if(NOT EXISTS ${CMAKE_CURRENT_BINARY_DIR}/dxc/build/native/bin/x64/dxcompiler.dll)
    message(FATAL_ERROR "Failed to extract DirectX Shader Compiler!")
endif()

message(STATUS "Successfully extracted DirectX Shader Compiler")

set(CAULDRON_DXC_PATH ${FFX_ROOT}/framework/cauldron/framework/libs/dxc)

# copy dxc binaries
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/dxc/build/native/bin/x64/dxcompiler.dll ${CAULDRON_DXC_PATH}/bin/x64/dxcompiler.dll)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/dxc/build/native/bin/x64/dxc.exe ${CAULDRON_DXC_PATH}/bin/x64/dxc.exe)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/dxc/build/native/lib/x64/dxcompiler.lib ${CAULDRON_DXC_PATH}/lib/x64/dxcompiler.lib)

# copy dxc headers
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/dxc/build/native/include/d3d12shader.h ${CAULDRON_DXC_PATH}/inc/d3d12shader.h)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/dxc/build/native/include/dxcapi.h ${CAULDRON_DXC_PATH}/inc/dxcapi.h)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/dxc/build/native/include/dxcerrors.h ${CAULDRON_DXC_PATH}/inc/dxcerrors.h)
file(COPY_FILE ${CMAKE_CURRENT_BINARY_DIR}/dxc/build/native/include/dxcisense.h ${CAULDRON_DXC_PATH}/inc/dxcisense.h)

message(STATUS "Successfully copied DirectX Shader Compiler to Cauldron source")

message(STATUS "Patching Agility SDK version")

# find git and apply a patch to FFX 
find_package(Git)
execute_process(COMMAND "${GIT_EXECUTABLE}" apply "${CMAKE_CURRENT_SOURCE_DIR}/agilitysdk-version.patch"
                WORKING_DIRECTORY "${FFX_ROOT}"
                ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE)