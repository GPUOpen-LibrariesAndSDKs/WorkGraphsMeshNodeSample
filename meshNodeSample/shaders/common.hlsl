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

#include "workgraphcommon.h"
#include "utils.hlsl"
#include "heightmap.hlsl"

// ==================
// Constants

// World grid definitions
// DO NOT CHANGE THESE!
static const uint grassPatchesPerDetailedTile = 16;
static const uint detailedTilesPerTile        = 8;
static const uint tilesPerChunk               = 8;

// World grid sizes are defined by grass blade spacing
static const float grassSpacing     = 0.25;
static const float detailedTileSize = grassPatchesPerDetailedTile * grassSpacing;
static const float tileSize         = detailedTilesPerTile * detailedTileSize;
static const float chunkSize        = tilesPerChunk * tileSize;

// Distance limits for procedural generation
static const float worldGridMaxDistance = 2000.f;

static const float denseGrassMaxDistance  = 80.f;
static const float sparseGrassMaxDistance = 250.f;

static const float flowerMaxDistance         = 300.f;
static const float flowerSparseStartDistance = 100.f;

static const float mushroomMaxDistance = denseGrassMaxDistance;

static const float butterflyMaxDistance       = 25.f;
static const float butterflyFadeStartDistance = 20.f;
static const float beeMaxDistance             = 40.f;
static const float beeFadeStartDistance       = 30.f;

// Night time definition: start at 18:00 till 6:00
// Bees and butterflies won't be rendered/generated at night
static const float nightStartTime = 18.f;
static const float nightEndTime   = 6.f;

// Radius of curved world
static const float earthRadius = 6000.f;

// ===================================
// Record structs for work graph nodes

// Record for each tile in a chunk & detailed tile in a tile
struct TileRecord {
    int2 position;
};

// Record for drawing terrain segments inside a chunk
struct DrawTerrainChunkRecord {
    uint3 dispatchGrid : SV_DispatchGrid;
    int2  chunkGridPosition;
    int   levelOfDetail;
    // indicated if neighboring terrain tiles have higher LOD
    // x = (-1, 0)
    // y = (0, -1)
    // z = (1, 0)
    // w = (0, 1)
    bool4 levelOfDetailTransition;
};

struct GenerateTreeRecord {
    float2 position;
};

static const uint maxSplinesPerRecord        = 32;
static const uint splineMaxControlPointCount = 8;

// Record for drawing multiple splines. Each spline is defined as a series of control points.
// Each control point defines a vertex ring with varying radius and vertex count.
struct DrawSplineRecord {
    uint3  dispatchGrid : SV_DispatchGrid;
    float3 color[maxSplinesPerRecord];
    float  rotationOffset[maxSplinesPerRecord];
    // x is overall wind strength, y is blending factor for individual vertices
    float2 windStrength[maxSplinesPerRecord];
    uint   controlPointCount[maxSplinesPerRecord];
    float3 controlPointPositions[maxSplinesPerRecord * splineMaxControlPointCount];
    uint   controlPointVertexCounts[maxSplinesPerRecord * splineMaxControlPointCount];
    float2 controlPointRadii[maxSplinesPerRecord * splineMaxControlPointCount];
    float  controlPointNoiseAmplitudes[maxSplinesPerRecord * splineMaxControlPointCount];
};

// Each thread in a biome tile can generate one insects
static const uint maxInsectsPerRecord = detailedTilesPerTile * detailedTilesPerTile;

// Record for insects
// Used by
//  - DrawBees
//  - DrawButterflies
struct DrawInsectRecord {
    uint3  dispatchGrid : SV_DispatchGrid;
    float3 position[maxInsectsPerRecord];
};

// Each thread in a biome tile can generate up to 3 mushrooms
static const uint maxMushroomsPerDetailedTile = 3;
static const uint maxMushroomsPerRecord = detailedTilesPerTile * detailedTilesPerTile * maxMushroomsPerDetailedTile;

// Record for mushrooms
// Used by
//  - DrawMushroomPatch
struct DrawMushroomRecord {
    uint3  dispatchGrid : SV_DispatchGrid;
    float3 position[maxMushroomsPerRecord];
};

