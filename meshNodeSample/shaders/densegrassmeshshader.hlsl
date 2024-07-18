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

float3 bezier(float3 v0, float3 v1, float3 v2, float t)
{
    float3 a = lerp(v0, v1, t);
    float3 b = lerp(v1, v2, t);
    return lerp(a, b, t);
}

float3 bezierDerivative(float3 v0, float3 v1, float3 v2, float t)
{
    return 2. * (1. - t) * (v1 - v0) + 2. * t * (v2 - v1);
}

// The following function (MakePersistentLength) is taken from
// https://github.com/klejah/ResponsiveGrassDemo/blob/6ce514717467acc80fd965a6f7695d5151ba8c03/ResponsiveGrassDemo/shader/Grass/GrassUpdateForcesShader.cs#L67
// Licensed under BSD 3-Clause:
//
// Copyright (c) 2016, klejah
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// 
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// 
// * Neither the name of the copyright holder nor the names of its
//   contributors may be used to endorse or promote products derived from
//   this software without specific prior written permission.
void MakePersistentLength(in float3 v0, inout float3 v1, inout float3 v2, in float height)
{
    // Persistent length
    float3 v01  = v1 - v0;
    float3 v12  = v2 - v1;
    float  lv01 = length(v01);
    float  lv12 = length(v12);

    float L1 = lv01 + lv12;
    float L0 = length(v2 - v0);
    float L  = (2.0f * L0 + L1) / 3.0f;  // http://steve.hollasch.net/cgindex/curves/cbezarclen.html

    float ldiff = height / L;
    v01         = v01 * ldiff;
    v12         = v12 * ldiff;
    v1          = v0 + v01;
    v2          = v1 + v12;
}

static const int denseGrassGroupSize     = 128;
static const int maxNumOutputVerticesLimit  = 256;
static const int maxNumOutputTrianglesLimit = 192;
static const int numOutputVerticesLimit  = 128;
static const int numOutputTrianglesLimit = 96;

// 4 vertices per edge; 2 edges per blade
static const int numGrassBladeVerticesPerEdge = 4;
static const int numGrassBladeVertices        = 2 * numGrassBladeVerticesPerEdge;
static const int numGrassBladeTriangles       = 6;
static const int maxNumGrassBlades =
    min(32,
        min(maxNumOutputVerticesLimit / numGrassBladeVertices, maxNumOutputTrianglesLimit / numGrassBladeTriangles));
static const int maxNumOutputGrassBlades =
    min(32, min(numOutputVerticesLimit / numGrassBladeVertices, numOutputTrianglesLimit / numGrassBladeTriangles));
static const int numOutputVertices  = maxNumOutputGrassBlades * numGrassBladeVertices;
static const int numOutputTriangles = maxNumOutputGrassBlades * numGrassBladeTriangles;

static const int numOutputVertexIterations   = (numOutputVertices + (denseGrassGroupSize - 1)) / denseGrassGroupSize;
static const int numOutputTriangleIterations = (numOutputTriangles + (denseGrassGroupSize - 1)) / denseGrassGroupSize;

