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

// Groupshared counters for group output records
groupshared uint denseGrassPatchCount;
groupshared uint sparseGrassPatchCount;
groupshared uint mushroomPatchCount;
groupshared uint butterflyPatchCount;
groupshared uint flowerPatchCount;
groupshared uint beePatchCount;

// Groupshared terrain gradient estimate
groupshared int terrainGradient;

[Shader("node")]
[NodeId("Tile", 0)]
[NodeLaunch("broadcasting")]
[NodeDispatchGrid(1, 1, 1)]
// each thread corresponds to one detailed tile
[NumThreads(detailedTilesPerTile, detailedTilesPerTile, 1)] 
void MountainTile(
    DispatchNodeInputRecord<TileRecord> inputRecord,

    int2 groupThreadId : SV_GroupThreadID,

    [MaxRecords(detailedTilesPerTile * detailedTilesPerTile)]
    [NodeId("GenerateRock")]
    NodeOutput<GenerateTreeRecord> rockOutput,

    [MaxRecords(detailedTilesPerTile * detailedTilesPerTile)]
    [NodeId("GenerateTree", 1)]
    NodeOutput<GenerateTreeRecord> treeOutput)
{
    // clear groupshared counters
    terrainGradient = 0;

    GroupMemoryBarrierWithGroupSync();

    const int linearGroupThreadId = groupThreadId.x + groupThreadId.y * 8;

    const TileRecord input             = inputRecord.Get();
    const int2       tileGridPosition  = input.position;
    const float2     tileWorldPosition = tileGridPosition * tileSize;
    const float3     tileCenterWorldPosition = GetTerrainPosition(tileWorldPosition + tileSize * 0.5);

    const int2   threadGridPosition        = tileGridPosition * detailedTilesPerTile + groupThreadId;
    const float2 threadWorldPosition       = threadGridPosition * detailedTileSize;
    const float3 threadCenterWorldPosition = GetTerrainPosition(threadWorldPosition + detailedTileSize * 0.5);

    // Gradient estimation
    if (any(groupThreadId == 0) || any(groupThreadId == (detailedTilesPerTile - 1)))
    {
        const float3 towardsCenter = tileCenterWorldPosition - threadCenterWorldPosition;
        
        InterlockedAdd(terrainGradient, int(towardsCenter.y * 10.f));
    }

    GroupMemoryBarrierWithGroupSync();

    // Tree cluster output
    {
        const uint seed = CombineSeed(asuint(tileGridPosition.x), asuint(tileGridPosition.y));

        const bool hasTreeCluster = (terrainGradient < 0) && (Random(seed, 97834) > 0.55);
        const uint treeCount      = hasTreeCluster * round(lerp(5, 10, Random(seed, 5614)));

        const bool hasThreadTreeOutput = linearGroupThreadId < treeCount;

        ThreadNodeOutputRecords<GenerateTreeRecord> treeOutputRecord =
            treeOutput.GetThreadNodeOutputRecords(hasThreadTreeOutput);

        if (hasThreadTreeOutput) {
            const float  angle  = linearGroupThreadId * (1.5f + Random(seed, 8437));
            const float  radius = linearGroupThreadId * (1.f + Random(seed, 4742));
            const float2 offset = float2(sin(angle), cos(angle)) * radius;

            treeOutputRecord.Get().position = tileCenterWorldPosition.xz + offset;
        }

        treeOutputRecord.OutputComplete();
    }

    // Rock output
    {
        const uint seed = CombineSeed(asuint(threadGridPosition.x), asuint(threadGridPosition.y));

        const float3 biomeWeight   = GetBiomeWeights(threadWorldPosition);
        const float3 terrainNormal = GetTerrainNormal(threadWorldPosition);

        const bool hasRockOutput =
            (abs(terrainGradient) < 500) && (Random(seed, 7982) > 0.75) && (terrainNormal.y > 0.65);

        ThreadNodeOutputRecords<GenerateTreeRecord> rockOutputRecord =
            rockOutput.GetThreadNodeOutputRecords(hasRockOutput);

        if (hasRockOutput) {
            rockOutputRecord.Get().position = threadCenterWorldPosition.xz;
        }

        rockOutputRecord.OutputComplete();
    }
}

