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

#pragma once

#include "render/rendermodule.h"
#include "render/shaderbuilder.h"

// d3dx12 for work graphs
#include "d3dx12/d3dx12.h"

// Forward declaration of Cauldron classes
namespace cauldron
{
    class Buffer;
    class ParameterSet;
    class PipelineObject;
    class RasterView;
    class RootSignature;
    class Texture;
}  // namespace cauldron

class WorkGraphRenderModule : public cauldron::RenderModule
{
public:
    WorkGraphRenderModule();
    virtual ~WorkGraphRenderModule();

    /**
     * @brief   Initialize work graphs, UI & other contexts
     */
    void Init(const json& initData) override;

    /**
     * @brief   Execute the work graph.
     */
    void Execute(double deltaTime, cauldron::CommandList* pCmdList) override;

    /**
     * @brief Called by the framework when resolution changes.
     */
    void OnResize(const cauldron::ResolutionInfo& resInfo) override;

private:
    /**
     * @brief   Create and initialize textures required for rendering and shading.
     */
    void InitTextures();
    /**
     * @brief   Create and initialize the work graph program with mesh nodes.
     */
    void InitWorkGraphProgram();
    /**
     * @brief   Create and initialize the shading compute pipeline.
     */
    void InitShadingPipeline();

    // time variable for shader animations in milliseconds
    uint32_t m_shaderTime = 0;

    // UI controlled settings
    float m_WindStrength  = 1.f;
    float m_WindDirection = 0.f;

    const cauldron::Texture*                   m_pGBufferDepthOutput     = nullptr;
    const cauldron::RasterView*                m_pGBufferDepthRasterView = nullptr;
    const cauldron::Texture*                   m_pGBufferColorOutput     = nullptr;
    const cauldron::Texture*                   m_pGBufferNormalOutput    = nullptr;
    const cauldron::Texture*                   m_pGBufferMotionOutput    = nullptr;
    std::array<const cauldron::RasterView*, 3> m_pGBufferRasterViews;

    cauldron::RootSignature* m_pWorkGraphRootSignature       = nullptr;
    cauldron::ParameterSet*  m_pWorkGraphParameterSet        = nullptr;
    ID3D12StateObject*       m_pWorkGraphStateObject         = nullptr;
    cauldron::Buffer*        m_pWorkGraphBackingMemoryBuffer = nullptr;
    // Program description for binding the work graph
    // contains work graph identifier & backing memory
    D3D12_SET_PROGRAM_DESC m_WorkGraphProgramDesc = {};
    // Index of entry point node
    UINT m_WorkGraphEntryPointIndex = 0;

    const cauldron::Texture*  m_pShadingOutput        = nullptr;
    cauldron::RootSignature*  m_pShadingRootSignature = nullptr;
    cauldron::ParameterSet*   m_pShadingParameterSet  = nullptr;
    cauldron::PipelineObject* m_pShadingPipeline      = nullptr;
};