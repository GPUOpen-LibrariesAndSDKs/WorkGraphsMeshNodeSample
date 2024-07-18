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

#include "workgraphrendermodule.h"

#include "core/framework.h"
#include "core/scene.h"
#include "core/uimanager.h"
#include "misc/assert.h"

// Render components
#include "render/buffer.h"
#include "render/device.h"
#include "render/dynamicresourcepool.h"
#include "render/parameterset.h"
#include "render/pipelinedesc.h"
#include "render/pipelineobject.h"
#include "render/profiler.h"
#include "render/rasterview.h"
#include "render/rootsignature.h"
#include "render/rootsignaturedesc.h"
#include "render/texture.h"

// D3D12 Cauldron implementation
#include "render/dx12/buffer_dx12.h"
#include "render/dx12/commandlist_dx12.h"
#include "render/dx12/device_dx12.h"
#include "render/dx12/gpuresource_dx12.h"
#include "render/dx12/rootsignature_dx12.h"

// common files with shaders
#include "shaders/shadingcommon.h"
#include "shaders/workgraphcommon.h"

// shader compiler
#include "shadercompiler.h"

#include <sstream>

using namespace cauldron;

// Name for work graph program inside the state object
static const wchar_t* WorkGraphProgramName = L"WorkGraph";

WorkGraphRenderModule::WorkGraphRenderModule()
    : RenderModule(L"WorkGraphRenderModule")
{
}

WorkGraphRenderModule::~WorkGraphRenderModule()
{
    // Delete work graph
    if (m_pWorkGraphStateObject)
        m_pWorkGraphStateObject->Release();
    if (m_pWorkGraphParameterSet)
        delete m_pWorkGraphParameterSet;
    if (m_pWorkGraphRootSignature)
        delete m_pWorkGraphRootSignature;
    if (m_pWorkGraphBackingMemoryBuffer)
        delete m_pWorkGraphBackingMemoryBuffer;

    // Delete shading pipeline
    if (m_pShadingPipeline)
        delete m_pShadingPipeline;
    if (m_pShadingRootSignature)
        delete m_pShadingRootSignature;
    if (m_pShadingParameterSet)
        delete m_pShadingParameterSet;
}

void WorkGraphRenderModule::Init(const json& initData)
{
    InitTextures();
    InitWorkGraphProgram();
    InitShadingPipeline();

    cauldron::UISection uiSection = {};
    uiSection.SectionName         = "Procedural Generation";

    uiSection.AddFloatSlider("Wind Strength", &m_WindStrength, 0.f, 2.5f);
    uiSection.AddFloatSlider("Wind Direction", &m_WindDirection, 0.f, 360.f, nullptr, nullptr, false, "%.1f");

    GetUIManager()->RegisterUIElements(uiSection);

    SetModuleReady(true);
}