bool HasTree(in int2 detailedTileGridPosition, out int outTreeType, out float2 outTreePosition)
{
    outTreeType     = -1;
    // Set position to +inf
    outTreePosition = 1.f / 0.f;

    const float2 detailedTileWorldPosition = detailedTileGridPosition * detailedTileSize;

    const uint seed = CombineSeed(asuint(detailedTileGridPosition.x), asuint(detailedTileGridPosition.y));

    const float3 biomeWeight = GetBiomeWeights(detailedTileWorldPosition);

    // check if woodlands is the dominant biome
    if ((biomeWeight.y < biomeWeight.x) || (biomeWeight.y < biomeWeight.z)) {
        return false;
    }

    const float3 terrainNormal = GetTerrainNormal(detailedTileWorldPosition);

    const float2 randomOffset = float2(Random(seed, 82347), Random(seed, 9780));

    outTreeType     = ((biomeWeight.x > 0.4) || (terrainNormal.y < 0.85)) ? 1 : 0;
    outTreePosition = detailedTileWorldPosition + randomOffset * detailedTileSize;

    return (Random(seed, 7982) > 0.1) &&             // Randomly limit tree occurance
           (Random(seed, 28937) < biomeWeight.y) &&  // Only place trees in woodland biome
           (terrainNormal.y > 0.65);                 // Don't place trees on very steep slopes
}

