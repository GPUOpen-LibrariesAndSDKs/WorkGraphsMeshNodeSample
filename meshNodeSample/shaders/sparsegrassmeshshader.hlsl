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

static const int sparseGrassGroupSize    = 128;
static const int numOutputVerticesLimit  = 128;
static const int numOutputTrianglesLimit = 64;

// multiple 8x4 patches fill a detailed tile
static const int2 sparseGrassThreadGroupGridSize = int2(8, 4);
static const int2 spraseGrassThreadGroupsPerAxis = grassPatchesPerDetailedTile / sparseGrassThreadGroupGridSize;

float2 GetPatchPosition(in int patch, in int patchOffset, in int2 gridBase)
{
    const int x = patch % sparseGrassThreadGroupGridSize.x;
    const int z = patch / sparseGrassThreadGroupGridSize.x;

    const int offsetX = patchOffset % spraseGrassThreadGroupsPerAxis.x;
    const int offsetZ = patchOffset / spraseGrassThreadGroupsPerAxis.x;

    const int2 grid = int2(x, z) + int2(offsetX, offsetZ) * sparseGrassThreadGroupGridSize;

    return grassSpacing * gridBase +
           (grid + GetGrassOffset(gridBase + grid)) * grassSpacing * (8.0 / sparseGrassThreadGroupGridSize.x);
}


[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawSparseGrassPatch", 0)]
[NodeMaxDispatchGrid(maxSparseGrassPatchesPerRecord, sparseGrassThreadGroupsPerRecord, 1)]
// This limit was set through instrumentation and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(100, true)]
[NumThreads(sparseGrassGroupSize, 1, 1)]
[OutputTopology("triangle")]
void SparseGrassMeshShader(
    uint                                           gtid : SV_GroupThreadID,
    uint2                                          gid : SV_GroupID,
    DispatchNodeInputRecord<DrawSparseGrassRecord> inputRecord,
    out indices uint3                              tris[numOutputTrianglesLimit],
    out primitives GrassCullPrimitive              prims[numOutputTrianglesLimit],
    out vertices GrassVertex                       verts[numOutputVerticesLimit])
{
    const int bladeCount    = sparseGrassThreadGroupGridSize.x * sparseGrassThreadGroupGridSize.y;
    // 4 vertices per blade
    const int vertexCount   = bladeCount * 4;
    // 2 triangles per blade
    const int triangleCount = bladeCount * 2;

    SetMeshOutputCounts(vertexCount, triangleCount);

    GrassVertex vertex;

    float low  = .05;
    float high = .45;

    float3 color = pow(float3(0.41, 0.44, 0.29), 2.2) * .775;

    const int2 gridBase = inputRecord.Get().position[gid.x] * grassPatchesPerDetailedTile;

    static const float3 grassColor = float3(0.130139, 0.149961, 0.059513);

    if (gtid < vertexCount) {
        int  vertexId = gtid;
        int  patch    = vertexId / 4;
        int  vi       = vertexId % 4;
        bool isLow    = vi == 0 || vi == 1;
        bool isRight  = vi == 0 || vi == 2;

        const float2 pos = GetPatchPosition(patch, gid.y, gridBase);

        float3 patchNormal = GetTerrainNormal(pos);

        float3 center = float3(pos.x, GetTerrainHeight(pos), pos.y);

        // Fade grass into the ground in the distance
        const float distanceScale = smoothstep(sparseGrassMaxDistance * 0.9, sparseGrassMaxDistance, distance(center, GetCameraPosition()));
        center.y -= high * distanceScale;

        float3 center2cam = normalize(GetCameraPosition() - center);

        float3 forward = normalize(float3(center2cam.x, min(0.2, center2cam.y), center2cam.z));
        float3 right   = normalize(cross(center2cam, float3(0, 1, 0)));

        float3 up = normalize(cross(right, forward));

        vertex.worldSpacePosition = center;
        vertex.worldSpacePosition += right * BitSign((uint)isRight, 0) * grassSpacing;
        vertex.worldSpacePosition += up * (isLow ? (low) : high);

        vertex.worldSpacePosition.xz += center2cam.xz * (length(center2cam) / 1000.);
        vertex.worldSpacePosition.y = center.y + (isLow ? (low + center2cam.y * 0.2) : high);

        vertex.rootHeight             = center.y + .08;
        vertex.height                 = high;
        vertex.worldSpaceNormal       = isLow ? normalize(float3(center2cam.x, 0, center2cam.z)) : float3(0, 1, 0);
        vertex.worldSpaceGroundNormal = patchNormal;

        ComputeClipSpacePositionAndMotion(vertex, vertex.worldSpacePosition);

        verts[vertexId] = vertex;
    }

    if (gtid < triangleCount) {
        const int patch = gtid / 2;
        const int base  = 4 * patch;

        const float2 pos    = GetPatchPosition(patch, gid.y, gridBase);
        const float3 center = float3(pos.x, GetTerrainHeight(pos), pos.y);

        const float3 terrainNormal = GetTerrainNormal(pos);
        const float3 biomeWeight   = GetBiomeWeights(pos);

        const bool cull = (Random(asuint(pos.x), asuint(pos.y), 2378) < biomeWeight.x * 2) ||
                          (terrainNormal.y < 0.55);

        uint3 tri = (gtid % 2) == 0 ? uint3(base, base + 1, base + 2) : uint3(base + 3, base + 2, base + 1);

        tris[gtid]       = tri;
        prims[gtid].cull = cull;
    }
}