// Each thread in a biome tile can generate up to 12 flowers
static const int maxFlowersPerDetailedTile = 12;
static const int maxFlowersPerRecord       = (detailedTilesPerTile * detailedTilesPerTile) * maxFlowersPerDetailedTile;
// scaling factor for dispatch grid size when using sparse flowers
static const int flowersInSparseFlowerThreadGroup = 5;

// Record for flowers
// Used by
//  - DrawFlowerPatch
struct DrawFlowerRecord {
    uint3  dispatchGrid : SV_DispatchGrid;
    uint   flowerPatchCount;
    float2 position[maxFlowersPerRecord];
};

// Each thread in a detailed tile corresponds to one or two dense grass patches
static const uint maxDenseGrassPatchesPerRecord = 2 * grassPatchesPerDetailedTile * grassPatchesPerDetailedTile;

// Record for dense grass
// Used by
//  - DrawDenseGrassPatch
struct DrawDenseGrassRecord {
    uint3  dispatchGrid : SV_DispatchGrid;
    float3 position[maxDenseGrassPatchesPerRecord];
    float  height[maxDenseGrassPatchesPerRecord];
    uint   bladeOffset[maxDenseGrassPatchesPerRecord];
};

// Each thread in a biome tile corresponds to a sparse grass patch
static const uint maxSparseGrassPatchesPerRecord = detailedTilesPerTile * detailedTilesPerTile;
// Number of sparse grass mesh shader thread groups needed to render one detailed tile
static const uint sparseGrassThreadGroupsPerRecord = 8;

// record for DrawSparseGrassPatch
struct DrawSparseGrassRecord {
    uint3 dispatchGrid : SV_DispatchGrid;
    int2  position[maxSparseGrassPatchesPerRecord];
};

// =====================================
// Common MS & PS input & output structs

// Vertex definition for InsectPixelShader
// Used by
//  - BeeMeshShader
//  - ButterflyMeshShader
//  - FlowerMeshShader
//  - MushroomMeshShader
struct InsectVertex {
    float4 clipSpacePosition : SV_POSITION;
    // Vertex position in object space for computing normals
    // object to world space transforms are always only translations
    // thus we can safely compute normals in object space
    float3 objectSpacePosition : POSITION0;
    float2 clipSpaceMotion : TEXCOORD0;
    float3 color : NORMAL0;
};

// Vertex definition for GrassPixelShader
// Used by
//  - DenseGrassMeshShader
//  - SparseGrassMeshShader
struct GrassVertex {
    float4 clipSpacePosition : SV_POSITION;
    float3 worldSpacePosition : POSITION0;
    float2 clipSpaceMotion : TEXCOORD0;
    float3 worldSpaceNormal : NORMAL0;
    float3 worldSpaceGroundNormal : NORMAL1;
    float  rootHeight : BLENDWEIGHT0;
    float  height : BLENDWEIGHT1;
};

// Primitive definition for mesh shaders
// Used by
//  - SparseGrassMeshShader
struct GrassCullPrimitive {
    bool cull : SV_CullPrimitive;
};

// Output struct for deferred pixel shaders
struct DeferredPixelShaderOutput {
    float4 baseColor : SV_Target0;
    float4 normal : SV_Target1;
    float2 motion : SV_Target2;
};

// ======================================================
// Common functions for accessing data in constant buffer

float GetTimeOfDay()
{
    return 12;
}

float3 GetCameraPosition()
{
    return CameraPosition.xyz;
}

float3 GetPreviousCameraPosition()
{
    return PreviousCameraPosition.xyz;
}

ClipPlanes ComputeClipPlanes()
{
    return ComputeClipPlanes(ViewProjection);
}

uint GetTime()
{
    return ShaderTime;
}

uint GetPreviousTime()
{
    return PreviousShaderTime;
}

float GetWindStrength()
{
    return WindStrength;
}

// Rotation of wind direction around y-Axis; 0 = float3(1, 0, 0);
float GetWindDirection()
{
    return WindDirection;
}

// =====================================================
// Common functions for grass placement & wind animation