[Shader("node")]
[NodeId("Tile", 1)]
[NodeLaunch("broadcasting")]
[NodeDispatchGrid(1, 1, 1)]
// each thread corresponds to one detailed tile
[NumThreads(detailedTilesPerTile, detailedTilesPerTile, 1)] 
void WoodlandTile(
    DispatchNodeInputRecord<TileRecord> inputRecord,

    int2 groupThreadId : SV_GroupThreadID,
        
    [MaxRecords(detailedTilesPerTile * detailedTilesPerTile)]
    [NodeId("DetailedTile")]
    NodeOutput<TileRecord> detailedTileOutput,

    [MaxRecords(detailedTilesPerTile * detailedTilesPerTile)]
    [NodeId("GenerateTree")]
    [NodeArraySize(2)]
    NodeOutputArray<GenerateTreeRecord> treeOutput,

    [MaxRecords(1)]
    [NodeId("DrawMushroomPatch")]
    NodeOutput<DrawMushroomRecord> mushroomOutput,
        
    [MaxRecords(1)]
    [NodeId("DrawSparseGrassPatch")]
    NodeOutput<DrawSparseGrassRecord> sparseGrassOutput)
{
    // clear groupshared counters
    sparseGrassPatchCount = 0;
    mushroomPatchCount    = 0;
    butterflyPatchCount   = 0;

    GroupMemoryBarrierWithGroupSync();

    const TileRecord input             = inputRecord.Get();
    const int2       tileGridPosition  = input.position;
    const float2     tileWorldPosition = tileGridPosition * tileSize;

    const int2   threadGridPosition              = tileGridPosition * detailedTilesPerTile + groupThreadId;
    const float2 threadWorldPosition             = threadGridPosition * detailedTileSize;
    const float3 threadCenterWorldPosition       = GetTerrainPosition(threadWorldPosition + detailedTileSize * 0.5);
    const float3 threadCenterCurvedWorldPosition = GetCurvedWorldSpacePosition(threadCenterWorldPosition);
    const float  centerDistanceToCamera          = distance(GetCameraPosition(), threadCenterWorldPosition);

    const AxisAlignedBoundingBox threadBoundingBox =
        GetGridBoundingBox(threadGridPosition, detailedTileSize, -100, 300);
    const bool isThreadVisible = threadBoundingBox.IsVisible(ComputeClipPlanes());

    const uint seed = CombineSeed(asuint(threadGridPosition.x), asuint(threadGridPosition.y));

    // sparse grass
    {

        bool hasOutput = true;

        // --- frustum cull ---
        float radius = sqrt(grassPatchesPerDetailedTile * grassPatchesPerDetailedTile) * grassSpacing;
        if (!IsSphereVisible(threadCenterCurvedWorldPosition, radius, ComputeClipPlanes())) {
            hasOutput = false;
        }

        // --- distance cull ---
        if (((centerDistanceToCamera + radius) < denseGrassMaxDistance) ||
            ((centerDistanceToCamera + radius) > sparseGrassMaxDistance))
        {
            hasOutput = false;
        }

        int outputIndex = 0;

        if (hasOutput) {
            InterlockedAdd(sparseGrassPatchCount, 1, outputIndex);
        }

        GroupMemoryBarrierWithGroupSync();

        GroupNodeOutputRecords<DrawSparseGrassRecord> sparseGrassRecord =
            sparseGrassOutput.GetGroupNodeOutputRecords(sparseGrassPatchCount > 0);

        if (all(groupThreadId == 0) && sparseGrassPatchCount > 0) {
            sparseGrassRecord.Get().dispatchGrid = uint3(sparseGrassPatchCount, sparseGrassThreadGroupsPerRecord, 1);
        }

        if (hasOutput) {
            // XZ-position
            sparseGrassRecord.Get().position[outputIndex] = threadGridPosition;
        }

        sparseGrassRecord.OutputComplete();
    }

    // tree output
    {
        int treeType;
        float2 treePosition;
        const bool hasTreeOutput = HasTree(threadGridPosition, treeType, treePosition);

        ThreadNodeOutputRecords<GenerateTreeRecord> treeOutputRecord =
            treeOutput[treeType].GetThreadNodeOutputRecords(hasTreeOutput);

        if (hasTreeOutput) {
            treeOutputRecord.Get().position = treePosition;
        }

        treeOutputRecord.OutputComplete();

        // Place mushrooms under each tree
        const bool hasMushroomOutput =
            hasTreeOutput && (centerDistanceToCamera < (mushroomMaxDistance * 1.5 + (detailedTileSize * 2)));
        // Select random number of mushrooms to generate
        const int mushroomOutputCount =
            hasMushroomOutput * round(lerp(1, maxMushroomsPerDetailedTile, Random(seed, 67823)));

        // Synchronize mushroom output counts across thread group
        int mushroomOutputIndex = 0;
        if (mushroomOutputCount > 0) {
            InterlockedAdd(mushroomPatchCount, mushroomOutputCount, mushroomOutputIndex);
        }

        GroupMemoryBarrierWithGroupSync();

        GroupNodeOutputRecords<DrawMushroomRecord> mushroomRecord =
            mushroomOutput.GetGroupNodeOutputRecords(mushroomPatchCount > 0);

        if (all(groupThreadId == 0) && mushroomPatchCount > 0) {
            mushroomRecord.Get().dispatchGrid = uint3(mushroomPatchCount, 1, 1);
        }

        for (int mushroomIndex = 0; mushroomIndex < mushroomOutputCount; ++mushroomIndex) {
            const float mushroomAngleRange = PI / 2;
            const float mushroomOffsetAngle =
                (-mushroomAngleRange / 2.f) +
                (mushroomIndex * (mushroomAngleRange / mushroomOutputCount)) +
                (Random(seed, mushroomIndex, 23456) - 1.f) * (mushroomAngleRange / mushroomOutputCount);
            const float  mushroomOffsetRadius = 0.75f + Random(seed, mushroomIndex, 89237) * 0.5f;
            const float2 mushroomOffset =
                float2(cos(mushroomOffsetAngle), sin(mushroomOffsetAngle)) * mushroomOffsetRadius;

            mushroomRecord.Get().position[mushroomOutputIndex + mushroomIndex] =
                GetTerrainPosition(treePosition + mushroomOffset);
        }

        mushroomRecord.OutputComplete();
    }

    // detailed tile output
    {
        const bool hasDetailedTileOutput =
            isThreadVisible && (centerDistanceToCamera < (denseGrassMaxDistance + (detailedTileSize * 2)));

        ThreadNodeOutputRecords<TileRecord> detailedTileOutputRecord =
            detailedTileOutput.GetThreadNodeOutputRecords(hasDetailedTileOutput);

        if (hasDetailedTileOutput) {
            detailedTileOutputRecord.Get().position = tileGridPosition * detailedTilesPerTile + groupThreadId;
        }

        detailedTileOutputRecord.OutputComplete();
    }
}

