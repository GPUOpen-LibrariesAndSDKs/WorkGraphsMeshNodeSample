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

// Framework and Windows implementation
#include "core/framework.h"
#include "core/win/framework_win.h"

// Config file parsing
#include "misc/fileio.h"

// Custom camera component
#include "samplecameracomponent.h"

// Content manager to fix texture load bug
#include "core/contentmanager.h"

// Render Module Registry
#include "rendermoduleregistry.h"
// Render Modules
#include "fsr2rendermodule.h"
#include "workgraphrendermodule.h"

// D3D12 header to enable experimental shader models
#include "d3d12.h"

using namespace cauldron;

class MeshNodeSample final : public Framework
{
public:
    MeshNodeSample(const FrameworkInitParams* pInitParams)
        : Framework(pInitParams)
    {
    }

    ~MeshNodeSample() = default;

    // Overrides
    void ParseSampleConfig() override
    {
        const auto configFileName = L"configs/meshnodesampleconfig.json";

        json sampleConfig;
        CauldronAssert(ASSERT_CRITICAL, ParseJsonFile(configFileName, sampleConfig), L"Could not parse JSON file %ls", configFileName);

        // Get the sample configuration
        json configData = sampleConfig["Mesh Node Sample"];

        // Let the framework parse all the "known" options for us
        ParseConfigData(configData);
    }

    void RegisterSampleModules() override
    {
        // Init all pre-registered render modules
        rendermodule::RegisterAvailableRenderModules();

        // Register sample render module
        RenderModuleFactory::RegisterModule<WorkGraphRenderModule>("WorkGraphRenderModule");
        // Register FSR 2 render module
        RenderModuleFactory::RegisterModule<FSR2RenderModule>("FSR2RenderModule");
    }

    int32_t PreRun() override
    {
        const auto status = Framework::PreRun();

        // Init custom camera entity & component
        Task createCameraTask(InitCameraEntity, nullptr);
        GetTaskManager()->AddTask(createCameraTask);

        // Cauldron is missing its media folder, thus these textures are not available.
        // Due to a bug, Cauldron will not shutdown if these textures are not loaded,
        // thus we decrement the pending texture loads manually with three nullptr textures
        Texture* texturePtr = nullptr;
        GetContentManager()->StartManagingContent(L"SpecularIBL", texturePtr);
        GetContentManager()->StartManagingContent(L"DiffuseIBL", texturePtr);
        GetContentManager()->StartManagingContent(L"BrdfLut", texturePtr);

        return status;
    }

    int32_t DoSampleInit() override
    {
        // Enable FSR 2 upscaling and AA
        GetFramework()->GetRenderModule("FSR2RenderModule")->EnableModule(true);

        return 0;
    }

    void DoSampleShutdown() override
    {
        // Shutdown (disable) FSR 2 render module
        GetFramework()->GetRenderModule("FSR2RenderModule")->EnableModule(false);
    }
};

static FrameworkInitParamsInternal s_WindowsParams;

//////////////////////////////////////////////////////////////////////////
// WinMain
int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow)
{
    // Enable experimental D3D12 features for mesh nodes
    std::array<UUID, 2> meshNodesExperimentalFeatures = {D3D12ExperimentalShaderModels, D3D12StateObjectsExperiment};
    CauldronThrowOnFail(
        D3D12EnableExperimentalFeatures(static_cast<UINT>(meshNodesExperimentalFeatures.size()), meshNodesExperimentalFeatures.data(), nullptr, nullptr));

    // Create the sample and kick it off to the framework to run
    FrameworkInitParams initParams = {};
    initParams.Name                = L"Mesh Node Sample";
    initParams.CmdLine             = lpCmdLine;
    initParams.AdditionalParams    = &s_WindowsParams;

    // Setup the windows info
    s_WindowsParams.InstanceHandle = hInstance;
    s_WindowsParams.CmdShow        = nCmdShow;

    MeshNodeSample frameworkInstance(&initParams);
    return RunFramework(&frameworkInstance);
}
