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

#include "fullscreen.hlsl"
#include "shadingcommon.h"
#include "upscaler.h"
#include "skybox.hlsl"

//--------------------------------------------------------------------------------------
// Texture definitions
//--------------------------------------------------------------------------------------
RWTexture2D<float4> RenderTarget : register(u0);

Texture2D<float4> BaseColor : register(t0);
Texture2D<float3> Normal : register(t1);

//--------------------------------------------------------------------------------------
// Main function
//--------------------------------------------------------------------------------------
[numthreads(s_shadingThreadGroupSizeX, s_shadingThreadGroupSizeY, 1)]

void MainCS(uint3 dtID : SV_DispatchThreadID)
{
    if (any(dtID.xy > UpscalerInfo.FullScreenScaleRatio.xy)) {
        return;
    }

    const float2 uv            = GetUV(dtID.xy, 1.f / UpscalerInfo.FullScreenScaleRatio.xy);
    const float3 clip          = float3(2 * uv.x - 1, 1 - 2 * uv.y, 1);
    const float3 viewDirection = normalize(PerspectiveProject(InverseViewProjection, clip) - CameraPosition.xyz);

    const LightingData lightingData = GetLightingData();

    const float4 baseColor = BaseColor[dtID.xy];

    if (baseColor.a < 0.5) {
        RenderTarget[dtID.xy] = float4(GetSkyboxColor(viewDirection, lightingData), 1);

        return;
    }

    const float3 normal = Normal[dtID.xy];

    // Ambient
    const float  sunZenithDot   = lightingData.sunDirection.y;
    const float  sunZenithDot01 = (sunZenithDot + 1.0) * 0.5;
    const float3 ambientContrib = baseColor.rgb * 0.2 * saturate(pow(dot(normal, -viewDirection), .25)) * 1 *
                                  (skybox::SunZenith_Gradient(0.5) + skybox::ViewZenith_Gradient(sunZenithDot01));
    
    // Diffuse
    const float3 diffuseContrib = saturate(dot(normal, lightingData.globalLightDirection));

    float3 color = ambientContrib + diffuseContrib * baseColor.rgb;

    RenderTarget[dtID.xy] = float4(color.rgb, 1);
}