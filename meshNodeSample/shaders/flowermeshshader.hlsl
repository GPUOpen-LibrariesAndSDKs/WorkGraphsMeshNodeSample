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

static const int flowerGroupSize = 128;

static const int stemVertexCount   = 6;
static const int stemTriangleCount = 6;

static const int headMaxRingCount     = 6;
static const int headMaxVertexCount   = headMaxRingCount * 2 + 2;
static const int headMaxTriangleCount = headMaxRingCount * 4;

static const int flowerMaxVertexCount   = stemVertexCount + headMaxVertexCount;
static const int flowerMaxTriangleCount = stemTriangleCount + headMaxTriangleCount;

static const int outputMaxVertexCount   = 128;
static const int outputMaxTriangleCount = 256;
static const int maxFlowerCount =
    min(outputMaxVertexCount / flowerMaxVertexCount, outputMaxTriangleCount / flowerMaxTriangleCount);

static const int numOutputVertices  = maxFlowerCount * flowerMaxVertexCount;
static const int numOutputTriangles = maxFlowerCount * flowerMaxTriangleCount;

static const int numOutputVertexIterations   = (numOutputVertices + (flowerGroupSize - 1)) / flowerGroupSize;
static const int numOutputTriangleIterations = (numOutputTriangles + (flowerGroupSize - 1)) / flowerGroupSize;

static const int sparseFlowerVertexCount = 4;
static const int sparseFlowerTriangleCount = 2;

static const int sparseOutputMaxVertexCount   = 128;
static const int sparseOutputMaxTriangleCount = 64;
// maximum number of flower patches that can be rendered by one sparse flower thread group
static const int maxSparseFlowerPatchesPerThreadGroup = min(sparseOutputMaxVertexCount / sparseFlowerVertexCount,
                                                            sparseOutputMaxTriangleCount / sparseFlowerTriangleCount) /
                                                        maxFlowerCount;

static const int numSparseOutputVertices =
    maxSparseFlowerPatchesPerThreadGroup * maxFlowerCount * sparseFlowerVertexCount;
static const int numSparseOutputTriangles =
    maxSparseFlowerPatchesPerThreadGroup * maxFlowerCount * sparseFlowerTriangleCount;


float GetFlowerHeight(in int flowerId, in uint seed)
{
    return .5f + Random(seed, 79823, flowerId) * 0.2f;
}

float2 GetFlowerPosition(in int flowerId, in uint seed)
{
    const float flowerPositionAngle  = flowerId + Random(seed, 324897, flowerId);
    const float flowerPositionRadius = 0.05f + (flowerId * 0.05f) + Random(seed, flowerId, 4732) * 0.1f;
    return float2(cos(flowerPositionAngle), sin(flowerPositionAngle)) * flowerPositionRadius;
}

float3 GetFlowerColor(in int flowerId, in uint seed)
{
    static const float3 flowerColor[] = {
        float3(1.0, 0.95, 0.95),
        float3(1.0, 0.95, 0.95),
        float3(1.0, 0.95, 0.95),
        float3(1.0, 0.2, 0.3),
        float3(1.0, 0.4, 1.0),
        float3(0.95, 0.8, 0.0),
        float3(0.7, 0.7, 1.0),
    };

    return flowerColor[Random(seed, flowerId) * 7];
}

int GetFlowerCount(in int seed) {
    return round(lerp(2, maxFlowerCount, Random(seed, 6145)));
}

static const float3 flowerStemColor = pow(float3(0.82, 0.89, 0.58), 2.2);

