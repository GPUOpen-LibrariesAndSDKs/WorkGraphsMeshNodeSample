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

// Static "vertex buffer" for butterflies
static const int numButterflyVertices = 16;
static const float3 butterflyPositions[numButterflyVertices] = {
    float3(-0.548, 0.0, -0.0),
    float3(-0.41, 0.0, 0.226),
    float3(-0.41, -0.0, -0.226),
    float3(-0.948, 0.239, 0.528),
    float3(-1.048, 0.238, 0.468),
    float3(-0.948, 0.239, -0.528),
    float3(-1.048, 0.238, -0.468),
    float3(0.747, 0.0, 0.125),
    float3(0.747, -0.0, -0.125),
    float3(-0.194, 0.139, -0.0),
    float3(0.384, -0.046, -0.0),
    float3(-0.297, 0.092, -0.0),
    float3(-0.651, 0.324, 2.446),
    float3(1.621, -0.0, 0.785),
    float3(-0.651, 0.324, -2.446),
    float3(1.621, -0.0, -0.785),
};
// Static vertex color attributes
static const float3 butterflyColors[numButterflyVertices] = {
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0., 0., 0.),
    float3(0.2, 0.2, .7),
    float3(0.2, 0.2, .7),
    float3(0.2, 0.2, .7),
    float3(0.2, 0.2, .7)
};

// Static "index buffer" for butterflies
static const int numButterflyTriangles = 14;
static const uint3 butterflyTriangles[numButterflyTriangles] = {
    uint3(1, 10, 0),
    uint3(3, 4, 0),
    uint3(5, 0, 6),
    uint3(10, 2, 0),
    uint3(7, 1, 9),
    uint3(1, 0, 9),
    uint3(2, 9, 0),
    uint3(2, 8, 9),
    uint3(7, 9, 8),
    uint3(7, 10, 1),
    uint3(7, 8, 10),
    uint3(2, 10, 8),
    uint3(12, 13, 11),
    uint3(11, 14, 15),
};

float3 GetInsectPosition(float time)
{
    return 4 * float3(PerlinNoise2D(float2(time * 0.001, 0)),
                      PerlinNoise2D(float2(time * 0.001, 5)),
                      PerlinNoise2D(float2(time * 0.001, 9)));
}

static const int butterflyGroupSize = 128;

// customizable butterfly limit
static const int maxNumButterflies  = min(32, min(256 / numButterflyVertices, 192 / numButterflyTriangles));
static const int numOutputVertices  = maxNumButterflies * numButterflyVertices;
static const int numOutputTriangles = maxNumButterflies * numButterflyTriangles;

static const int numOutputVertexIterations   = (numOutputVertices + (butterflyGroupSize - 1)) / butterflyGroupSize;
static const int numOutputTriangleIterations = (numOutputTriangles + (butterflyGroupSize - 1)) / butterflyGroupSize;