[Shader("node")]
[NodeId("Tile", 2)]
[NodeLaunch("broadcasting")]
[NodeDispatchGrid(1, 1, 1)]
// each thread corresponds to one detailed tile
[NumThreads(detailedTilesPerTile, detailedTilesPerTile, 1)] 
void GrasslandTile(
    DispatchNodeInputRecord<TileRecord> inputRecord,

    int2 groupThreadId : SV_GroupThreadID,

    [MaxRecords(detailedTilesPerTile * detailedTilesPerTile)]
    [NodeId("DetailedTile")]
    NodeOutput<TileRecord> detailedTileOutput,

    [MaxRecords(1)]
    [NodeId("DrawButterflies")]
    NodeOutput<DrawInsectRecord> butterflyOutput,

    [MaxRecords(1)]
    [NodeArraySize(2)]
    [NodeId("DrawFlowerPatch")]
    NodeOutputArray<DrawFlowerRecord> flowerOutput,

    [MaxRecords(1)]
    [NodeId("DrawBees")]
    NodeOutput<DrawInsectRecord> beeOutput,
        
    [MaxRecords(1)]
    [NodeId("DrawSparseGrassPatch")]
    NodeOutput<DrawSparseGrassRecord> sparseGrassOutput)
{
    // clear groupshared counters
    sparseGrassPatchCount = 0;
    butterflyPatchCount   = 0;
    flowerPatchCount      = 0;
    beePatchCount         = 0;

    GroupMemoryBarrierWithGroupSync();

    const TileRecord input                   = inputRecord.Get();
    const int2       tileGridPosition        = input.position;
    const float2     tileWorldPosition       = tileGridPosition * tileSize;
    const float3     tileCenterWorldPosition = GetTerrainPosition(tileWorldPosition + tileSize * 0.5);

    const int2   threadGridPosition              = tileGridPosition * detailedTilesPerTile + groupThreadId;
    const float2 threadWorldPosition             = threadGridPosition * detailedTileSize;
    const float3 threadCenterWorldPosition       = GetTerrainPosition(threadWorldPosition + detailedTileSize * 0.5);
    const float3 threadCenterCurvedWorldPosition = GetCurvedWorldSpacePosition(threadCenterWorldPosition);
    const float  centerDistanceToCamera          = distance(GetCameraPosition(), threadCenterWorldPosition);

    const AxisAlignedBoundingBox threadBoundingBox =
        GetGridBoundingBox(threadGridPosition, detailedTileSize, -100, 300);
    const bool isThreadVisible = threadBoundingBox.IsVisible(ComputeClipPlanes());

    const uint seed    = CombineSeed(asuint(threadGridPosition.x), asuint(threadGridPosition.y));
    const bool isNight = (GetTimeOfDay() > nightStartTime) || (GetTimeOfDay() < nightEndTime);

    // sparse grass
    {
        bool hasOutput = true;

        // --- frustum cull ---
        float radius = sqrt(grassPatchesPerDetailedTile * grassPatchesPerDetailedTile) * grassSpacing;
        if (!IsSphereVisible(threadCenterCurvedWorldPosition, radius, ComputeClipPlanes())) {
            hasOutput = false;
        }

        // --- distance cull ---
        if (((centerDistanceToCamera + radius) < denseGrassMaxDistance) ||
            ((centerDistanceToCamera + radius) > sparseGrassMaxDistance))
        {
            hasOutput = false;
        }

        int outputIndex = 0;

        if (hasOutput) {
            InterlockedAdd(sparseGrassPatchCount, 1, outputIndex);
        }

        GroupMemoryBarrierWithGroupSync();

        GroupNodeOutputRecords<DrawSparseGrassRecord> sparseGrassRecord =
            sparseGrassOutput.GetGroupNodeOutputRecords(sparseGrassPatchCount > 0);

        if (all(groupThreadId == 0) && sparseGrassPatchCount > 0) {
            sparseGrassRecord.Get().dispatchGrid = uint3(sparseGrassPatchCount, sparseGrassThreadGroupsPerRecord, 1);
        }

        if (hasOutput) {
            // XZ-position
            sparseGrassRecord.Get().position[outputIndex] = threadGridPosition;
        }

        sparseGrassRecord.OutputComplete();
    }
        
    // butterfly output
    {
        // 2% chance of spawning butterflies
        const float butterflyProbability = 0.02f;
        const bool  hasButterflyOutput =
            !isNight &&                                         // no butterflies at night
            (centerDistanceToCamera < butterflyMaxDistance) &&  // cull butterflies in distance
            (Random(seed, 1998) < butterflyProbability);

        int butterflyOutputIndex = 0;

        if (hasButterflyOutput) {
            InterlockedAdd(butterflyPatchCount, 1, butterflyOutputIndex);
        }

        GroupMemoryBarrierWithGroupSync();

        GroupNodeOutputRecords<DrawInsectRecord> butterflyOutputRecord =
            butterflyOutput.GetGroupNodeOutputRecords(butterflyPatchCount > 0);

        if (all(groupThreadId == 0) && butterflyPatchCount > 0) {
            butterflyOutputRecord.Get().dispatchGrid = uint3(butterflyPatchCount, 1, 1);
        }

        if (hasButterflyOutput) {
            // XZ-position
            butterflyOutputRecord.Get().position[butterflyOutputIndex] = threadCenterWorldPosition;
        }

        butterflyOutputRecord.OutputComplete();
    }

    // flower output
    {
        const float3 biomeWeight = GetBiomeWeights(threadWorldPosition);

        // cull flowers for visibility and max distance
        const float flowerCullDistance = flowerMaxDistance - (Random(seed, 8437) * flowerMaxDistance * 0.2);
        const bool  hasFlowerOutput    = isThreadVisible && (centerDistanceToCamera < flowerCullDistance);
        // select random number of flowers to generate. number also depends on meadow biome weight
        const int   flowerOutputCount =
            hasFlowerOutput * round(lerp(0, maxFlowersPerDetailedTile, Random(seed, 2134) * biomeWeight.z));
        // 30% chance of spawning bees over a flower
        const float beeProbability = 0.3f;
        // one of the generated flowers can also spawn a bee patch
        const bool  hasBeeOutput   = (flowerOutputCount > 0) &&                 // patch has at least one flower
                                  !isNight &&                                   // no bees at night
                                  (centerDistanceToCamera < beeMaxDistance) &&  // cull bees in distance
                                  (Random(seed, 2378) < beeProbability);        // limit bee occurrance

        // output indices into shared records
        int flowerOutputIndex = 0;
        int beeOutputIndex    = 0;

        // increment shared flower/bee counters
        if (flowerOutputCount > 0) {
            InterlockedAdd(flowerPatchCount, flowerOutputCount, flowerOutputIndex);
        }
        if (hasBeeOutput) {
            InterlockedAdd(beePatchCount, 1, beeOutputIndex);
        }

        GroupMemoryBarrierWithGroupSync();

        const uint flowerType = (distance(GetCameraPosition(), tileCenterWorldPosition) > flowerSparseStartDistance);

        GroupNodeOutputRecords<DrawFlowerRecord> flowerOutputRecord =
            flowerOutput[flowerType].GetGroupNodeOutputRecords(flowerPatchCount > 0);
        GroupNodeOutputRecords<DrawInsectRecord> beeOutputRecord =
            beeOutput.GetGroupNodeOutputRecords(beePatchCount > 0);

        if (all(groupThreadId == 0) && flowerPatchCount > 0) {
            if (flowerType == 1) {
                flowerOutputRecord.Get().dispatchGrid = uint3(
                    (flowerPatchCount + flowersInSparseFlowerThreadGroup - 1) / flowersInSparseFlowerThreadGroup, 1, 1);
            } else {
                flowerOutputRecord.Get().dispatchGrid = uint3(flowerPatchCount, 1, 1);
            }
            flowerOutputRecord.Get().flowerPatchCount = flowerPatchCount;
        }
        if (all(groupThreadId == 0) && beePatchCount > 0) {
            beeOutputRecord.Get().dispatchGrid = uint3(beePatchCount, 1, 1);
        }

        for (int flowerId = 0; flowerId < flowerOutputCount; ++flowerId) {
            const float2 offset =
                float2(Random(asuint(threadWorldPosition.x), asuint(threadWorldPosition.y), flowerId, 4387),
                       Random(asuint(threadWorldPosition.x), asuint(threadWorldPosition.y), flowerId, 8327)) *
                detailedTileSize;

            flowerOutputRecord.Get().position[flowerOutputIndex + flowerId] = threadWorldPosition + offset;
        }

        if (hasBeeOutput) {
            beeOutputRecord.Get().position[beeOutputIndex] =
                GetTerrainPosition(flowerOutputRecord.Get().position[flowerOutputIndex]);
        }

        flowerOutputRecord.OutputComplete();
        beeOutputRecord.OutputComplete();
    }

    // detailed tile output
    {
        const bool hasDetailedTileOutput =
            isThreadVisible && (centerDistanceToCamera < (denseGrassMaxDistance + (detailedTileSize * 2)));

        ThreadNodeOutputRecords<TileRecord> detailedTileOutputRecord =
            detailedTileOutput.GetThreadNodeOutputRecords(hasDetailedTileOutput);

        if (hasDetailedTileOutput) {
            detailedTileOutputRecord.Get().position = tileGridPosition * detailedTilesPerTile + groupThreadId;
        }

        detailedTileOutputRecord.OutputComplete();
    }
}

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeDispatchGrid(1, 1, 1)]
// each thread corresponds to one grass patch tile
[NumThreads(grassPatchesPerDetailedTile, grassPatchesPerDetailedTile, 1)] 
void DetailedTile(
    DispatchNodeInputRecord<TileRecord> inputRecord,

    int2 groupThreadId : SV_GroupThreadID,

    // Node outputs:
    [MaxRecords(1)]
    [NodeId("DrawDenseGrassPatch")]
    NodeOutput<DrawDenseGrassRecord> grassOutput)
{
    // clear groupshared counters
    denseGrassPatchCount = 0;

    GroupMemoryBarrierWithGroupSync();
    
    const TileRecord input = inputRecord.Get();

    const int2               tileGridPosition  = input.position;
    const float2             tileWorldPosition = tileGridPosition * detailedTileSize;

    const int2   threadGridPosition  = tileGridPosition * grassPatchesPerDetailedTile + groupThreadId;
    const float2 threadWorldPosition = (threadGridPosition + GetGrassOffset(threadGridPosition)) * grassSpacing;

    // get terrain height and normal & biome weights
    const float3 patchPosition = GetTerrainPosition(threadWorldPosition.x, threadWorldPosition.y);
    const float3 patchNormal   = GetTerrainNormal(threadWorldPosition.x, threadWorldPosition.y);
    const float3 biomeWeights  = GetBiomeWeights(threadWorldPosition);
    
    bool hasOutput = true;

    // don't spawn grass on extremly steep slopes
    if (patchNormal.y < 0.55) {
        hasOutput = false;
    }

    // cull against view frustum
    const float radius = 4 * grassSpacing;
    if (!IsSphereVisible(patchPosition, radius, ComputeClipPlanes())) {
        hasOutput = false;
    }

    const float distanceToCamera = distance(GetCameraPosition(), patchPosition.xyz);

    // cull against distance to camera
    if (distanceToCamera > denseGrassMaxDistance) {
        hasOutput = false;
    }
    
    // cull at biome transitions to mountain biome
    if (Random(asuint(patchPosition.x), asuint(patchPosition.z), 2378) < biomeWeights.x * 2) {
        hasOutput = false;
    }

    const float minGrassHeight = 0.2;
    const float maxGrassHeight = minGrassHeight + .35;
    const float grassHeight    = minGrassHeight + (maxGrassHeight - minGrassHeight) * Random(threadGridPosition.x, threadGridPosition.y, 34567);

    // Each dense grass mesh shader can only render 16 grass blades.
    // If grass patch has more than 16 blades, we require two thread groups to draw this patch
    const bool hasSplitOutput =
        lerp(32.f, 2., pow(saturate(distanceToCamera / (denseGrassMaxDistance * 1.05)), 0.75)) > 16.f;
    
    // Output dense grass
    {
        // sync total dense grass count
        uint grassOutputIndex  = 0;

        if (hasOutput) {
            InterlockedAdd(denseGrassPatchCount, hasSplitOutput? 2 : 1, grassOutputIndex);
        }

        GroupMemoryBarrierWithGroupSync();

        GroupNodeOutputRecords<DrawDenseGrassRecord> denseGrassRecord =
            grassOutput.GetGroupNodeOutputRecords(denseGrassPatchCount > 0);

        if (all(groupThreadId == 0) && denseGrassPatchCount > 0) {
            denseGrassRecord.Get().dispatchGrid = uint3(denseGrassPatchCount, 1, 1);
        }

        if (hasOutput) {
            denseGrassRecord.Get().position[grassOutputIndex]    = patchPosition;
            denseGrassRecord.Get().height[grassOutputIndex]      = grassHeight;
            denseGrassRecord.Get().bladeOffset[grassOutputIndex] = 0;

            if (hasSplitOutput) {
                denseGrassRecord.Get().position[grassOutputIndex + 1]    = patchPosition;
                denseGrassRecord.Get().height[grassOutputIndex + 1]      = grassHeight;
                denseGrassRecord.Get().bladeOffset[grassOutputIndex + 1] = 1;
            }
        }

        denseGrassRecord.OutputComplete();
    }
}