void WorkGraphRenderModule::Execute(double deltaTime, cauldron::CommandList* pCmdList)
{
    const auto previousShaderTime = m_shaderTime;

    // Increment shader time
    m_shaderTime += static_cast<uint32_t>(deltaTime * 1000.0);

    // Get render resolution based on upscaler state
    const auto  upscaleState = GetFramework()->GetUpscalingState();
    const auto& resInfo      = GetFramework()->GetResolutionInfo();

    uint32_t width, height;
    if (upscaleState == UpscalerState::None || upscaleState == UpscalerState::PostUpscale)
    {
        width  = resInfo.DisplayWidth;
        height = resInfo.DisplayHeight;
    }
    else
    {
        width  = resInfo.RenderWidth;
        height = resInfo.RenderHeight;
    }

    {
        GPUScopedProfileCapture workGraphMarker(pCmdList, L"Work Graph");

        std::vector<Barrier> barriers;
        barriers.push_back(Barrier::Transition(m_pGBufferColorOutput->GetResource(),
                                               ResourceState::NonPixelShaderResource | ResourceState::PixelShaderResource,
                                               ResourceState::RenderTargetResource));
        barriers.push_back(Barrier::Transition(m_pGBufferNormalOutput->GetResource(),
                                               ResourceState::NonPixelShaderResource | ResourceState::PixelShaderResource,
                                               ResourceState::RenderTargetResource));
        barriers.push_back(Barrier::Transition(m_pGBufferMotionOutput->GetResource(),
                                               ResourceState::NonPixelShaderResource | ResourceState::PixelShaderResource,
                                               ResourceState::RenderTargetResource));
        barriers.push_back(Barrier::Transition(
            m_pGBufferDepthOutput->GetResource(), ResourceState::NonPixelShaderResource | ResourceState::PixelShaderResource, ResourceState::DepthWrite));

        ResourceBarrier(pCmdList, static_cast<uint32_t>(barriers.size()), barriers.data());

        // Clear color targets
        float clearColor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        for (const auto* rasterView : m_pGBufferRasterViews)
        {
            ClearRenderTarget(pCmdList, &rasterView->GetResourceView(), clearColor);
        }

        // Clear depth target
        ClearDepthStencil(pCmdList, &m_pGBufferDepthRasterView->GetResourceView(), 0);

        // Begin raster with render targets
        BeginRaster(pCmdList, static_cast<uint32_t>(m_pGBufferRasterViews.size()), m_pGBufferRasterViews.data(), m_pGBufferDepthRasterView, nullptr);
        SetViewportScissorRect(pCmdList, 0, 0, width, height, 0.f, 1.f);

        const auto* currentCamera = GetScene()->GetCurrentCamera();

        WorkGraphCBData workGraphData        = {};
        workGraphData.ViewProjection         = currentCamera->GetProjectionJittered() * currentCamera->GetView();
        workGraphData.PreviousViewProjection = currentCamera->GetPrevProjectionJittered() * currentCamera->GetPreviousView();
        workGraphData.InverseViewProjection  = InverseMatrix(workGraphData.ViewProjection);
        workGraphData.CameraPosition         = currentCamera->GetCameraTranslation();
        workGraphData.PreviousCameraPosition = InverseMatrix(currentCamera->GetPreviousView()).getCol3();
        workGraphData.ShaderTime             = m_shaderTime;
        workGraphData.PreviousShaderTime     = previousShaderTime;
        workGraphData.WindStrength           = m_WindStrength;
        workGraphData.WindDirection          = DEG_TO_RAD(m_WindDirection);

        BufferAddressInfo workGraphDataInfo = GetDynamicBufferPool()->AllocConstantBuffer(sizeof(WorkGraphCBData), &workGraphData);
        m_pWorkGraphParameterSet->UpdateRootConstantBuffer(&workGraphDataInfo, 0);

        // Bind all the parameters
        m_pWorkGraphParameterSet->Bind(pCmdList, nullptr);

        // Dispatch the work graph
        {
            D3D12_DISPATCH_GRAPH_DESC dispatchDesc    = {};
            dispatchDesc.Mode                         = D3D12_DISPATCH_MODE_NODE_CPU_INPUT;
            dispatchDesc.NodeCPUInput                 = {};
            dispatchDesc.NodeCPUInput.EntrypointIndex = m_WorkGraphEntryPointIndex;
            // Launch graph with one record
            dispatchDesc.NodeCPUInput.NumRecords = 1;
            // Record does not contain any data
            dispatchDesc.NodeCPUInput.RecordStrideInBytes = 0;
            dispatchDesc.NodeCPUInput.pRecords            = nullptr;

            // Get ID3D12GraphicsCommandList10 from Cauldron command list
            ID3D12GraphicsCommandList10* commandList;
            CauldronThrowOnFail(pCmdList->GetImpl()->DX12CmdList()->QueryInterface(IID_PPV_ARGS(&commandList)));

            commandList->SetProgram(&m_WorkGraphProgramDesc);
            commandList->DispatchGraph(&dispatchDesc);

            // Release command list (only releases additional reference created by QueryInterface)
            commandList->Release();

            // Clear backing memory initialization flag, as the graph has run at least once now
            m_WorkGraphProgramDesc.WorkGraph.Flags &= ~D3D12_SET_WORK_GRAPH_FLAG_INITIALIZE;
        }

        EndRaster(pCmdList, nullptr);

        // Transition render targets back to readable state
        for (auto& barrier : barriers)
        {
            std::swap(barrier.DestState, barrier.SourceState);
        }

        ResourceBarrier(pCmdList, static_cast<uint32_t>(barriers.size()), barriers.data());
    }

    {
        GPUScopedProfileCapture shadingMarker(pCmdList, L"Shading");

        // Render modules expect resources coming in/going out to be in a shader read state
        Barrier barrier = Barrier::Transition(
            m_pShadingOutput->GetResource(), ResourceState::NonPixelShaderResource | ResourceState::PixelShaderResource, ResourceState::UnorderedAccess);
        ResourceBarrier(pCmdList, 1, &barrier);

        BufferAddressInfo upscaleInfo =
            GetDynamicBufferPool()->AllocConstantBuffer(sizeof(UpscalerInformation), &GetScene()->GetSceneInfo().UpscalerInfo.FullScreenScaleRatio);
        m_pShadingParameterSet->UpdateRootConstantBuffer(&upscaleInfo, 0);

        const auto* currentCamera = GetScene()->GetCurrentCamera();

        ShadingCBData shadingData         = {};
        shadingData.InverseViewProjection = InverseMatrix(currentCamera->GetProjectionJittered() * currentCamera->GetView());
        shadingData.CameraPosition        = currentCamera->GetCameraTranslation();

        BufferAddressInfo shadingInfo = GetDynamicBufferPool()->AllocConstantBuffer(sizeof(ShadingCBData), &shadingData);
        m_pShadingParameterSet->UpdateRootConstantBuffer(&shadingInfo, 1);

        // Bind all the parameters
        m_pShadingParameterSet->Bind(pCmdList, m_pShadingPipeline);

        SetPipelineState(pCmdList, m_pShadingPipeline);

        const uint32_t numGroupX = DivideRoundingUp(width, s_shadingThreadGroupSizeX);
        const uint32_t numGroupY = DivideRoundingUp(height, s_shadingThreadGroupSizeY);
        Dispatch(pCmdList, numGroupX, numGroupY, 1);

        // Render modules expect resources coming in/going out to be in a shader read state
        barrier = Barrier::Transition(
            m_pShadingOutput->GetResource(), ResourceState::UnorderedAccess, ResourceState::NonPixelShaderResource | ResourceState::PixelShaderResource);
        ResourceBarrier(pCmdList, 1, &barrier);
    }
}