[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawFlowerPatch", 0)]
[NodeMaxDispatchGrid(maxFlowersPerRecord, 1, 1)]
// This limit was set through instrumentation and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(200, true)]
[NumThreads(flowerGroupSize, 1, 1)]
[OutputTopology("triangle")]
void FlowerMeshShader(
    uint                                      gtid : SV_GroupThreadID,
    uint                                      gid : SV_GroupID,
    DispatchNodeInputRecord<DrawFlowerRecord> inputRecord,
    out indices uint3                         tris[numOutputTriangles],
    out vertices InsectVertex                 verts[numOutputVertices])
{
    const DrawFlowerRecord record = inputRecord.Get();

    const float3 patchPosition = GetTerrainPosition(inputRecord.Get().position[gid]);
    const uint   seed          = CombineSeed(asuint(patchPosition.x), asuint(patchPosition.z));

    const int flowerCount         = GetFlowerCount(seed);
    const int headRingVertexCount = round(lerp(4, headMaxRingCount, Random(seed, 7878)));

    const int headVertexCount   = headRingVertexCount * 2 + 2;
    const int headTriangleCount = headRingVertexCount * 4;

    const int totalStemVertexCount   = flowerCount * stemVertexCount;
    const int totalStemTriangleCount = flowerCount * stemTriangleCount;

    const int totalHeadVertexCount   = flowerCount * headVertexCount;
    const int totalHeadTriangleCount = flowerCount * headTriangleCount;

    const int vertexCount   = totalStemVertexCount + totalHeadVertexCount;
    const int triangleCount = totalStemTriangleCount + totalHeadTriangleCount;

    SetMeshOutputCounts(vertexCount, triangleCount);

    [[unroll]]
    for (uint i = 0; i < numOutputVertexIterations; ++i)
    {
        const int vertId = gtid + flowerGroupSize * i;

        int    flowerId;
        float3 localVertexPosition;
        float3 color;

        if (vertId < totalStemVertexCount) {
            // vertex is stem vertex

            flowerId               = vertId / stemVertexCount;
            const int stemVertexId = vertId % stemVertexCount;

            const bool isTopVertex = stemVertexId >= 3;

            const float flowerHeight       = GetFlowerHeight(flowerId, seed);
            const float stemRadius         = .03f * (isTopVertex ? 0.8f : 1.f) + Random(seed, 87324, flowerId) * 0.02f;
            const float stemRotationOffset = flowerId;

            const float  vertexAngle        = stemRotationOffset + stemVertexId * ((2 * PI) / 3.f);
            const float2 vertexRingPosition = float2(cos(vertexAngle), sin(vertexAngle)) * stemRadius;

            const float vertexY = isTopVertex ? flowerHeight : 0;
            localVertexPosition = float3(vertexRingPosition.x, vertexY, vertexRingPosition.y);

            color = flowerStemColor;
        } else if (vertId < (totalStemVertexCount + totalHeadVertexCount)) {
            const int vertexOffset = totalStemVertexCount;

            flowerId               = (vertId - vertexOffset) / headVertexCount;
            const int headVertexId = (vertId - vertexOffset) % headVertexCount;

            const bool isBottomVertex = headVertexId == 0;
            const bool isTopVertex    = headVertexId == (headVertexCount - 1);
            const int  headVertexRing = (headVertexId - 1) / headRingVertexCount;

            const float flowerHeight = GetFlowerHeight(flowerId, seed);
            const float headRadius   = (isBottomVertex || isTopVertex) ? 0.f : (.08f * (1 + (headVertexRing * 0.2)));
            const float headRotationOffset = flowerId;

            const float  vertexAngle = headRotationOffset + headVertexId * ((2 * PI) / float(headRingVertexCount));
            const float2 vertexRingPosition = float2(cos(vertexAngle), sin(vertexAngle)) * headRadius;

            const float ringHeight = 0.05f;
            float       vertexY    = flowerHeight + headVertexRing * ringHeight;
            if (isTopVertex) {
                vertexY = flowerHeight + 0 * ringHeight;
            }
            if (isBottomVertex) {
                vertexY = flowerHeight - ringHeight;
            }

            localVertexPosition = float3(vertexRingPosition.x, vertexY, vertexRingPosition.y);

            color = GetFlowerColor(flowerId, seed);
        }

        if (vertId < vertexCount) {
            const float2 flowerPositionOffset = GetFlowerPosition(flowerId, seed);
            const float3 windOffset           = localVertexPosition.y * GetWindStrength() *
                                                GetWindOffset(patchPosition.xz + flowerPositionOffset, GetTime());
            const float3 previousWindOffset = localVertexPosition.y * GetWindStrength() *
                                              GetWindOffset(patchPosition.xz + flowerPositionOffset, GetPreviousTime());

            InsectVertex vertex;
            vertex.objectSpacePosition =
                float3(flowerPositionOffset.x, 0, flowerPositionOffset.y) + localVertexPosition + windOffset;
            vertex.color = color;

            const float3 worldSpaceBasePosition =
                patchPosition + float3(flowerPositionOffset.x, 0, flowerPositionOffset.y) + localVertexPosition;

            ComputeClipSpacePositionAndMotion(
                vertex, worldSpaceBasePosition + windOffset, worldSpaceBasePosition + previousWindOffset);

            verts[vertId] = vertex;
        }
    }

    [[unroll]]
    for (uint i = 0; i < numOutputTriangleIterations; ++i)
    {
        const int triId = gtid + flowerGroupSize * i;

        uint3 triangleIndices = uint3(0, 1, 2);

        if (triId < totalStemTriangleCount) {
            // triangle is stem triangle

            const int flowerId       = triId / stemTriangleCount;
            const int stemTriangleId = triId % stemTriangleCount;

            const int stemVertexOffset = flowerId * stemVertexCount;

            const uint  base = stemTriangleId / 2;
            // z -- w
            // | \  |
            // |  \ |
            // y -- x
            const uint4 quad = uint4(base, (base + 1) % 3, (base + 1) % 3 + 3, base + 3);

            triangleIndices = stemVertexOffset + ((stemTriangleId & 0x1) ? quad.xyz : quad.xzw);
        } else if (triId < (totalStemTriangleCount + totalHeadTriangleCount)) {
            // triangle is head triangle

            const int triangleOffset = totalStemTriangleCount;

            const int headId         = (triId - triangleOffset) / headTriangleCount;
            const int headTriangleId = (triId - triangleOffset) % headTriangleCount;

            const int bottomVertexId         = 0;
            const int topVertexId            = 1 + (2 * headRingVertexCount);
            const int firstRingVertexOffset  = 1;
            const int secondRingVertexOffset = 1 + headRingVertexCount;

            const int headVertexOffset = totalStemVertexCount + headId * headVertexCount;

            triangleIndices = headVertexOffset + uint3(0, 0, 0);

            if (headTriangleId < (2 * headRingVertexCount)) {
                const uint  base         = headTriangleId / 2;
                const uint3 ringTriangle = uint3(bottomVertexId,
                                                 firstRingVertexOffset + base,
                                                 firstRingVertexOffset + (base + 1) % headRingVertexCount);

                triangleIndices =
                    headVertexOffset + ((headTriangleId & 0x1) ? (topVertexId - ringTriangle) : ringTriangle);
            } else {
                const uint base = (headTriangleId - (2 * headRingVertexCount)) / 2;

                const uint3 ringTriangle = uint3(firstRingVertexOffset + base,
                                                 firstRingVertexOffset + (base + 1) % headRingVertexCount,
                                                 firstRingVertexOffset + base + headRingVertexCount);

                triangleIndices =
                    headVertexOffset + ((headTriangleId & 0x1) ? (topVertexId - ringTriangle) : ringTriangle);
            }
        }

        if (triId < triangleCount) {
            tris[triId] = triangleIndices;
        }
    }
}

[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawFlowerPatch", 1)]
[NodeMaxDispatchGrid(maxFlowersPerRecord / flowersInSparseFlowerThreadGroup, 1, 1)]
// This limit was set through instrumentation and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(200, true)]
[NumThreads(flowerGroupSize, 1, 1)]
[OutputTopology("triangle")]
void SparseFlowerMeshShader(
    uint                                      gtid : SV_GroupThreadID,
    uint                                      gid : SV_GroupID,
    DispatchNodeInputRecord<DrawFlowerRecord> inputRecord,
    out indices uint3                         tris[numOutputTriangles],
    out vertices InsectVertex                 verts[numOutputVertices])
{
    const int recordPositionOffset = gid * maxSparseFlowerPatchesPerThreadGroup;
    const int threadGroupPatchCount =
        clamp(int(inputRecord.Get().flowerPatchCount) - recordPositionOffset, 0, maxSparseFlowerPatchesPerThreadGroup);

    int totalFlowerCount = 0;

    if (WaveGetLaneIndex() < threadGroupPatchCount) {
        const float2 lanePatchPosition = inputRecord.Get().position[recordPositionOffset + WaveGetLaneIndex()];
        const int    laneSeed          = CombineSeed(asuint(lanePatchPosition.x), asuint(lanePatchPosition.y));
        const int    laneFlowerCount   = GetFlowerCount(laneSeed);

        totalFlowerCount = laneFlowerCount;
    }

    totalFlowerCount = WaveActiveSum(totalFlowerCount);

    const int vertexCount   = totalFlowerCount * sparseFlowerVertexCount;
    const int triangleCount = totalFlowerCount * sparseFlowerTriangleCount;

    SetMeshOutputCounts(vertexCount, triangleCount);

    if (gtid < vertexCount) {
        float3 patchPosition = 0;
        uint   seed     = 0;
        int    vertexId = 0;

        {
            int runningVertexCount = 0;

            for (int i = 0; i < maxSparseFlowerPatchesPerThreadGroup; ++i) {
                const float2 candidatePatchPosition = inputRecord.Get().position[recordPositionOffset + i];
                const int    candidateSeed =
                    CombineSeed(asuint(candidatePatchPosition.x), asuint(candidatePatchPosition.y));
                const int candidateFlowerCount = GetFlowerCount(candidateSeed);
                const int candidateVertexCount = candidateFlowerCount * sparseFlowerVertexCount;

                if ((gtid >= runningVertexCount) && (gtid < (runningVertexCount + candidateVertexCount))) {
                    patchPosition = GetTerrainPosition(candidatePatchPosition);
                    seed          = candidateSeed;
                    vertexId      = gtid - runningVertexCount;
                }

                runningVertexCount += candidateVertexCount;
            }
        }

        const int flowerId       = vertexId / sparseFlowerVertexCount;
        const int flowerVertexId = vertexId % sparseFlowerVertexCount;

        const float2 flowerPositionOffset = GetFlowerPosition(flowerId, seed);
        const float  flowerHeight         = GetFlowerHeight(flowerId, seed);

        const float3 viewVector = normalize(patchPosition - GetCameraPosition());
        const float3 side       = normalize(cross(viewVector, float3(0, 1, 0)));
        const float3 back       = normalize(float3(viewVector.x, 0, viewVector.z));

        const float width = 0.1;
        const float depth = 0.15;

        float3 localVertexPosition = 0;

        if (flowerVertexId == 1) {
            localVertexPosition = float3(0, flowerHeight, 0) + side * width;
        } else if (flowerVertexId == 2) {
            localVertexPosition = float3(0, flowerHeight, 0) - side * width;
        } else if (flowerVertexId == 3) {
            localVertexPosition = float3(0, flowerHeight, 0) + back * depth;
        }

        InsectVertex vertex;
        vertex.objectSpacePosition =
            float3(flowerPositionOffset.x, 0, flowerPositionOffset.y) + localVertexPosition;

        if (flowerVertexId == 0) {
            vertex.color = flowerStemColor;
        } else {
            vertex.color = GetFlowerColor(flowerId, seed);
        }

        ComputeClipSpacePositionAndMotion(
            vertex, patchPosition + float3(flowerPositionOffset.x, 0, flowerPositionOffset.y) + localVertexPosition);

        verts[gtid] = vertex;

    }

    if (gtid < triangleCount) {
        const int flowerId         = gtid / sparseFlowerTriangleCount;
        const int flowerTriangleId = gtid % sparseFlowerTriangleCount;

        const int flowerVertexOffset = flowerId * sparseFlowerVertexCount;

        tris[gtid] = flowerVertexOffset + ((flowerTriangleId & 0x1) ? uint3(0, 1, 2) : uint3(2, 1, 3));
    }
}