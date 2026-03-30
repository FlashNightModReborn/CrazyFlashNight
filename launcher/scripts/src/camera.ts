/// <reference path="types.ts" />

namespace HitNumber {
    /** Flash 舞台固定尺寸（FlashCoordinateMapper 构造参数确认） */
    export const STAGE_W = 1024;
    export const STAGE_H = 576;

    export const camera: CameraSnapshot = {
        gx: 0, gy: 0, sx: 1
    };

    /**
     * 由 C# FrameTask 调用，传入管道分隔字符串
     * 格式: "gx|gy|sx"（3 段）
     */
    export function updateCameraRaw(raw: string): void {
        const parts = raw.split("|");
        camera.gx = +parts[0];
        camera.gy = +parts[1];
        camera.sx = +parts[2];
    }
}