void WorkGraphRenderModule::OnResize(const cauldron::ResolutionInfo& resInfo)
{
}

void WorkGraphRenderModule::InitTextures()
{
    m_pShadingOutput = GetFramework()->GetColorTargetForCallback(GetName());
    CauldronAssert(ASSERT_CRITICAL, m_pShadingOutput != nullptr, L"Couldn't find or create the render target of WorkGraphRenderModule.");

    m_pGBufferColorOutput  = GetFramework()->GetRenderTexture(L"GBufferColorTarget");
    m_pGBufferNormalOutput = GetFramework()->GetRenderTexture(L"GBufferNormalTarget");
    m_pGBufferMotionOutput = GetFramework()->GetRenderTexture(L"GBufferMotionVectorTarget");
    m_pGBufferDepthOutput  = GetFramework()->GetRenderTexture(L"GBufferDepthTarget");

    m_pGBufferRasterViews[0] = GetRasterViewAllocator()->RequestRasterView(m_pGBufferColorOutput, ViewDimension::Texture2D);
    m_pGBufferRasterViews[1] = GetRasterViewAllocator()->RequestRasterView(m_pGBufferNormalOutput, ViewDimension::Texture2D);
    m_pGBufferRasterViews[2] = GetRasterViewAllocator()->RequestRasterView(m_pGBufferMotionOutput, ViewDimension::Texture2D);

    m_pGBufferDepthRasterView = GetRasterViewAllocator()->RequestRasterView(m_pGBufferDepthOutput, ViewDimension::Texture2D);
}