[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawDenseGrassPatch", 0)]
[NodeMaxDispatchGrid(maxDenseGrassPatchesPerRecord, 1, 1)]
// This limit was set through instrumentation and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(400, true)]
[NumThreads(denseGrassGroupSize, 1, 1)]
[OutputTopology("triangle")]
void DenseGrassMeshShader(
    uint                                          gtid : SV_GroupThreadID,
    uint                                          gid : SV_GroupID,
    DispatchNodeInputRecord<DrawDenseGrassRecord> inputRecord,
    out indices uint3                             tris[numOutputTriangles],
    out vertices GrassVertex                      verts[numOutputVertices])
{
    const float3 patchCenter       = inputRecord.Get().position[gid];
    const float  patchHeight       = inputRecord.Get().height[gid];
    const uint   bladeOffset       = inputRecord.Get().bladeOffset[gid];
    const float  patchWindStrength = GetWindStrength();
    const float3 patchNormal       = GetTerrainNormal(patchCenter.xz);
    const int seed = CombineSeed(asuint(int(patchCenter.x / grassSpacing)), asuint(int(patchCenter.z / grassSpacing)));

    const float dist        = distance(patchCenter, GetCameraPosition());
    const float bladeCountF =
        lerp(float(maxNumGrassBlades), 2., pow(saturate(dist / (denseGrassMaxDistance * 1.05)), 0.75));

    const int tileBladeCount         = ceil(bladeCountF);
    const int threadGroupBladeOffset = bladeOffset * maxNumOutputGrassBlades;
    const int threadGroupBladeCount  = clamp(tileBladeCount - threadGroupBladeOffset, 0, maxNumOutputGrassBlades);

    const int vertexCount   = threadGroupBladeCount * numGrassBladeVertices;
    const int triangleCount = threadGroupBladeCount * numGrassBladeTriangles;

    SetMeshOutputCounts(vertexCount, triangleCount);

    const int vertId = gtid;
    if (vertId < vertexCount) {
        const int bladeId     = (vertId / numGrassBladeVertices) + threadGroupBladeOffset;
        const int vertIdLocal = vertId % numGrassBladeVertices;
           
        const float height = patchHeight + float(Random(seed, bladeId, 20)) / 40.;
        
        // Position the grass in a circle around the hitPosition and angled using the hitNormal
        float3 tangent   = normalize(cross(float3(0, 0, 1), patchNormal));
        float3 bitangent = normalize(cross(patchNormal, tangent));

        float  bladeDirectionAngle = 2. * PI * Random(seed, 4, bladeId);
        float2 bladeDirection      = float2(cos(bladeDirectionAngle), sin(bladeDirectionAngle)) * height * 0.3;

        float  offsetAngle  = 2. * PI * Random(seed, bladeId);
        float  offsetRadius = grassSpacing * sqrt(Random(seed, 19, bladeId));
        float3 bladeOffset  = offsetRadius * (cos(offsetAngle) * tangent + sin(offsetAngle) * bitangent);

        float3 v0 = patchCenter + bladeOffset;
        float3 v1 = v0 + float3(0, height, 0);
        float3 v2 = v1 + float3(bladeDirection.x, 0, bladeDirection.y);

        float3 v1prev = v1;
        float3 v2prev = v2 + patchWindStrength * GetWindOffset(v0.xz, GetPreviousTime());

        v2 += patchWindStrength * GetWindOffset(v0.xz, GetTime());

        MakePersistentLength(v0, v1, v2, height);
        MakePersistentLength(v0, v1prev, v2prev, height);
        
        float width = 0.03;
        
        width *= maxNumGrassBlades / bladeCountF;
        
        if (bladeId == (tileBladeCount - 1)) {
            width *= frac(bladeCountF);
        }
        
        GrassVertex vertex;
        vertex.height                 = patchHeight;
        vertex.worldSpaceGroundNormal = patchNormal;
        vertex.rootHeight             = v0.y;

        const float3 sideVec = normalize(float3(bladeDirection.y, 0, -bladeDirection.x));
        const float3 offset  = BitSign(vertIdLocal, 0) * width * sideVec;

        v0 += offset * 1.0;
        v1 += offset * 0.7;
        v2 += offset * 0.3;

        v1prev += offset * 0.7;
        v2prev += offset * 0.3;

        float t                   = (vertIdLocal / 2) / float(numGrassBladeVerticesPerEdge - 1);
        vertex.worldSpacePosition = bezier(v0, v1, v2, t);
        vertex.worldSpaceNormal   = cross(sideVec, normalize(bezierDerivative(v0, v1, v2, t)));

        ComputeClipSpacePositionAndMotion(vertex, vertex.worldSpacePosition, bezier(v0, v1prev, v2prev, t));

        verts[vertId] = vertex;
    }

    const int triId = gtid;
    if (triId < triangleCount) {
        const int bladeId    = triId / numGrassBladeTriangles;
        const int triIdLocal = triId % numGrassBladeTriangles;
        
        const int offset = bladeId * numGrassBladeVertices + 2 * (triIdLocal / 2);

        tris[triId] = offset + (((triIdLocal & 1) == 0) ? uint3(0, 1, 2) : uint3(3, 2, 1));
    }
}