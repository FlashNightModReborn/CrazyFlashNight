#pragma once
#include <windows.h>
#include <cstdint>
constexpr wchar_t InputProperty[]=L"CF7.WorldPointer.Map.v1";
constexpr wchar_t InputMessage[]=L"CF7.WorldPointer.Packet.v1";
constexpr uint32_t InputMagic=0xCF710001;
struct InputShared {
    uint32_t magic, hostPid, sourcePid, reserved;
    uint64_t sourceWindow, ownerWindow;
    volatile LONG ready, stop, stopped, cursorReads, keyReads, patchMask;
};
static_assert(sizeof(void*)==8, "The paired projector is x64");