void WorkGraphRenderModule::InitWorkGraphProgram()
{
    // Create root signature for work graph
    RootSignatureDesc workGraphRootSigDesc;
    workGraphRootSigDesc.AddConstantBufferView(0, ShaderBindStage::Compute, 1);
    // Work graphs with mesh nodes use graphics root signature instead of compute root signature
    workGraphRootSigDesc.m_PipelineType = PipelineType::Graphics;

    m_pWorkGraphRootSignature = RootSignature::CreateRootSignature(L"MeshNodeSample_WorkGraphRootSignature", workGraphRootSigDesc);

    // Create parameter set for root signature
    m_pWorkGraphParameterSet = ParameterSet::CreateParameterSet(m_pWorkGraphRootSignature);
    m_pWorkGraphParameterSet->SetRootConstantBufferResource(GetDynamicBufferPool()->GetResource(), sizeof(WorkGraphCBData), 0);

    // Get D3D12 device
    // CreateStateObject is only available on ID3D12Device9
    ID3D12Device9* d3dDevice = nullptr;
    CauldronThrowOnFail(GetDevice()->GetImpl()->DX12Device()->QueryInterface(IID_PPV_ARGS(&d3dDevice)));

    // Check if mesh nodes are supported
    {
        D3D12_FEATURE_DATA_D3D12_OPTIONS21 options = {};
        CauldronThrowOnFail(d3dDevice->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS21, &options, sizeof(options)));

        // check if work graphs tier 1.1 (mesh nodes) is supported
        if (options.WorkGraphsTier < D3D12_WORK_GRAPHS_TIER_1_1)
        {
            CauldronCritical(L"Work graphs tier 1.1 (mesh nodes) are not supported on the current device.");
        }
    }

    // Create work graph
    CD3DX12_STATE_OBJECT_DESC stateObjectDesc(D3D12_STATE_OBJECT_TYPE_EXECUTABLE);

    // configure draw nodes to use graphics root signature
    auto configSubobject = stateObjectDesc.CreateSubobject<CD3DX12_STATE_OBJECT_CONFIG_SUBOBJECT>();
    configSubobject->SetFlags(D3D12_STATE_OBJECT_FLAG_WORK_GRAPHS_USE_GRAPHICS_STATE_FOR_GLOBAL_ROOT_SIGNATURE);

    // set root signature for work graph
    auto rootSignatureSubobject = stateObjectDesc.CreateSubobject<CD3DX12_GLOBAL_ROOT_SIGNATURE_SUBOBJECT>();
    rootSignatureSubobject->SetRootSignature(m_pWorkGraphRootSignature->GetImpl()->DX12RootSignature());

    auto workgraphSubobject = stateObjectDesc.CreateSubobject<CD3DX12_WORK_GRAPH_SUBOBJECT>();
    workgraphSubobject->IncludeAllAvailableNodes();
    workgraphSubobject->SetProgramName(WorkGraphProgramName);

    // add DXIL shader libraries
    ShaderCompiler shaderCompiler;

    // list of compiled shaders to be released once the work graph is created
    std::vector<IDxcBlob*> compiledShaders;

    // Helper function for adding a shader library to the work graph state object
    const auto AddShaderLibrary = [&](const wchar_t* shaderFileName) {
        // compile shader as library
        auto* blob           = shaderCompiler.CompileShader(shaderFileName, L"lib_6_9", nullptr);
        auto  shaderBytecode = CD3DX12_SHADER_BYTECODE(blob->GetBufferPointer(), blob->GetBufferSize());

        // add blob to state object
        auto librarySubobject = stateObjectDesc.CreateSubobject<CD3DX12_DXIL_LIBRARY_SUBOBJECT>();
        librarySubobject->SetDXILLibrary(&shaderBytecode);

        // add shader blob to be released later
        compiledShaders.push_back(blob);
    };

    // Helper function for adding a pixel shader to the work graph state object
    // Pixel shaders need to be compiled with "ps" target and as such the DXIL library object needs to specify a name
    // for the pixel shader (exportName) with which the generic program can reference the pixel shader
    const auto AddPixelShader = [&](const wchar_t* shaderFileName, const wchar_t* entryPoint) {
        // compile shader as pixel shader
        auto* blob           = shaderCompiler.CompileShader(shaderFileName, L"ps_6_9", entryPoint);
        auto  shaderBytecode = CD3DX12_SHADER_BYTECODE(blob->GetBufferPointer(), blob->GetBufferSize());

        // add blob to state object
        auto librarySubobject = stateObjectDesc.CreateSubobject<CD3DX12_DXIL_LIBRARY_SUBOBJECT>();
        librarySubobject->SetDXILLibrary(&shaderBytecode);

        // add shader blob to be released later
        compiledShaders.push_back(blob);
    };

    // ===================================================================
    // State object for graphics PSO state description in generic programs

    // Rasterizer state configuration without culling
    auto rasterizerNoCullingSubobject = stateObjectDesc.CreateSubobject<CD3DX12_RASTERIZER_SUBOBJECT>();
    rasterizerNoCullingSubobject->SetFrontCounterClockwise(true);
    rasterizerNoCullingSubobject->SetFillMode(D3D12_FILL_MODE_SOLID);
    rasterizerNoCullingSubobject->SetCullMode(D3D12_CULL_MODE_NONE);

    // Rasterizer state configuration with backface culling
    auto rasterizerBackfaceCullingSubobject = stateObjectDesc.CreateSubobject<CD3DX12_RASTERIZER_SUBOBJECT>();
    rasterizerBackfaceCullingSubobject->SetFrontCounterClockwise(true);
    rasterizerBackfaceCullingSubobject->SetFillMode(D3D12_FILL_MODE_SOLID);
    rasterizerBackfaceCullingSubobject->SetCullMode(D3D12_CULL_MODE_BACK);

    // Primitive topology configuration
    auto primitiveTopologySubobject = stateObjectDesc.CreateSubobject<CD3DX12_PRIMITIVE_TOPOLOGY_SUBOBJECT>();
    primitiveTopologySubobject->SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);

    // Depth stencil format configuration
    auto depthStencilFormatSubobject = stateObjectDesc.CreateSubobject<CD3DX12_DEPTH_STENCIL_FORMAT_SUBOBJECT>();
    depthStencilFormatSubobject->SetDepthStencilFormat(GetDXGIFormat(m_pGBufferDepthOutput->GetFormat()));

    //  Render target format configuration
    auto renderTargetFormatSubobject = stateObjectDesc.CreateSubobject<CD3DX12_RENDER_TARGET_FORMATS_SUBOBJECT>();
    renderTargetFormatSubobject->SetNumRenderTargets(3);
    renderTargetFormatSubobject->SetRenderTargetFormat(0, GetDXGIFormat(m_pGBufferColorOutput->GetFormat()));
    renderTargetFormatSubobject->SetRenderTargetFormat(1, GetDXGIFormat(m_pGBufferNormalOutput->GetFormat()));
    renderTargetFormatSubobject->SetRenderTargetFormat(2, GetDXGIFormat(m_pGBufferMotionOutput->GetFormat()));

    // =============================
    // Generic programs (mesh nodes)

    // Helper function to add a mesh node generic program subobject
    const auto AddMeshNode = [&](const wchar_t* meshShaderExportName, const wchar_t* pixelShaderExportName, bool backfaceCulling) {
        auto genericProgramSubobject = stateObjectDesc.CreateSubobject<CD3DX12_GENERIC_PROGRAM_SUBOBJECT>();
        // add mesh shader
        genericProgramSubobject->AddExport(meshShaderExportName);
        // add pixel shader
        genericProgramSubobject->AddExport(pixelShaderExportName);

        // add graphics state subobjects
        if (backfaceCulling)
        {
            genericProgramSubobject->AddSubobject(*rasterizerBackfaceCullingSubobject);
        }
        else
        {
            genericProgramSubobject->AddSubobject(*rasterizerNoCullingSubobject);
        }
        genericProgramSubobject->AddSubobject(*primitiveTopologySubobject);
        genericProgramSubobject->AddSubobject(*depthStencilFormatSubobject);
        genericProgramSubobject->AddSubobject(*renderTargetFormatSubobject);
    };

    // ===================================
    // Add shader libraries and mesh nodes

    // Shader libraries for procedural world generation
    AddShaderLibrary(L"world.hlsl");
    AddShaderLibrary(L"biomes.hlsl");
    AddShaderLibrary(L"tree.hlsl");
    AddShaderLibrary(L"rock.hlsl");

    // Terrain Mesh Node
    AddShaderLibrary(L"terrainrenderer.hlsl");
    AddPixelShader(L"terrainrenderer.hlsl", L"TerrainPixelShader");
    AddMeshNode(L"TerrainMeshShader", L"TerrainPixelShader", true);

    // Spline Mesh Node for trees & rocks
    AddShaderLibrary(L"splinerenderer.hlsl");
    AddPixelShader(L"splinerenderer.hlsl", L"SplinePixelShader");
    AddMeshNode(L"SplineMeshShader", L"SplinePixelShader", true);

    // Grass Nodes
    AddShaderLibrary(L"densegrassmeshshader.hlsl");
    AddShaderLibrary(L"sparsegrassmeshshader.hlsl");
    AddPixelShader(L"grasspixelshader.hlsl", L"GrassPixelShader");
    AddMeshNode(L"DenseGrassMeshShader", L"GrassPixelShader", false);
    AddMeshNode(L"SparseGrassMeshShader", L"GrassPixelShader", false);

    // Flowers, Insects & Mushroom Nodes
    AddShaderLibrary(L"beemeshshader.hlsl");
    AddShaderLibrary(L"butterflymeshshader.hlsl");
    AddShaderLibrary(L"flowermeshshader.hlsl");
    AddShaderLibrary(L"mushroommeshshader.hlsl");
    AddPixelShader(L"insectpixelshader.hlsl", L"InsectPixelShader");
    AddMeshNode(L"BeeMeshShader", L"InsectPixelShader", false);
    AddMeshNode(L"ButterflyMeshShader", L"InsectPixelShader", false);
    AddMeshNode(L"FlowerMeshShader", L"InsectPixelShader", false);
    AddMeshNode(L"SparseFlowerMeshShader", L"InsectPixelShader", false);
    AddMeshNode(L"MushroomMeshShader", L"InsectPixelShader", false);

    // Create work graph state object
    CauldronThrowOnFail(d3dDevice->CreateStateObject(stateObjectDesc, IID_PPV_ARGS(&m_pWorkGraphStateObject)));

    // release all compiled shaders
    for (auto* shader : compiledShaders)
    {
        if (shader)
        {
            shader->Release();
        }
    }

    // Get work graph properties
    ID3D12StateObjectProperties1* stateObjectProperties;
    ID3D12WorkGraphProperties1*   workGraphProperties;

    CauldronThrowOnFail(m_pWorkGraphStateObject->QueryInterface(IID_PPV_ARGS(&stateObjectProperties)));
    CauldronThrowOnFail(m_pWorkGraphStateObject->QueryInterface(IID_PPV_ARGS(&workGraphProperties)));

    // Get the index of our work graph inside the state object (state object can contain multiple work graphs)
    const auto workGraphIndex = workGraphProperties->GetWorkGraphIndex(WorkGraphProgramName);

    // Set the input record limit. This is required for work graphs with mesh nodes.
    // In this case we'll only have a single input record
    workGraphProperties->SetMaximumInputRecords(workGraphIndex, 1, 1);

    // Create backing memory buffer
    D3D12_WORK_GRAPH_MEMORY_REQUIREMENTS memoryRequirements = {};
    workGraphProperties->GetWorkGraphMemoryRequirements(workGraphIndex, &memoryRequirements);
    if (memoryRequirements.MaxSizeInBytes > 0)
    {
        BufferDesc bufferDesc = BufferDesc::Data(L"MeshNodeSample_WorkGraphBackingMemory",
                                                 static_cast<uint32_t>(memoryRequirements.MaxSizeInBytes),
                                                 1,
                                                 D3D12_WORK_GRAPHS_BACKING_MEMORY_ALIGNMENT_IN_BYTES,
                                                 ResourceFlags::AllowUnorderedAccess);

        m_pWorkGraphBackingMemoryBuffer = Buffer::CreateBufferResource(&bufferDesc, ResourceState::UnorderedAccess);
    }

    // Prepare work graph desc
    m_WorkGraphProgramDesc.Type                        = D3D12_PROGRAM_TYPE_WORK_GRAPH;
    m_WorkGraphProgramDesc.WorkGraph.ProgramIdentifier = stateObjectProperties->GetProgramIdentifier(WorkGraphProgramName);
    // Set flag to initialize backing memory.
    // We'll clear this flag once we've run the work graph for the first time.
    m_WorkGraphProgramDesc.WorkGraph.Flags = D3D12_SET_WORK_GRAPH_FLAG_INITIALIZE;
    // Set backing memory
    if (m_pWorkGraphBackingMemoryBuffer)
    {
        const auto addressInfo                                      = m_pWorkGraphBackingMemoryBuffer->GetAddressInfo();
        m_WorkGraphProgramDesc.WorkGraph.BackingMemory.StartAddress = addressInfo.GetImpl()->GPUBufferView;
        m_WorkGraphProgramDesc.WorkGraph.BackingMemory.SizeInBytes  = addressInfo.GetImpl()->SizeInBytes;
    }

    // Query entry point index
    m_WorkGraphEntryPointIndex = workGraphProperties->GetEntrypointIndex(workGraphIndex, {L"World", 0});

    // Release state object properties
    stateObjectProperties->Release();
    workGraphProperties->Release();

    // Release ID3D12Device9 (only releases additional reference created by QueryInterface)
    d3dDevice->Release();
}

