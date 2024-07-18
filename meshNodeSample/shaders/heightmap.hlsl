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

#include "utils.hlsl"

// x = mountain
// y = woodland
// z = grassland
float3 GetBiomeWeights(in float2 position)
{
    const float2 pos = position * 0.01;

    float mountainFactor = 0;
    mountainFactor += 1 * PerlinNoise2D(0.5 * pos);
    mountainFactor += 2 * PerlinNoise2D(0.2 * pos + float2(38, 23));
    mountainFactor += 4 * PerlinNoise2D(0.1 * pos);

    float woodlandMountainFactor = 1.f - smoothstep(0, 1, 4 * pow(mountainFactor - 0.5, 2));
    woodlandMountainFactor       = woodlandMountainFactor - pow(4 * PerlinNoise2D(0.1 * pos), 4);
    mountainFactor               = clamp(pow(clamp(mountainFactor, 0, 1), 2), 0, 1);

    float woodlandFactor = 0;
    woodlandFactor += 1 * pow(4 * PerlinNoise2D(0.3 * pos), 3);
    woodlandFactor += 5 * pow(1 * PerlinNoise2D(0.1 * pos), 2);
    woodlandFactor = clamp(smoothstep(0, 1, woodlandFactor), 0, 1);

    woodlandFactor = smoothstep(0, 1, max(woodlandMountainFactor, woodlandFactor - mountainFactor));

    float grasslandFactor = clamp(1 - (mountainFactor + woodlandFactor), 0, 1);

    return float3(mountainFactor, woodlandFactor, grasslandFactor);
}

float GetTerrainHeight(in float2 pos)
{
    const float3 biomes = GetBiomeWeights(pos);

    // scale position down for low-frequency perlin noise
    const float2 samplePosition = pos / 400.0;
    
    // Add multiple perlin noise layers to achieve base terrain height
    float baseHeight = 0;
    baseHeight += 1.0 * PerlinNoise2D(1.0 * samplePosition + float2(34, 98));
    baseHeight += 0.35 * PerlinNoise2D(2.0 * samplePosition + float2(73, 42));
    baseHeight += 0.25 * max(PerlinNoise2D(3.2 * samplePosition + float2(+0.5, -0.5)),
                             PerlinNoise2D(3.5 * samplePosition + float2(-0.5, +0.5)));
    baseHeight += 0.15 * PerlinNoise2D(4.0 * samplePosition);
    baseHeight += 0.08 * PerlinNoise2D(8.0 * samplePosition);
    baseHeight += 0.07 * PerlinNoise2D(9.0 * samplePosition);
    
    // square height to make hills a bit more pronounced and scale to final height
    float height = 140.0 * baseHeight * baseHeight;
    
    // Add additional high-frequency noise in mountain biome
    float mountainHeight = 0;
    mountainHeight += 0.97 * PerlinNoise2D(1.0 * samplePosition);
    mountainHeight += 0.95 * max(PerlinNoise2D(2.8 * samplePosition + float2(+2.3, -4.5)),
                                 PerlinNoise2D(3.1 * samplePosition + float2(-6.5, +3.6)));
    mountainHeight += 0.75 * PerlinNoise2D(2.0 * samplePosition + float2(34, 56));
    
    height += 70.0 * mountainHeight * mountainHeight * smoothstep(0.5, 1.0, biomes.x);
    
    // raise mountain biome up
    height += 40.0 * smoothstep(0.0, 1.0, biomes.x);

    return height;
}

float GetTerrainHeight(in float x, in float y)
{
    return GetTerrainHeight(float2(x, y));
}

float3 GetTerrainPosition(in float x, in float z)
{
    return float3(x, GetTerrainHeight(x, z), z);
}

float3 GetTerrainPosition(in float2 pos)
{
    return float3(pos.x, GetTerrainHeight(pos.x, pos.y), pos.y);
}

float3 GetTerrainNormal(in float x, in float z)
{
    const float height = GetTerrainHeight(x, z);

    static const float h  = 0.01;
    float              dx = (height - GetTerrainHeight(x + h, z));
    float              dz = (height - GetTerrainHeight(x, z + h));

    float3 a = normalize(float3(h, -dx, 0));
    float3 b = normalize(float3(0, -dz, h));

    return normalize(cross(b, a));
}

float3 GetTerrainNormal(in float2 pos)
{
    return GetTerrainNormal(pos.x, pos.y);
}