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

#include "common.hlsl"

DeferredPixelShaderOutput GrassPixelShader(const GrassVertex input, bool isFrontFace : SV_IsFrontFace)
{
    DeferredPixelShaderOutput output;
    output.motion = input.clipSpaceMotion.xy;

    const float3 biomeWeights = GetBiomeWeights(input.worldSpacePosition.xz);
    const float  biomeFactor  = lerp(1.0, 0.75, biomeWeights.y);

    float selfshadow     = clamp(pow((input.worldSpacePosition.y - input.rootHeight) / input.height, 1.5), 0, 1);
    output.baseColor.rgb = pow(float3(0.41, 0.44, 0.29) * 2, 2.2) * selfshadow * biomeFactor;
    output.baseColor.rgb *= 0.75 + 0.25 * PerlinNoise2D(0.25 * input.worldSpacePosition.xz);
    output.baseColor.a = 1;

    float3 normal = normalize(input.worldSpaceNormal);

    if (!isFrontFace) {
        normal = -normal;
    }

    float3 groundNormal = normalize(lerp(normalize(input.worldSpaceGroundNormal), float3(0, 1, 0), 0.5));
    output.normal.xyz   = normalize(lerp(groundNormal, normal, 0.25));
    output.normal.w     = 1.0;

    return output;
}