void WorkGraphRenderModule::InitShadingPipeline()
{
    RootSignatureDesc shadingRootSigDesc;
    shadingRootSigDesc.AddConstantBufferView(0, ShaderBindStage::Compute, 1);
    shadingRootSigDesc.AddConstantBufferView(1, ShaderBindStage::Compute, 1);
    shadingRootSigDesc.AddTextureSRVSet(0, ShaderBindStage::Compute, 2);
    shadingRootSigDesc.AddTextureUAVSet(0, ShaderBindStage::Compute, 1);

    m_pShadingRootSignature = RootSignature::CreateRootSignature(L"MeshNodeSample_ShadingRootSignature", shadingRootSigDesc);

    PipelineDesc shadingPsoDesc;
    shadingPsoDesc.SetRootSignature(m_pShadingRootSignature);
    shadingPsoDesc.AddShaderDesc(ShaderBuildDesc::Compute(L"shading.hlsl", L"MainCS", ShaderModel::SM6_0));

    m_pShadingPipeline = PipelineObject::CreatePipelineObject(L"MeshNodeSample_ShadingPipeline", shadingPsoDesc);

    m_pShadingParameterSet = ParameterSet::CreateParameterSet(m_pShadingRootSignature);

    m_pShadingParameterSet->SetRootConstantBufferResource(GetDynamicBufferPool()->GetResource(), sizeof(UpscalerInformation), 0);
    m_pShadingParameterSet->SetRootConstantBufferResource(GetDynamicBufferPool()->GetResource(), sizeof(ShadingCBData), 1);
    m_pShadingParameterSet->SetTextureSRV(m_pGBufferColorOutput, ViewDimension::Texture2D, 0);
    m_pShadingParameterSet->SetTextureSRV(m_pGBufferNormalOutput, ViewDimension::Texture2D, 1);
    m_pShadingParameterSet->SetTextureUAV(m_pShadingOutput, ViewDimension::Texture2D, 0);
}