float2 GetGrassOffset(in const int2 grid)
{
    float              theta               = 2. * PI * Random(grid.x, grid.y, 1337);
    float              radius              = sqrt(Random(grid.x, 19, grid.y));
    static const float patchCenterVariance = 0.4;

    return patchCenterVariance * radius * float2(cos(theta), sin(theta));
}

// Returns 2D wind offset as 3D vector for convenience
float3 GetWindOffset(in const float2 pos, in const float time)
{
    float posOnSineWave = cos(GetWindDirection()) * pos.x - sin(GetWindDirection()) * pos.y;

    float t     = 0.007 * time + posOnSineWave + 4 * PerlinNoise2D(0.1 * pos);
    float windx = 2 * sin(.5 * t);
    float windz = 1 * sin(1. * t);

    return 0.04 * float3(windx, 0, windz);
}

// ==================================================
// Common functions for curved world & motion vectors

// Computes position on curved world relative to current camera position
float3 GetCurvedWorldSpacePosition(in float3 worldSpacePosition, in bool previousCenter = false)
{
    const float2 center           = previousCenter ? GetPreviousCameraPosition().xz : GetCameraPosition().xz;
    const float2 centerToPos      = worldSpacePosition.xz - center;
    const float  distanceToCenter = length(centerToPos);
    const float2 direction        = centerToPos / distanceToCenter;

    const float alpha = distanceToCenter / earthRadius;
    const float s     = sin(alpha);
    const float c     = cos(alpha);

    const float3 curvedPosUp = normalize(float3(direction.x * s, c, direction.y * s));
    const float3 centerToCurvedPos =
        float3(direction.x * s * earthRadius, (c * earthRadius) - earthRadius, direction.y * s * earthRadius);

    const float heightScale = smoothstep(2000, 1000, distanceToCenter);

    return float3(center.x, 0, center.y) + centerToCurvedPos +  // base postion
           curvedPosUp * worldSpacePosition.y * heightScale;    // add rotated y component
}

// Computes bounding box for a grid element (e.g. chunk) on curved world
AxisAlignedBoundingBox GetGridBoundingBox(in int2  gridPosition,
                                          in float elementSize,
                                          in float minHeight,
                                          in float maxHeight)
{
    AxisAlignedBoundingBox result;

    const float3 minWorldPosition = float3(gridPosition.x, 0, gridPosition.y) * elementSize;
    const float3 maxWorldPosition = float3(gridPosition.x + 1, 0, gridPosition.y + 1) * elementSize;

    result.min = GetCurvedWorldSpacePosition(minWorldPosition) + float3(0, minHeight, 0);
    result.max = GetCurvedWorldSpacePosition(maxWorldPosition) + float3(0, maxHeight, 0);

    return result;
}

// Computes position on curved world, projects it into clip space & assigns it to vertex.clipSpacePosition
// Computes motion vector and assigns it to vertex.clipSpaceMotion
template <typename T>
void ComputeClipSpacePositionAndMotion(inout T   vertex,
                                       in float3 worldSpacePosition,
                                       in float3 previousWorldSpacePosition)
{
    // project vertex onto curved world
    const float3 curvedWorldSpacePosition         = GetCurvedWorldSpacePosition(worldSpacePosition);
    const float3 previousCurvedWorldSpacePosition = GetCurvedWorldSpacePosition(previousWorldSpacePosition, true);

    vertex.clipSpacePosition = mul(ViewProjection, float4(curvedWorldSpacePosition, 1));

    const float4 previousClipSpacePosition =
        mul(PreviousViewProjection, float4(previousCurvedWorldSpacePosition, 1));
    vertex.clipSpaceMotion = (previousClipSpacePosition.xy / previousClipSpacePosition.w) -
                             (vertex.clipSpacePosition.xy / vertex.clipSpacePosition.w);
}

// Computes position on curved world, projects it into clip space & assigns it to vertex.clipSpacePosition
// Computes motion vector and assigns it to vertex.clipSpaceMotion
template <typename T>
void ComputeClipSpacePositionAndMotion(inout T vertex, in float3 worldSpacePosition)
{
    ComputeClipSpacePositionAndMotion(vertex, worldSpacePosition, worldSpacePosition);
}