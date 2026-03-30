/// <reference path="types.ts" />

namespace HitNumber {
    /** Flash 侧 COLOR_TABLE 的镜像（HitNumberBatchProcessor.as:110） */
    export const COLOR_TABLE: string[] = [
        "#FFFFFF", "#FF0000", "#FFCC00", "#660033", "#4A0099",
        "#AC99FF", "#0099FF", "#7F0000", "#7F6A00", "#FF7F7F", "#FFE770"
    ];

    // 效果标志位常量（DamageResult.as bits 0-8）
    export const EF_CRUMBLE        = 1;
    export const EF_TOXIC          = 2;
    export const EF_EXECUTE        = 4;
    export const EF_DMG_TYPE_LABEL = 8;
    export const EF_CRUSH_LABEL    = 16;
    export const EF_LIFESTEAL      = 32;
    export const EF_IS_ENEMY       = 128;
    export const EF_SHIELD         = 256;

    // packed 编码（DamageResult.as:462-469）：
    //   bits 0-8:   efFlags (9 bits)
    //   bit  9:     isMISS
    //   bits 10-17: damageSize (0-255)
    //   bits 18-21: colorId (0-15)

    export function unpackFlags(packed: number): number { return packed & 511; }
    export function unpackIsMISS(packed: number): boolean { return ((packed >> 9) & 1) !== 0; }
    export function unpackSize(packed: number): number { return (packed >> 10) & 255; }
    export function unpackColorId(packed: number): number { return (packed >> 18) & 15; }

    /**
     * 协议字段反序列化。
     *
     * 当前取值域审计结果：efText/efEmoji 均不含分隔符，
     * AS2 侧 safeField 仅做 null→空串，不做转义。
     * 此函数保留接口签名，当前为直通。
     *
     * 若未来协议需要转义，在此处实现反转义即可，
     * 无需修改 AS2 热路径。
     */
    export function unescField(s: string): string {
        if (!s) return "";
        return s;
    }
}
