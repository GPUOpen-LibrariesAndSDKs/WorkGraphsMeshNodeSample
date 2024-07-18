// This file is part of the AMD Work Graph Mesh Node Sample.
//
// Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#include "shadercompiler.h"

#include "misc/assert.h"

#define _SILENCE_EXPERIMENTAL_FILESYSTEM_DEPRECATION_WARNING  // To avoid receiving deprecation error since we are using \
                                                              // C++11 only
#include <experimental/filesystem>
using namespace std::experimental;

template <class Interface>
inline void SafeRelease(Interface*& pInterfaceToRelease)
{
    if (pInterfaceToRelease != nullptr)
    {
        pInterfaceToRelease->Release();

        pInterfaceToRelease = nullptr;
    }
}

ShaderCompiler::ShaderCompiler()
{
    HMODULE dxilModule       = LoadLibraryW(L"dxil.dll");
    HMODULE dxcompilerModule = LoadLibraryW(L"dxcompiler.dll");

    cauldron::CauldronAssert(cauldron::ASSERT_CRITICAL, dxcompilerModule, L"Failed to load dxcompiler.dll");

    DxcCreateInstanceProc pfnDxcCreateInstance = DxcCreateInstanceProc(GetProcAddress(dxcompilerModule, "DxcCreateInstance"));

    cauldron::CauldronAssert(cauldron::ASSERT_CRITICAL, pfnDxcCreateInstance, L"Failed to load DxcCreateInstance from dxcompiler.dll");

    if (FAILED(pfnDxcCreateInstance(CLSID_DxcUtils, IID_PPV_ARGS(&m_pUtils))))
    {
        cauldron::CauldronCritical(L"Failed to create DXC utils");
    }

    if (FAILED(pfnDxcCreateInstance(CLSID_DxcCompiler, IID_PPV_ARGS(&m_pCompiler))))
    {
        // delete utils if compiler creation fails
        SafeRelease(m_pUtils);

        cauldron::CauldronCritical(L"Failed to create DXC compiler");
    }

    if (FAILED(m_pUtils->CreateDefaultIncludeHandler(&m_pIncludeHandler)))
    {
        // delete utils & compiler if include handler creation fails
        SafeRelease(m_pCompiler);
        SafeRelease(m_pUtils);

        cauldron::CauldronCritical(L"Failed to create DXC compiler");
    }
}

ShaderCompiler::~ShaderCompiler()
{
    SafeRelease(m_pIncludeHandler);
    SafeRelease(m_pCompiler);
    SafeRelease(m_pUtils);
}

IDxcBlob* ShaderCompiler::CompileShader(const wchar_t* shaderFilePath, const wchar_t* target, const wchar_t* entryPoint)
{
    IDxcBlobEncoding* source = nullptr;

    const auto shaderSourceFilePath = std::wstring(L"Shaders\\") + shaderFilePath;

    if (FAILED(m_pUtils->LoadFile(shaderSourceFilePath.c_str(), nullptr, &source)) || (source == nullptr))
    {
        cauldron::CauldronCritical(L"Failed to load %s", shaderFilePath);
    }

    const auto shadersFolderPath     = filesystem::current_path() / L"shaders";
    const auto shaderIncludeArgument = std::wstring(L"-I") + shadersFolderPath.wstring();

    std::vector<const wchar_t*> arguments = {
        L"-enable-16bit-types",
        // use HLSL 2021
        L"-HV",
        L"2021",
        // column major matrices
        DXC_ARG_PACK_MATRIX_COLUMN_MAJOR,
        // include path for "shaders" folder
        shaderIncludeArgument.c_str(),
    };

    IDxcOperationResult* result = nullptr;
    const auto           hr     = m_pCompiler->Compile(
        source, shaderFilePath, entryPoint, target, arguments.data(), static_cast<UINT32>(arguments.size()), nullptr, 0, m_pIncludeHandler, &result);

    // release source blob
    SafeRelease(source);

    if (FAILED(hr))
    {
        SafeRelease(result);

        cauldron::CauldronCritical(L"Failed to compile shader %s", shaderFilePath);
    }

    HRESULT compileStatus;
    if (FAILED(result->GetStatus(&compileStatus)))
    {
        SafeRelease(result);

        cauldron::CauldronCritical(L"Failed to get compilation status for shader %s", shaderFilePath);
    }

    std::wstring errorString = L"";

    // try get error string from DXC result
    {
        IDxcBlobEncoding* errorStringBlob = nullptr;
        if (SUCCEEDED(result->GetErrorBuffer(&errorStringBlob)) && (errorStringBlob != nullptr))
        {
            IDxcBlobWide* errorStringBlob16 = nullptr;
            m_pUtils->GetBlobAsUtf16(errorStringBlob, &errorStringBlob16);

            errorString = std::wstring(errorStringBlob16->GetStringPointer(), errorStringBlob16->GetStringLength());

            SafeRelease(errorStringBlob16);
        }
        SafeRelease(errorStringBlob);
    }

    if (FAILED(compileStatus))
    {
        SafeRelease(result);

        cauldron::CauldronCritical(L"Failed to compile shader %s\n%s", shaderFilePath, errorString.c_str());
    }

    IDxcBlob* outputBlob = nullptr;
    if (FAILED(result->GetResult(&outputBlob)))
    {
        SafeRelease(result);

        cauldron::CauldronCritical(L"Failed to get binary shader blob for shader %s", shaderFilePath);
    }

    SafeRelease(result);

    return outputBlob;
}