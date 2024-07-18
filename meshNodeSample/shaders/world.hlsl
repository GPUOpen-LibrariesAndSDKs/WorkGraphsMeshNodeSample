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

// Record for launching a grid of chunks
// grid size & offset are computed based on current camera view
struct ChunkGridRecord {
    uint2 grid : SV_DispatchGrid;
    int2  offset;
};

float2 ComputeFarPlaneCorner(in float clipX, in float clipY)
{
    // compute position of frustum corner on far plane
    const float3 cornerWorldPosition = PerspectiveProject(InverseViewProjection, float3(clipX, clipY, 1.f));

    const float2 viewVector       = cornerWorldPosition.xz - GetCameraPosition().xz;
    const float  viewVectorLength = length(viewVector);
    // limit view vector to maximum terrain distance
    const float  viewVectorScale  = min(worldGridMaxDistance / viewVectorLength, 1.f);

    return GetCameraPosition().xz + viewVector * viewVectorScale;
}

void minmax(inout float2 minTerrainPosition, inout float2 maxTerrainPosition, in float2 position)
{
    minTerrainPosition = min(minTerrainPosition, position);
    maxTerrainPosition = max(maxTerrainPosition, position);
}

[Shader("node")]
[NodeLaunch("thread")]
void World(
    [MaxRecords(1)]
    [NodeId("ChunkGrid")]
    NodeOutput<ChunkGridRecord> chunkGridOutput)
{
    // This node computes the world-space extends of the chunk grid based on the current camera view frustum

    // Compute bounding box of view frustum
    // Start with camera position
    float2 minTerrainPosition = GetCameraPosition().xz;
    float2 maxTerrainPosition = minTerrainPosition;

    // Add far plane corners to view frustum bounding box
    minmax(minTerrainPosition, maxTerrainPosition, ComputeFarPlaneCorner(-1, -1));
    minmax(minTerrainPosition, maxTerrainPosition, ComputeFarPlaneCorner(-1, +1));
    minmax(minTerrainPosition, maxTerrainPosition, ComputeFarPlaneCorner(+1, -1));
    minmax(minTerrainPosition, maxTerrainPosition, ComputeFarPlaneCorner(+1, +1));

    // Compute & round chunk coordinates
    const int2 minChunkPosition = floor(minTerrainPosition / chunkSize);
    const int2 maxChunkPosition = ceil(maxTerrainPosition / chunkSize);

    // Dispatch one thread group per chunk
    ThreadNodeOutputRecords<ChunkGridRecord> chunkGridRecord = chunkGridOutput.GetThreadNodeOutputRecords(1);

    chunkGridRecord.Get().grid   = clamp(maxChunkPosition - minChunkPosition, 0, 32);
    chunkGridRecord.Get().offset = minChunkPosition;

    chunkGridRecord.OutputComplete();
}

int GetTerrainChunkLevelOfDetail(in int2 chunkGridPosition)
{
    const float2 chunkWorldPosition       = chunkGridPosition * chunkSize;
    const float3 chunkWorldCenterPosition = GetTerrainPosition(chunkWorldPosition + chunkSize * 0.5);
    const float  distanceToCamera         = distance(GetCameraPosition(), chunkWorldCenterPosition);

    return clamp(distanceToCamera / (3 * chunkSize), 0, 3);
}

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeMaxDispatchGrid(32, 32, 1)]
// each thread corresponds to one tile
[NumThreads(tilesPerChunk, tilesPerChunk, 1)] 
void ChunkGrid(
    DispatchNodeInputRecord<ChunkGridRecord> inputRecord,

    int2 groupId : SV_GroupId,
    int2 groupThreadId : SV_GroupThreadID,

    [MaxRecords(1)]
    [NodeId("DrawTerrainChunk")]
    NodeOutput<DrawTerrainChunkRecord> terrainOutput,

    [MaxRecords(tilesPerChunk * tilesPerChunk)]
    [NodeId("Tile")]
    [NodeArraySize(3)]
    NodeOutputArray<TileRecord> tileOutput)
{
    const ChunkGridRecord input              = inputRecord.Get();
    const int2            chunkGridPosition  = input.offset + groupId;
    const float2          chunkWorldPosition = chunkGridPosition * chunkSize;

    const ClipPlanes clipPlanes = ComputeClipPlanes();

    const AxisAlignedBoundingBox chunkBoundingBox = GetGridBoundingBox(chunkGridPosition, chunkSize, -100, 300);
    const bool                   isChunkVisible   = chunkBoundingBox.IsVisible(clipPlanes);

    // Terrain output
    {
        const bool hasTerrainOutput = isChunkVisible;

        GroupNodeOutputRecords<DrawTerrainChunkRecord> terrainOutputRecord =
            terrainOutput.GetGroupNodeOutputRecords(hasTerrainOutput);

        if (hasTerrainOutput) {
            const int  levelOfDetail = GetTerrainChunkLevelOfDetail(chunkGridPosition);
            const uint dispatchSize  = 8 / clamp(1U << levelOfDetail, 1, 8);

            terrainOutputRecord.Get().dispatchGrid      = uint3(dispatchSize, dispatchSize, 1);
            terrainOutputRecord.Get().chunkGridPosition = chunkGridPosition;
            terrainOutputRecord.Get().levelOfDetail     = levelOfDetail;

            terrainOutputRecord.Get().levelOfDetailTransition.x =
                GetTerrainChunkLevelOfDetail(chunkGridPosition + int2(-1, 0)) > levelOfDetail;
            terrainOutputRecord.Get().levelOfDetailTransition.y =
                GetTerrainChunkLevelOfDetail(chunkGridPosition + int2(0, -1)) > levelOfDetail;
            terrainOutputRecord.Get().levelOfDetailTransition.z =
                GetTerrainChunkLevelOfDetail(chunkGridPosition + int2(1, 0)) > levelOfDetail;
            terrainOutputRecord.Get().levelOfDetailTransition.w =
                GetTerrainChunkLevelOfDetail(chunkGridPosition + int2(0, 1)) > levelOfDetail;
        }

        terrainOutputRecord.OutputComplete();
    }

    // Tile output
    if (isChunkVisible)
    {
        const int2   threadGridPosition  = chunkGridPosition * tilesPerChunk + groupThreadId;
        const float2 threadWorldPosition = threadGridPosition * tileSize;

        const AxisAlignedBoundingBox tileBoundingBox = GetGridBoundingBox(threadGridPosition, tileSize, -100, 300);

        const bool hasTileOutput = tileBoundingBox.IsVisible(clipPlanes);

        // Get biome weights in center of tile
        const float3 biomeWeights = GetBiomeWeights(threadWorldPosition + tileSize * 0.5);

        // Classify biome tile to launch by dominant biome
        const uint biome = biomeWeights.x > biomeWeights.y ? (biomeWeights.x > biomeWeights.z ? 0 : 2)
                                                           : (biomeWeights.y > biomeWeights.z ? 1 : 2);

        ThreadNodeOutputRecords<TileRecord> tileOutputRecord =
            tileOutput[biome].GetThreadNodeOutputRecords(hasTileOutput);

        if (hasTileOutput) {

            tileOutputRecord.Get().position = chunkGridPosition * tilesPerChunk + groupThreadId;
        }

        tileOutputRecord.OutputComplete();
    }
}