[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawButterflies", 0)]
[NodeMaxDispatchGrid(maxInsectsPerRecord, 1, 1)]
// This limit was set through instrumentation and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(10, true)]
[NumThreads(butterflyGroupSize, 1, 1)]
[OutputTopology("triangle")]
void ButterflyMeshShader(
    uint                                      gtid : SV_GroupThreadID,
    uint                                      gid : SV_GroupID,
    DispatchNodeInputRecord<DrawInsectRecord> inputRecord,
    out indices uint3                         tris[numOutputTriangles],
    out vertices InsectVertex                 verts[numOutputVertices])
{
    const int numButterflies = maxNumButterflies;
    const int vertexCount    = numButterflies * numButterflyVertices;
    const int triangleCount  = numButterflies * numButterflyTriangles;

    SetMeshOutputCounts(vertexCount, triangleCount);

    const float3 patchCenter = inputRecord.Get().position[gid];
    const int    seed        = CombineSeed(asuint(patchCenter.x), asuint(patchCenter.z));
    
    [[unroll]]
    for (int i = 0; i < numOutputTriangleIterations; ++i)
    {
        const int triId = gtid + butterflyGroupSize * i;

        if (triId < triangleCount) {
            const int insectId         = triId / numButterflyTriangles;
            const int insectTriangleId = triId % numButterflyTriangles;

            tris[triId] = butterflyTriangles[insectTriangleId] + insectId * numButterflyVertices;
        }
    } 

    [[unroll]]
    for (int i = 0; i < numOutputVertexIterations; ++i)
    {
        const int vertId = gtid + butterflyGroupSize * i;

        if (vertId < vertexCount) {
            const int insectId       = vertId / numButterflyVertices;
            const int insectVertexId = vertId % numButterflyVertices;

            // start time before night start
            const float nightStart = nightStartTime - Random(seed, 4561);
            // end time after night end
            const float nightEnd   = nightEndTime + Random(seed, 6456);

            // scale insects to 0 at night
            const float nightScale    = max(smoothstep(nightStart - 1, nightStart, GetTimeOfDay()),
                                         1 - smoothstep(nightEnd, nightEnd + 1, GetTimeOfDay()));
            // slowly scale insects to 0 in the distance
            // for simplicity, we omit this scaling from the motion vector, as it only affects very distant insects
            const float distanceScale = smoothstep(
                butterflyFadeStartDistance, butterflyMaxDistance, distance(patchCenter, GetCameraPosition()));

            const float scale = (.01 + 0.03 * Random(seed, insectId, 8)) * (1 - nightScale) * (1 - distanceScale);

            // radius scale for positioning insects
            static const float R      = 2;
            const float        angle  = 2 * PI * Random(seed, insectId, 8);
            const float        radius = sqrt(R * Random(seed, insectId, 98));

            // compute random position offset for insect
            // insects will rotate around this position
            const float3 insectBasePosition =
                float3(radius * cos(angle), 0.75 + 0.5 * Random(seed, insectId, 988), radius * sin(angle));

            const float timeOffset = 1e6 * Random(seed, insectId, 55);
            const float time       = GetTime() + timeOffset;
            const float timePrev   = GetPreviousTime() + timeOffset;

            // compute local insect position offsets
            const float3 insectPositionOffset          = GetInsectPosition(time * .25);
            const float3 insectPositionOffsetDelta     = GetInsectPosition((time - 10) * .25);
            const float3 prevInsectPositionOffset      = GetInsectPosition(timePrev * .25);
            const float3 prevInsectPositionOffsetDelta = GetInsectPosition((timePrev - 10) * .25);

            const float3 insectPosition     = insectBasePosition + insectPositionOffset;
            const float3 prevInsectPosition = insectBasePosition + prevInsectPositionOffset;

            // compute forward vectors for rotating insects to face movement direction
            const float2 forward     = -normalize(insectPositionOffset.xz - insectPositionOffsetDelta.xz);
            const float2 prevForward = -normalize(prevInsectPositionOffset.xz - prevInsectPositionOffsetDelta.xz);

            float3 vertexPosition     = butterflyPositions[insectVertexId] * scale;
            float3 prevVertexPosition = vertexPosition;

            // rotate wing vertices around insect center
            if (insectVertexId >= 12) {
                // compute wing animation angle
                static const float wingDownAngle = -0.15;
                static const float wingAmplitude = 0.6;
                const float        phase         = wingDownAngle + wingAmplitude * cos(2 * PI * frac(time * 0.005));
                const float        phasePrev     = wingDownAngle + wingAmplitude * cos(2 * PI * frac(timePrev * 0.005));

                // insect center for rotating wings
                static const float3 rotatePoint = float3(0.353, 0.6, 0.0) * scale;

                float wingAngle       = sign(vertexPosition.z) * phase;
                float prevWingAngle   = sign(vertexPosition.z) * phasePrev;
                vertexPosition.yz     = RotateAroundPoint2d(vertexPosition.yz, wingAngle, rotatePoint.yz);
                prevVertexPosition.yz = RotateAroundPoint2d(prevVertexPosition.yz, prevWingAngle, rotatePoint.yz);
            }
            // rotate insect towards movement direction
            vertexPosition.xz     = float2(vertexPosition.x * forward.x - vertexPosition.z * forward.y,
                                           vertexPosition.x * forward.y + vertexPosition.z * forward.x);
            prevVertexPosition.xz = float2(prevVertexPosition.x * prevForward.x - prevVertexPosition.z * prevForward.y,
                                           prevVertexPosition.x * prevForward.y + prevVertexPosition.z * prevForward.x);

            InsectVertex vertex;
            vertex.objectSpacePosition = insectPosition + vertexPosition;

            if (insectVertexId >= 12) {
                // compute random wing color
                vertex.color = 0.95 * normalize(float3(Random(insectId, seed, 'r'),  //
                                                       Random(insectId, seed, 'g'),  //
                                                       Random(insectId, seed, 'b')));
            } else {
                vertex.color = butterflyColors[insectVertexId];
            }

            ComputeClipSpacePositionAndMotion(vertex,
                                              patchCenter + vertex.objectSpacePosition,
                                              patchCenter + prevInsectPosition + prevVertexPosition);

            verts[vertId] = vertex;
        }
    }
}