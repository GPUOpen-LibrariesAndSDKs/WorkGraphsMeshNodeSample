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

#include "samplecameracomponent.h"

#include "core/contentmanager.h"
#include "core/framework.h"
#include "core/inputmanager.h"
#include "core/scene.h"

MeshNodeSampleCameraComponent::MeshNodeSampleCameraComponent(cauldron::Entity* pOwner, cauldron::ComponentData* pData, cauldron::CameraComponentMgr* pManager)
    : CameraComponent(pOwner, pData, pManager)
{
    m_Speed       = 50.f;
    m_ArcBallMode = false;
}

void MeshNodeSampleCameraComponent::Update(double deltaTime)
{
    using namespace cauldron;

    // Always update temporal information
    m_PrevViewMatrix           = m_ViewMatrix;
    m_PrevViewProjectionMatrix = m_ViewProjectionMatrix;
    m_PrevProjJittered         = m_ProjJittered;

    // If this camera is the currently active camera for the scene, check for input
    if (GetScene()->GetCurrentCamera() == this)
    {
        const InputState& inputState = GetInputManager()->GetInputState();

        // Read in inputs

        // Scale speed with mouse wheel rotation
        if (inputState.GetMouseAxisDelta(Mouse_Wheel))
        {
            m_Speed = m_Speed * ((inputState.GetMouseAxisDelta(Mouse_Wheel) > 0) ? 1.5f : (1.f / 1.5f));
            // clamp speed
            m_Speed = std::max(m_Speed, 1.f);
            m_Speed = std::min(m_Speed, 200.f);
        }

        // Use right game pad stick to pitch and yaw the camera
        bool hasRotation = false;
        if (inputState.GetGamePadAxisState(Pad_RightThumbX) || inputState.GetGamePadAxisState(Pad_RightThumbY))
        {
            // All rotations (per frame) are of 0.005 radians
            m_Yaw -= inputState.GetGamePadAxisState(Pad_RightThumbX) / 200.f;
            m_Pitch += inputState.GetGamePadAxisState(Pad_RightThumbY) / 200.f;
            hasRotation = true;
        }

        // Left click + mouse move == free cam look & WASDEQ movement (+ mouse wheel in/out)
        else if (inputState.GetMouseButtonState(Mouse_LButton))
        {
            // All rotations (per frame) are of 0.002 radians
            m_Yaw -= inputState.GetMouseAxisDelta(Mouse_XAxis) / 500.f;
            m_Pitch += inputState.GetMouseAxisDelta(Mouse_YAxis) / 500.f;
            hasRotation = true;
        }

        // If hitting the 'r' key or back button on game pad, reset camera to original transform
        if (inputState.GetKeyState(Key_R) || inputState.GetGamePadButtonState(Pad_Back))
        {
            ResetCamera();
            UpdateMatrices();
            return;
        }

        Vec4 eyePos      = Vec4(m_InvViewMatrix.getTranslation(), 0.f);
        Vec4 polarVector = PolarToVector(m_Yaw, m_Pitch);

        // WASDQE == camera translation
        float x(0.f), y(0.f), z(0.f);
        x -= (inputState.GetKeyState(Key_A)) ? 1.f : 0.f;
        x += (inputState.GetKeyState(Key_D)) ? 1.f : 0.f;
        y -= (inputState.GetKeyState(Key_Q)) ? 1.f : 0.f;
        y += (inputState.GetKeyState(Key_E)) ? 1.f : 0.f;
        z -= (inputState.GetKeyState(Key_W)) ? 1.f : 0.f;
        z += (inputState.GetKeyState(Key_S)) ? 1.f : 0.f;

        // Controller input can also translate
        x += inputState.GetGamePadAxisState(Pad_LeftThumbX);
        z -= inputState.GetGamePadAxisState(Pad_LeftThumbY);
        y -= inputState.GetGamePadAxisState(Pad_LTrigger);
        y += inputState.GetGamePadAxisState(Pad_RTrigger);
        Vec4 movement = Vec4(x, y, z, 0.f);

        Mat4& transform = m_pOwner->GetTransform();

        // Update from inputs
        if (hasRotation || dot(movement.getXYZ(), movement.getXYZ()))
        {
            // Setup new eye position
            eyePos =
                m_InvViewMatrix.getCol3() + (m_InvViewMatrix * movement * m_Speed * static_cast<float>(deltaTime));  // InvViewMatrix is the owner's transform
        }

        // Limit maximum camera height
        eyePos[1] = std::min<float>(eyePos[1], 400.f);

        // Update camera jitter if we need it
        if (CameraComponent::s_pSetJitterCallback)
        {
            s_pSetJitterCallback(m_jitterValues);
            m_Dirty = true;
        }
        else
        {
            // Reset jitter if disabled
            if (m_jitterValues.getX() != 0.f || m_jitterValues.getY() != 0.f)
            {
                m_jitterValues = Vec2(0.f, 0.f);
                m_Dirty        = true;
            }
        }

        LookAt(eyePos, eyePos - 10 * polarVector);
        UpdateMatrices();
    }
}

void InitCameraEntity(void*)
{
    using namespace cauldron;

    ContentBlock* pContentBlock = new ContentBlock();

    // Memory backing camera creation
    EntityDataBlock* pCameraDataBlock = new EntityDataBlock();
    pContentBlock->EntityDataBlocks.push_back(pCameraDataBlock);
    pCameraDataBlock->pEntity = new Entity(L"MeshNodeDemoCamera");
    CauldronAssert(ASSERT_CRITICAL, pCameraDataBlock->pEntity, L"Could not allocate default perspective camera entity");

    // Use the same matrix setup as Cauldron 1.4 (note that Cauldron kept view-matrix native transforms, and our
    // entity needs the inverse of that)
    Mat4 transform = LookAtMatrix(Vec4(120.65f, 24.44f, -15.74f, 0.f),  // eye position
                                  Vec4(120.45f, 24.44f, -14.74f, 0.f),  // look-at position
                                  Vec4(0.f, 1.f, 0.f, 0.f));            // up
    transform      = InverseMatrix(transform);
    pCameraDataBlock->pEntity->SetTransform(transform);

    // Setup default camera parameters
    CameraComponentData defaultPerspCameraCompData;
    defaultPerspCameraCompData.Name                    = L"MeshNodeDemoCamera";
    defaultPerspCameraCompData.Perspective.AspectRatio = GetFramework()->GetAspectRatio();
    defaultPerspCameraCompData.Perspective.Yfov        = CAULDRON_PI2 / defaultPerspCameraCompData.Perspective.AspectRatio;
    defaultPerspCameraCompData.Znear                   = 0.5f;
    defaultPerspCameraCompData.Zfar                    = 2000.f;

    CameraComponentData* pCameraComponentData = new CameraComponentData(defaultPerspCameraCompData);
    pCameraDataBlock->ComponentsData.push_back(pCameraComponentData);
    MeshNodeSampleCameraComponent* pCameraComponent =
        new MeshNodeSampleCameraComponent(pCameraDataBlock->pEntity, pCameraComponentData, CameraComponentMgr::Get());
    pCameraDataBlock->pEntity->AddComponent(pCameraComponent);

    pCameraDataBlock->Components.push_back(pCameraComponent);

    pContentBlock->ActiveCamera = pCameraDataBlock->pEntity;

    GetContentManager()->StartManagingContent(L"MeshNodeDemoCameraEntities", pContentBlock, false);
}
