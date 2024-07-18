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

struct TransformedVertex {
    float4 clipSpacePosition : SV_POSITION;
    float3 worldSpacePosition : NORMAL0;
    float3 normal : NORMAL1;
    float2 clipSpaceMotion : TEXCOORD0;
};

uint3 GetPrimitive(uint index, in uint primitivesPerRow)
{
    uint verticesPerRow = primitivesPerRow + 1;

    uint cell = index / 2;
    uint row  = cell / primitivesPerRow;
    cell      = cell % primitivesPerRow;

    uint base = (row * verticesPerRow) + cell;

    // c - d
    // | / |
    // a - b
    const uint a = base;
    const uint b = base + 1;
    const uint c = base + verticesPerRow;
    const uint d = base + verticesPerRow + 1;

    return (index % 2) == 0 ? uint3(a, c, d) : uint3(d, b, a);
}

[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawTerrainChunk", 0)]
[NodeMaxDispatchGrid(8, 8, 1)]
// This limit reflects the maximum dispatch size of the chunk grid and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(32 * 32, true)]
[NumThreads(128, 1, 1)]
[OutputTopology("triangle")]
void TerrainMeshShader(
    uint gtid : SV_GroupThreadID,
    uint2 gid : SV_GroupID,
    DispatchNodeInputRecord<DrawTerrainChunkRecord> inputRecord,
    out indices uint3 tris[128],
    out vertices TransformedVertex verts[81])
{
    const DrawTerrainChunkRecord record = inputRecord.Get();

    const int levelOfDetail                = record.levelOfDetail;
    // number of thread groups per chunk axis for LOD 0
    const int baseThreadGroupsPerChunkAxis = 8;

    const int threadGroupsPerChunkAxis =
        baseThreadGroupsPerChunkAxis / clamp(1L << levelOfDetail, 1, baseThreadGroupsPerChunkAxis);
    const int threadGroupIdScale       = baseThreadGroupsPerChunkAxis / threadGroupsPerChunkAxis;

    const int   primitivesPerAxis = 8;
    const int   verticesPerAxis   = primitivesPerAxis + 1;
    const float scale             = chunkSize / float(primitivesPerAxis * baseThreadGroupsPerChunkAxis);

    const int vertexCount    = verticesPerAxis * verticesPerAxis;
    const int primitiveCount = primitivesPerAxis * primitivesPerAxis * 2;

    SetMeshOutputCounts(vertexCount, primitiveCount);

    const int2 tile = record.chunkGridPosition * baseThreadGroupsPerChunkAxis + int2(gid.xy) * threadGroupIdScale;

    const bool4 localLevelOfDetailTransition =
        bool4(record.levelOfDetailTransition.x && (gid.x == 0),
              record.levelOfDetailTransition.y && (gid.y == 0),
              record.levelOfDetailTransition.z && (gid.x == (record.dispatchGrid.x - 1)),
              record.levelOfDetailTransition.w && (gid.y == (record.dispatchGrid.y - 1)));

    if (gtid < vertexCount) {
        TransformedVertex vertex;

        int2 localVertexIndex = int2(gtid % verticesPerAxis, gtid / verticesPerAxis);

        // collapse vertices along LOD borders
        if (localLevelOfDetailTransition.x && (localVertexIndex.x == 0) && ((localVertexIndex.y % 2) == 1)) {
            localVertexIndex.y = int(localVertexIndex.y / 2) * 2;
        }
        if (localLevelOfDetailTransition.y && (localVertexIndex.y == 0) && ((localVertexIndex.x % 2) == 1)) {
            localVertexIndex.x = int(localVertexIndex.x / 2) * 2;
        }
        if (localLevelOfDetailTransition.z && (localVertexIndex.x == 8) && ((localVertexIndex.y % 2) == 1)) {
            localVertexIndex.y = int(localVertexIndex.y / 2) * 2;
        }
        if (localLevelOfDetailTransition.w && (localVertexIndex.y == 8) && ((localVertexIndex.x % 2) == 1)) {
            localVertexIndex.x = int(localVertexIndex.x / 2) * 2;
        }

        localVertexIndex *= threadGroupIdScale;

        const int2 globalVertexIndex = tile * primitivesPerAxis + localVertexIndex;

        const float2 globalVertexPosition = globalVertexIndex * scale;

        const float3 worldSpacePosition =
            float3(globalVertexPosition.x, GetTerrainHeight(globalVertexPosition), globalVertexPosition.y);

        vertex.normal             = GetTerrainNormal(worldSpacePosition.xz);
        vertex.worldSpacePosition = worldSpacePosition;
        ComputeClipSpacePositionAndMotion(vertex, worldSpacePosition);

        verts[gtid] = vertex;
    }

    {
        tris[gtid] = GetPrimitive(gtid, 8);
    }
}

DeferredPixelShaderOutput TerrainPixelShader(TransformedVertex input)
{
    DeferredPixelShaderOutput output;

    output.normal = float4(normalize(input.normal), 1);
    output.motion = input.clipSpaceMotion;

    const float3 biomeWeights = GetBiomeWeights(input.worldSpacePosition.xz);
    const float  biomeFactor  = lerp(1.0, 0.75, biomeWeights.y);

    const float3 grassColor = pow(float3(0.41, 0.44, 0.29) * 2, 2.2) * 0.65 * biomeFactor *
                              (0.75 + 0.25 * PerlinNoise2D(0.25 * input.worldSpacePosition.xz));
    const float3 rockColor = float3(0.24, 0.24, 0.24);

    output.baseColor.rgb = lerp(grassColor, rockColor, biomeWeights.x);
    output.baseColor.a   = 1.0;

    return output;
}