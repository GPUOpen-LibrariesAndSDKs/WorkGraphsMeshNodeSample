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

#define PI 3.14159265359

// ========================
// Projection Utils

float3 PerspectiveDivision(in float4 vec)
{
    return vec.xyz / vec.w;
}

float3 PerspectiveProject(in float4x4 projectionMatrix, in float4 vec)
{
    return PerspectiveDivision(mul(projectionMatrix, vec));
}

float3 PerspectiveProject(in float4x4 projectionMatrix, in float3 vec)
{
    return PerspectiveProject(projectionMatrix, float4(vec, 1));
}

// ========================
// Bit Utils

bool IsBitSet(in uint data, in int bitIndex)
{
    return data & (1u << bitIndex);
}

int BitSign(in uint data, in int bitIndex)
{
    return IsBitSet(data, bitIndex) ? 1 : -1;
}

// ========================
// Randon & Noise functions

// Random gradient at 2D position
float2 PerlinNoiseDir2D(in int2 position)
{
    const int2 pos = position % 289;
    
    float f = 0;
    f = (34 * pos.x + 1);
    f = f * pos.x % 289 + pos.y;
    f = (34 * f + 1) * f % 289;
    f = frac(f / 43) * 2 - 1;
    
    float x = f - round(f);
    float y = abs(f) - 0.5;
    
    return normalize(float2(x, y));
}

float PerlinNoise2D(in float2 position)
{
    const int2 gridPositon = floor(position);
    const float2 gridOffset = frac(position);
    
    const float d00 = dot(PerlinNoiseDir2D(gridPositon + int2(0, 0)), gridOffset - float2(0, 0));
    const float d01 = dot(PerlinNoiseDir2D(gridPositon + int2(0, 1)), gridOffset - float2(0, 1));
    const float d10 = dot(PerlinNoiseDir2D(gridPositon + int2(1, 0)), gridOffset - float2(1, 0));
    const float d11 = dot(PerlinNoiseDir2D(gridPositon + int2(1, 1)), gridOffset - float2(1, 1));
    
    const float2 interpolationWeights = gridOffset * gridOffset * gridOffset * (gridOffset * (gridOffset * 6 - 15) + 10);
    
    const float d0 = lerp(d00, d01, interpolationWeights.y);
    const float d1 = lerp(d10, d11, interpolationWeights.y);
    
    return lerp(d0, d1, interpolationWeights.x);
}

uint Hash(uint seed)
{
    seed = (seed ^ 61u) ^ (seed >> 16u);
    seed *= 9u;
    seed = seed ^ (seed >> 4u);
    seed *= 0x27d4eb2du;
    seed = seed ^ (seed >> 15u);
    return seed;
}

uint CombineSeed(uint a, uint b)
{
    return a ^ Hash(b) + 0x9e3779b9 + (a << 6) + (a >> 2);
}

uint CombineSeed(uint a, uint b, uint c)
{
    return CombineSeed(CombineSeed(a, b), c);
}

uint CombineSeed(uint a, uint b, uint c, uint d)
{
    return CombineSeed(CombineSeed(a, b), c, d);
}

uint Hash(in float seed)
{
    return Hash(asuint(seed));
}

uint Hash(in float3 vec)
{
    return CombineSeed(Hash(vec.x), Hash(vec.y), Hash(vec.z));
}

uint Hash(in float4 vec)
{
    return CombineSeed(Hash(vec.x), Hash(vec.y), Hash(vec.z), Hash(vec.w));
}

float Random(uint seed)
{
    return Hash(seed) / float(~0u);
}

float Random(uint a, uint b)
{
    return Random(CombineSeed(a, b));
}

float Random(uint a, uint b, uint c)
{
    return Random(CombineSeed(a, b), c);
}

float Random(uint a, uint b, uint c, uint d)
{
    return Random(CombineSeed(a, b), c, d);
}

float Random(uint a, uint b, uint c, uint d, uint e)
{
    return Random(CombineSeed(a, b), c, d, e);
}

// ========================

float ToRadians(in float degrees)
{
    return PI * (degrees / 180.0);
}

