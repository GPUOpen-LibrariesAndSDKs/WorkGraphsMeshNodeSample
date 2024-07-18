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

// Rock generation is single-threaded, this we use a coalescing node to generate multiple rocks in parallel.
// Rocks are rendered with the same spline mesh node as the trees.
[Shader("node")]
[NodeLaunch("coalescing")]
[NumThreads(maxSplinesPerRecord, 1, 1)]
void GenerateRock(
    [MaxRecords(maxSplinesPerRecord)]
    GroupNodeInputRecords<GenerateTreeRecord> inputRecord,

    uint threadId : SV_GroupThreadID,

    [MaxRecords(1)]
    [NodeId("DrawSpline")]
    NodeOutput<DrawSplineRecord> output)
{
    GroupNodeOutputRecords<DrawSplineRecord> outputRecord = output.GetGroupNodeOutputRecords(1);

    outputRecord.Get().dispatchGrid = uint3(inputRecord.Count(), 1, 1);

    if (threadId < inputRecord.Count()) {
        const float2 basePositionXZ = inputRecord.Get(threadId).position;
        const uint   seed           = CombineSeed(asuint(basePositionXZ.x), asuint(basePositionXZ.y));

        const float3 basePosition   = GetTerrainPosition(basePositionXZ);
        const float3 terrainNormal  = GetTerrainNormal(basePositionXZ);
        const float3 basePositionUp = lerp(float3(0, 1, 0), terrainNormal, 1 + Random(seed, 456) * 0.5);

        const float rotationAngle = Random(seed, 14658) * 2 * PI;

        const float  upScale   = lerp(0.5, 1.2, Random(seed, 546));
        const float  a         = 1.05f + Random(seed, 6514);
        const float2 sideScale = lerp(0.6, 5.0, Random(seed, 9487)) * float2(a, 1);

        const float f = 1.05f + Random(seed, 1564);
        const float c = lerp(0.5, 0.9, Random(seed, 49827));

        outputRecord.Get(0).color[threadId]             = float3(0.1, 0.1, 0.1) * 3.5;
        outputRecord.Get(0).rotationOffset[threadId]    = rotationAngle;
        outputRecord.Get(0).windStrength[threadId]      = 0;
        outputRecord.Get(0).controlPointCount[threadId] = 4;

        int controlPointIndex = threadId * splineMaxControlPointCount;

        outputRecord.Get(0).controlPointPositions[controlPointIndex]       = basePosition - terrainNormal;
        outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = 1;
        outputRecord.Get(0).controlPointRadii[controlPointIndex]           = 0;
        outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
        controlPointIndex++;

        outputRecord.Get(0).controlPointPositions[controlPointIndex]       = basePosition;
        outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = round(lerp(5, 7, Random(seed, 4145)));
        outputRecord.Get(0).controlPointRadii[controlPointIndex]           = sideScale;
        outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.5 * upScale;
        controlPointIndex++;

        outputRecord.Get(0).controlPointPositions[controlPointIndex]       = basePosition + upScale * basePositionUp;
        outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = round(lerp(5, 7, Random(seed, 4578)));
        outputRecord.Get(0).controlPointRadii[controlPointIndex]           = c * sideScale;
        outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.5 * upScale;
        controlPointIndex++;

        outputRecord.Get(0).controlPointPositions[controlPointIndex]    = basePosition + f * upScale * basePositionUp;
        outputRecord.Get(0).controlPointVertexCounts[controlPointIndex] = 1;
        outputRecord.Get(0).controlPointRadii[controlPointIndex]        = Random(seed, 89514);
        outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0;
    }

    outputRecord.OutputComplete();
}