template <typename T>
T IdentityMatrix()
{
    // float4x4 identity matrix should(TM) convert to identity matrix for smaller matrices
    return (T)float4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
}

template <>
float3x3 IdentityMatrix<float3x3>()
{
    return float3x3(1, 0, 0, 0, 1, 0, 0, 0, 0);
}

template <>
float4x4 IdentityMatrix<float4x4>()
{
    return float4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
}

float2 RotateAroundPoint2d(in const float2 position, in const float angle, in const float2 rotationPoint)
{
    // Move reference position to origin
    const float2 p = position - rotationPoint;

    const float s = sin(angle);
    const float c = cos(angle);

    return float2(p.x * c - p.y * s, p.x * s + p.y * c) + rotationPoint;
}

// =====================================
// Bounding box & visibility test utils

struct ClipPlanes {
    float4 planes[6];
};

float4 PlaneNormalize(in float4 plane)
{
    const float l = length(plane.xyz);

    if (l > 0.0) {
        return plane / l;
    }

    return 0;
}

ClipPlanes ComputeClipPlanes(in float4x4 viewProjectionMatrix)
{
    ClipPlanes result;

    result.planes[0] = PlaneNormalize(viewProjectionMatrix[3] + viewProjectionMatrix[0]);
    result.planes[1] = PlaneNormalize(viewProjectionMatrix[3] - viewProjectionMatrix[0]);
    result.planes[2] = PlaneNormalize(viewProjectionMatrix[3] + viewProjectionMatrix[1]);
    result.planes[3] = PlaneNormalize(viewProjectionMatrix[3] - viewProjectionMatrix[1]);
    result.planes[4] = PlaneNormalize(viewProjectionMatrix[3] + viewProjectionMatrix[2]);
    result.planes[5] = PlaneNormalize(viewProjectionMatrix[3] - viewProjectionMatrix[2]);

    return result;
}

bool IsSphereVisible(const in float3 center, const in float radius, const in float4 clipPlanes[6])
{
    for (int i = 0; i < 6; ++i) {
        if (dot(float4(center, 1), clipPlanes[i]) < -radius) {
            return false;
        }
    }

    return true;
}

bool IsSphereVisible(const in float3 center, const in float radius, const in ClipPlanes clipPlanes)
{
    return IsSphereVisible(center, radius, clipPlanes.planes);
}

bool IsPointVisible(const in float3 position, const in float4 clipPlanes[6])
{
    return IsSphereVisible(position, 0, clipPlanes);
}

bool IsPointVisible(const in float3 position, const in ClipPlanes clipPlanes)
{
    return IsPointVisible(position, clipPlanes.planes);
}

struct AxisAlignedBoundingBox {
    float3 min;
    float3 max;

    void Transform(const in float4x4 transform)
    {
        const float3 center  = (max + min) * 0.5;
        const float3 extents = max - center;

        const float3 transformedCenter = mul(transform, float4(center, 1.0)).xyz;

        float3x3 absMatrix          = abs((float3x3)transform);
        float3   transformedExtents = mul(absMatrix, extents);

        min = transformedCenter - transformedExtents;
        max = transformedCenter + transformedExtents;
    }

    bool IsVisible(const in float4 clipPlanes[6])
    {
        for (int i = 0; i < 6; ++i) {
            float4 plane = clipPlanes[i];

            float3 axis = float3(plane.x < 0.f ? min.x : max.x,  //
                                 plane.y < 0.f ? min.y : max.y,  //
                                 plane.z < 0.f ? min.z : max.z);

            if ((dot(plane.xyz, axis) + plane.w) < 0.0f) {
                return false;
            }
        }

        return true;
    }

    bool IsVisible(const in ClipPlanes clipPlanes)
    {
        return IsVisible(clipPlanes.planes);
    }

    bool IsVisible(const in float4x4 transform, const in float4 clipPlanes[6])
    {
        AxisAlignedBoundingBox tmp = {min, max};
        tmp.Transform(transform);

        return tmp.IsVisible(clipPlanes);
    }

    bool IsVisible(const in float4x4 transform, const in ClipPlanes clipPlanes)
    {
        return IsVisible(transform, clipPlanes.planes);
    }
};