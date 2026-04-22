var MapPanelData = (function() {
    'use strict';

    var _pageOrder = ['base', 'faction', 'defense', 'school'];
    var _pageAliases = {
        base_floor_1: 'base',
        base: 'base',
        faction: 'faction',
        defense: 'defense',
        school: 'school'
    };
    var _sourceRefs = {
        xflDir: 'flashswf/UI/地图界面',
        domDocument: 'flashswf/UI/地图界面/DOMDocument.xml',
        ffdecCli: 'tools/ffdec/ffdec-cli.exe'
    };

    var _unlockGroups = {
        warlord: { id: 'warlord', conditionId: 'unlock.warlord', label: '军阀线路', lockedReason: '军阀线路尚未开放' },
        rock: { id: 'rock', conditionId: 'unlock.rock', label: '摇滚线路', lockedReason: '摇滚线路尚未开放' },
        blackiron: { id: 'blackiron', conditionId: 'unlock.blackiron', label: '黑铁会线路', lockedReason: '黑铁会线路尚未开放' },
        fallen: { id: 'fallen', conditionId: 'unlock.fallen', label: '堕落城线路', lockedReason: '堕落城线路尚未开放' },
        defense: { id: 'defense', conditionId: 'unlock.defense', label: '第一防线', lockedReason: '第一防线尚未开放' },
        restricted: { id: 'restricted', conditionId: 'unlock.restricted', label: '禁区', lockedReason: '禁区尚未开放' },
        schoolOutside: { id: 'schoolOutside', conditionId: 'unlock.schoolOutside', label: '学校外部', lockedReason: '学校外部尚未开放' },
        schoolInside: { id: 'schoolInside', conditionId: 'unlock.schoolInside', label: '学校内部', lockedReason: '学校内部尚未开放' }
    };
    var _pageUnlockGroups = {
        faction: {
            filters: {
                warlord: 'warlord',
                rock: 'rock',
                blackiron: 'blackiron',
                fallen: 'fallen'
            },
            hotspots: {
                warlord_base: 'warlord',
                warlord_tent: 'warlord',
                firing_range: 'warlord',
                rock_park: 'rock',
                rock_rehearsal: 'rock',
                blackiron_training: 'blackiron',
                blackiron_pavilion: 'blackiron',
                fallen_bar: 'fallen',
                fallen_street: 'fallen'
            }
        },
        defense: {
            filters: {
                first_line: 'defense',
                restricted: 'restricted'
            },
            hotspots: {
                first_defense: 'defense',
                alliance_dock: 'restricted',
                alliance_corridor: 'restricted'
            }
        },
        school: {
            filters: {
                inside: 'schoolInside',
                outside: 'schoolOutside'
            },
            hotspots: {
                workshop: 'schoolInside',
                university_interior: 'schoolInside',
                university_playground: 'schoolInside',
                dorm_downstairs: 'schoolInside',
                school_dormitory: 'schoolInside',
                office: 'schoolInside',
                kendo_club: 'schoolInside',
                science_class: 'schoolInside',
                arts_class: 'schoolInside',
                teaching_interior: 'schoolInside',
                teaching_right: 'schoolInside',
                union_university: 'schoolOutside'
            }
        }
    };
    var _handTunedLayoutIds = {
        base_roof: true,
        base_lobby: true,
        base_entrance: true,
        base_garage: true,
        merc_bar: true,
        infirmary: true,
        dormitory: true,
        basement1: true,
        gym: true,
        armory: true,
        cafeteria: true,
        corridor: true,
        lab: true,
        underground_water: true,
        warlord_base: true,
        warlord_tent: true,
        firing_range: true,
        alliance_dock: true,
        alliance_corridor: true
    };
    var _xflSourceRects = {
        base: {
            base_roof: { x: 211.6, y: 95.25, w: 2341.3, h: 478.2 },
            base_lobby: { x: 223.35, y: 146.7, w: 4245.2, h: 898.2 },
            base_entrance: { x: 622.65, y: 151.3, w: 2682.5, h: 959.3 },
            base_garage: { x: 33.3, y: 134.25, w: 2418.2, h: 1108.4 },
            merc_bar: { x: 295.1, y: 65.9, w: 1387.2, h: 681.3 },
            infirmary: { x: 496.55, y: 95.2, w: 1163.3, h: 821.5 },
            dormitory: { x: 475.85, y: 56.2, w: 123.3, h: 71.1 },
            basement1: { x: 337.55, y: 257.4, w: 2725.2, h: 803.2 },
            gym: { x: 221.25, y: 257.4, w: 1462.5, h: 797.9 },
            armory: { x: 459.65, y: 217.9, w: 1472.9, h: 796.2 },
            cafeteria: { x: 44.6, y: 314.05, w: 3224.9, h: 1126.7 },
            corridor: { x: 329, y: 348.55, w: 1465.1, h: 797.1 },
            lab: { x: 496.1, y: 339.7, w: 328.4, h: 188.6 },
            underground_water: { x: 328.25, y: 418.65, w: 1222.6, h: 728.2 }
        },
        faction: {
            warlord_base: { x: 46.35, y: 85.4, w: 745.8, h: 360.1 },
            warlord_tent: { x: 60.6, y: 33.15, w: 613.1, h: 330.1 },
            firing_range: { x: 40.75, y: 170.05, w: 773.6, h: 439.4 },
            rock_park: { x: 377.05, y: 55, w: 253.8, h: 115.1 },
            rock_rehearsal: { x: 390.3, y: 193.7, w: 219.9, h: 97.3 },
            blackiron_training: { x: 8.1, y: 352.95, w: 299.1, h: 100.1 },
            blackiron_pavilion: { x: 6.1, y: 418.4, w: 308.5, h: 123.6 },
            fallen_bar: { x: 360.65, y: 389.15, w: 222.6, h: 108.7 },
            fallen_street: { x: 597.9, y: 392.15, w: 182.7, h: 108.9 }
        },
        defense: {
            first_defense: { x: 60, y: 94.7, w: 255.1, h: 86.7 },
            alliance_dock: { x: 38.75, y: 260.4, w: 240.3, h: 98.8 },
            alliance_corridor: { x: 46.4, y: 299.1, w: 247.2, h: 172.6 }
        },
        school: {
            workshop: { x: 423.05, y: 259.2, w: 147.3, h: 73.6 },
            union_university: { x: 375.2, y: 443.2, w: 198.4, h: 86.5 },
            university_interior: { x: 364.15, y: 350.6, w: 238.2, h: 86.8 },
            university_playground: { x: 591.85, y: 378.3, w: 191.2, h: 58.8 },
            dorm_downstairs: { x: 195.75, y: 340.25, w: 185.9, h: 105.5 },
            school_dormitory: { x: 57.3, y: 276.35, w: 148.8, h: 85.9 },
            office: { x: 412.15, y: 47.6, w: 132.3, h: 66.8 },
            kendo_club: { x: 534.95, y: 160.5, w: 134.3, h: 68.4 },
            science_class: { x: 681.75, y: 164.45, w: 67.1, h: 45.4 },
            arts_class: { x: 748.85, y: 164.45, w: 67.1, h: 45.4 },
            teaching_interior: { x: 423.05, y: 201.75, w: 190, h: 63.2 },
            teaching_right: { x: 652.95, y: 200.1, w: 134.8, h: 67 }
        }
    };

    function buildStaticAvatarSlot(id, label, hotspotId, centerX, centerY, assetName, size) {
        var diameter = size || 44;
        return {
            id: id,
            label: label,
            hotspotId: hotspotId,
            x: +(centerX - (diameter / 2)).toFixed(2),
            y: +(centerY - (diameter / 2)).toFixed(2),
            w: diameter,
            h: diameter,
            assetUrl: 'assets/map/avatars/' + assetName
        };
    }

    function buildStaticAvatarSlots(defs) {
        var slots = [];
        for (var i = 0; i < defs.length; i++) {
            slots.push(buildStaticAvatarSlot(defs[i][0], defs[i][1], defs[i][2], defs[i][3], defs[i][4], defs[i][5], defs[i][6]));
        }
        return slots;
    }

    var _pageStaticAvatars = {
        base: buildStaticAvatarSlots([
            ['pig_avatar', 'Pig', 'base_garage', 171.55, 217.85, 'pig头像.png'],
            ['boy_avatar', 'Boy', 'base_garage', 212.95, 246.0, 'boy头像.png'],
            ['king_avatar', 'King', 'base_garage', 265.35, 217.85, 'king头像.png'],
            ['weapon_merchant_avatar', '冷兵器商人', 'base_garage', 120.5, 222.05, '冷兵器商人头像.png'],
            ['shamate_avatar', '杀马特', 'base_lobby', 365.95, 217.6, '∞天ㄙ★使的剪∞头像.png'],
            ['bartender_avatar', '酒保', 'merc_bar', 444.85, 136.15, '酒保头像.png'],
            ['wizard_avatar', '格格巫', 'infirmary', 567.05, 173.8, '格格巫头像.png'],
            ['lilith_avatar', '丽丽丝', 'infirmary', 621.55, 173.8, '丽丽丝头像.png'],
            ['dancer_avatar', '舞女', 'merc_bar', 389.55, 140.2, '舞女头像.png'],
            ['gem_contact_avatar', '宝石线人', 'base_lobby', 564.15, 249.75, '宝石线人头像.png'],
            ['sheriff_avatar', '前治安官', 'base_lobby', 625.5, 237.2, '前治安官头像.png'],
            ['diplomat_avatar', '黑铁会外交部长', 'base_lobby', 363.25, 264.75, '黑铁会外交部长头像.png'],
            ['schoolgirl_avatar', '学生妹', 'base_lobby', 414.1, 245.45, '学生妹头像.png'],
            ['veteran_avatar', '幸存老兵', 'base_lobby', 466.5, 259.35, '幸存老兵头像.png'],
            ['thegirl_avatar', 'The Girl', 'basement1', 436.25, 332.65, 'the girl头像.png'],
            ['andy_avatar', 'Andy Law', 'basement1', 497.55, 329.4, 'andy头像.png'],
            ['shopgirl_avatar', 'Shop Girl', 'armory', 549.95, 291.2, 'shopgirl头像.png'],
            ['blue_avatar', 'Blue', 'basement1', 620.9, 336.8, 'blue头像.png'],
            ['xiaof_avatar', '小F', 'armory', 609.15, 279.75, '小F头像.png'],
            ['chef_avatar', '厨师', 'cafeteria', 324.85, 431.85, '厨师头像.png']
        ]),
        faction: buildStaticAvatarSlots([
            ['general_avatar', 'general', 'warlord_base', 239.3, 170.6, 'general头像.png'],
            ['gazer_avatar', 'gazer', 'warlord_base', 128.95, 168.1, 'gazer头像.png'],
            ['director_avatar', 'director', 'warlord_tent', 190.85, 125.0, 'director头像.png'],
            ['itinerant_avatar', 'itinerant', 'firing_range', 154.35, 293.6, 'itinerant头像.png'],
            ['surveyor_avatar', 'surveyor', 'firing_range', 254.35, 264.1, 'surveyor头像.png'],
            ['singer_avatar', 'singer', 'rock_park', 540.55, 158.5, 'singer头像.png'],
            ['keyboard_avatar', 'keyboard', 'rock_park', 603.75, 187.7, 'keyboard头像.png'],
            ['guitar_avatar', 'guitar', 'rock_park', 476.95, 186.1, 'guitar头像.png'],
            ['firephoenix_avatar', '火凤', 'blackiron_training', 135.7, 425.45, '火凤头像.png'],
            ['wingtiger_avatar', '翅虎', 'blackiron_training', 230.95, 412.7, '翅虎头像.png'],
            ['blackdragon_avatar', '黑龙', 'blackiron_training', 277.5, 433.2, '黑龙头像.png'],
            ['blackiron_avatar', '黑铁', 'blackiron_pavilion', 186.9, 514.5, '黑铁头像.png'],
            ['cowboy_avatar', '牛仔', 'fallen_bar', 522.75, 471.7, '牛仔头像.png'],
            ['cyborg_sage_avatar', '假肢仙人', 'fallen_street', 753.55, 488.45, '假肢仙人头像.png'],
            ['hitler_avatar', '吸特乐', 'fallen_street', 675.8, 482.0, '吸特乐头像.png']
        ]),
        defense: buildStaticAvatarSlots([
            ['artist_avatar', 'artist', 'first_defense', 161.65, 155.15, 'artist头像.png'],
            ['soldier_avatar', 'soldier', 'first_defense', 250.7, 162.6, 'soldier头像.png'],
            ['paigu_avatar', '排骨', 'alliance_dock', 137.45, 332.3, '排骨头像.png'],
            ['jige_avatar', '机哥', 'alliance_dock', 189.45, 333.65, '机哥头像.png'],
            ['abo_avatar', '阿波', 'alliance_dock', 241.2, 331.65, '阿波头像.png'],
            ['prophet_avatar', 'PROPHET', 'alliance_corridor', 228.45, 392.45, 'PROPHET头像.png']
        ]),
        school: buildStaticAvatarSlots([
            ['heizi_avatar', '黑仔', 'union_university', 430.05, 508.2, '黑仔头像.png'],
            ['bat_avatar', 'Bat', 'union_university', 471.4, 529.7, 'Bat头像.png'],
            ['tomboy_avatar', 'Tomboy', 'union_university', 516.9, 513.2, 'Tomboy头像.png'],
            ['weapon_order_avatar', '武器订购系统', 'union_university', 570.4, 516.7, '武器订购系统头像.png'],
            ['pe_teacher_avatar', '体育老师', 'university_interior', 539.2, 428.65, '体育老师头像.png'],
            ['chengzheng_avatar', '程铮', 'teaching_interior', 486.65, 255.75, '程铮头像.png'],
            ['kendo_president_avatar', '剑道社长', 'kendo_club', 663.3, 213.1, '剑道社长头像.png'],
            ['fengyouquan_avatar', '冯佑权', 'kendo_club', 593.3, 211.9, '冯佑权头像.png'],
            ['science_prof_avatar', '理科教授', 'science_class', 744.65, 212.35, '理科教授头像.png'],
            ['arts_teacher_avatar', '文科老师', 'arts_class', 810.9, 213.1, '文科老师头像.png'],
            ['vanshuther_avatar', 'Vanshuther', 'workshop', 555.75, 327.2, 'Vanshuther头像.png'],
            ['dean_avatar', '教导主任', 'office', 538.9, 104.15, '教导主任头像.png']
        ])
    };

    var _pages = {
        base: {
            id: 'base',
            title: '基地',
            tabLabel: '基地',
            renderMode: 'assembled',
            backdropTheme: 'base',
            backgroundUrl: 'assets/map/page-base.png',
            width: 1031,
            height: 608,
            sceneVisuals: [
                { id: 'base_roof_visual', label: '基地屋顶', assetUrl: 'assets/map/composite/base/base-roof.png', rect: { x: 211.6, y: 95.25, w: 471.05, h: 179.25 }, filterIds: ['roof', 'all', 'hierarchy'], hotspotIds: ['base_roof'] },
                { id: 'merc_bar_visual', label: '佣兵酒吧', assetUrl: 'assets/map/composite/base/merc-bar.png', rect: { x: 295.1, y: 65.9, w: 216.25, h: 125.44 }, filterIds: ['first_floor', 'all', 'hierarchy'], hotspotIds: ['merc_bar'] },
                { id: 'infirmary_visual', label: '医务室', assetUrl: 'assets/map/composite/base/infirmary.png', rect: { x: 496.55, y: 95.2, w: 156.52, h: 123.5 }, filterIds: ['first_floor', 'all', 'hierarchy'], hotspotIds: ['infirmary'] },
                { id: 'dormitory_visual', label: '宿舍', assetUrl: 'assets/map/composite/base/dormitory.png', rect: { x: 475.85, y: 56.2, w: 133.93, h: 100.91 }, filterIds: ['first_floor', 'all', 'hierarchy'], hotspotIds: ['dormitory'] },
                { id: 'base_garage_visual', label: '基地车库', assetUrl: 'assets/map/composite/base/base-garage.png', rect: { x: 33.3, y: 134.25, w: 290, h: 156.87 }, filterIds: ['first_floor', 'all', 'hierarchy'], hotspotIds: ['base_garage'] },
                { id: 'base_lobby_visual', label: '基地大厅', assetUrl: 'assets/map/composite/base/base-lobby.png', rect: { x: 223.35, y: 146.7, w: 441.94, h: 142.76 }, filterIds: ['first_floor', 'all', 'hierarchy'], hotspotIds: ['base_lobby'] },
                { id: 'base_entrance_visual', label: '基地门口', assetUrl: 'assets/map/composite/base/base-entrance.png', rect: { x: 622.65, y: 151.3, w: 289.54, h: 137.49 }, filterIds: ['first_floor', 'all', 'hierarchy'], hotspotIds: ['base_entrance'] },
                { id: 'basement1_visual', label: '地下一层', assetUrl: 'assets/map/composite/base/basement1.png', rect: { x: 337.55, y: 257.4, w: 333.2, h: 121.98 }, filterIds: ['basement1', 'all', 'hierarchy'], hotspotIds: ['basement1'] },
                { id: 'gym_visual', label: '健身房', assetUrl: 'assets/map/composite/base/gym.png', rect: { x: 221.25, y: 257.4, w: 199.87, h: 120.98 }, filterIds: ['basement1', 'all', 'hierarchy'], hotspotIds: ['gym'] },
                { id: 'armory_visual', label: '武器库', assetUrl: 'assets/map/composite/base/armory.png', rect: { x: 459.65, y: 217.9, w: 198.61, h: 120.98 }, filterIds: ['basement1', 'all', 'hierarchy'], hotspotIds: ['armory'] },
                { id: 'cafeteria_visual', label: '食堂', assetUrl: 'assets/map/composite/base/cafeteria.png', rect: { x: 44.6, y: 314.05, w: 399.62, h: 159.39 }, filterIds: ['basement2', 'all', 'hierarchy'], hotspotIds: ['cafeteria'] },
                { id: 'corridor_visual', label: '走廊', assetUrl: 'assets/map/composite/base/corridor.png', rect: { x: 329, y: 348.55, w: 197.46, h: 121.66 }, filterIds: ['basement2', 'all', 'hierarchy'], hotspotIds: ['corridor'] },
                { id: 'lab_visual', label: '实验室', assetUrl: 'assets/map/composite/base/lab.png', rect: { x: 496.1, y: 317.35, w: 219.99, h: 153.01 }, filterIds: ['basement2', 'all', 'hierarchy'], hotspotIds: ['lab'] },
                { id: 'underground_water_visual', label: '地下水', assetUrl: 'assets/map/composite/base/underground-water.png', rect: { x: 328.25, y: 418.65, w: 170.17, h: 113.41 }, filterIds: ['water', 'all', 'hierarchy'], hotspotIds: ['underground_water'] }
            ],
            staticAvatars: _pageStaticAvatars.base,
            filters: [
                { id: 'roof', label: '基地屋顶', hotspotIds: ['base_roof'], buttonRect: { x: 895, y: 108, w: 132, h: 42 } },
                { id: 'first_floor', label: '基地一层', hotspotIds: ['base_lobby', 'base_entrance', 'base_garage', 'merc_bar', 'infirmary', 'dormitory'], buttonRect: { x: 894, y: 151, w: 132, h: 42 } },
                { id: 'basement1', label: '地下一层', hotspotIds: ['basement1', 'gym', 'armory'], buttonRect: { x: 893, y: 194, w: 132, h: 42 } },
                { id: 'basement2', label: '地下二层', hotspotIds: ['lab', 'corridor', 'cafeteria'], buttonRect: { x: 893, y: 238, w: 132, h: 42 } },
                { id: 'water', label: '地下水', hotspotIds: ['underground_water'], buttonRect: { x: 894, y: 281, w: 132, h: 42 } },
                { id: 'all', label: '初始化', hotspotIds: ['base_roof', 'base_lobby', 'base_entrance', 'base_garage', 'merc_bar', 'infirmary', 'dormitory', 'basement1', 'gym', 'armory', 'lab', 'corridor', 'cafeteria', 'underground_water'], buttonRect: { x: 894, y: 341, w: 132, h: 42 } },
                { id: 'hierarchy', label: '层级关系', hotspotIds: ['base_roof', 'base_lobby', 'base_entrance', 'base_garage', 'merc_bar', 'infirmary', 'dormitory', 'basement1', 'gym', 'armory', 'lab', 'corridor', 'cafeteria', 'underground_water'], buttonRect: { x: 894, y: 384, w: 132, h: 42 } }
            ],
            defaultFilterId: 'all',
            hotspots: [
                { id: 'base_roof', label: '基地屋顶', sceneName: '基地房顶', rect: { x: 285, y: 56, w: 392, h: 118 } },
                { id: 'base_lobby', label: '基地大厅', sceneName: '基地1层', rect: { x: 281, y: 142, w: 552, h: 118 } },
                { id: 'base_entrance', label: '基地门口', sceneName: '基地门口', rect: { x: 622, y: 145, w: 224, h: 111 } },
                { id: 'base_garage', label: '基地车库', sceneName: '基地车库', rect: { x: 40, y: 140, w: 240, h: 118 } },
                { id: 'merc_bar', label: '佣兵酒吧', sceneName: '佣兵酒吧', rect: { x: 334, y: 54, w: 280, h: 132 } },
                { id: 'infirmary', label: '医务室', sceneName: '医务室', rect: { x: 487, y: 80, w: 150, h: 84 } },
                { id: 'dormitory', label: '宿舍', sceneName: '房间', rect: { x: 515, y: 64, w: 168, h: 70 } },
                { id: 'basement1', label: '地下一层', sceneName: '地下室1层', rect: { x: 203, y: 256, w: 438, h: 88 } },
                { id: 'gym', label: '健身房', sceneName: '健身房', rect: { x: 214, y: 258, w: 130, h: 82 } },
                { id: 'armory', label: '武器库', sceneName: '武器库', rect: { x: 462, y: 258, w: 171, h: 84 } },
                { id: 'cafeteria', label: '食堂', sceneName: '地图-食堂', rect: { x: 39, y: 346, w: 348, h: 98 } },
                { id: 'corridor', label: '走廊', sceneName: '地图-走廊', rect: { x: 366, y: 346, w: 132, h: 98 } },
                { id: 'lab', label: '实验室', sceneName: '地图-实验室', rect: { x: 486, y: 344, w: 154, h: 98 } },
                { id: 'underground_water', label: '地下水', sceneName: '地下2层', rect: { x: 330, y: 438, w: 128, h: 70 } }
            ]
        },
        faction: {
            id: 'faction',
            title: 'A兵团',
            tabLabel: 'A兵团',
            renderMode: 'assembled',
            backdropTheme: 'faction',
            backgroundUrl: 'assets/map/page-faction.png',
            width: 1031,
            height: 608,
            sceneVisuals: [
                { id: 'warlord_base_visual', label: '军阀基地', assetUrl: 'assets/map/composite/faction/warlord-base.png', rect: { x: 46.35, y: 85.4, w: 240.25, h: 125.08 }, filterIds: ['warlord', 'all'], hotspotIds: ['warlord_base'] },
                { id: 'warlord_tent_visual', label: '军阀帐篷', assetUrl: 'assets/map/composite/faction/warlord-tent.png', rect: { x: 60.6, y: 33.15, w: 193.16, h: 115.48 }, filterIds: ['warlord', 'all'], hotspotIds: ['warlord_tent'] },
                { id: 'firing_range_visual', label: '靶场', assetUrl: 'assets/map/composite/faction/firing-range.png', rect: { x: 40.75, y: 170.05, w: 248.3, h: 148.26 }, filterIds: ['warlord', 'all'], hotspotIds: ['firing_range'] },
                { id: 'rock_park_visual', label: '摇滚公园', assetUrl: 'assets/map/composite/faction/rock-park.png', rect: { x: 377.05, y: 55, w: 284, h: 145 }, filterIds: ['rock', 'all'], hotspotIds: ['rock_park'] },
                { id: 'rock_rehearsal_visual', label: '摇滚排练室', assetUrl: 'assets/map/composite/faction/rock-rehearsal.png', rect: { x: 390.3, y: 193.7, w: 262, h: 127 }, filterIds: ['rock', 'all'], hotspotIds: ['rock_rehearsal'] },
                { id: 'blackiron_training_visual', label: '黑铁会修炼场', assetUrl: 'assets/map/composite/faction/blackiron-training.png', rect: { x: 8.1, y: 352.95, w: 292, h: 98 }, filterIds: ['blackiron', 'all'], hotspotIds: ['blackiron_training'] },
                { id: 'blackiron_pavilion_visual', label: '黑铁阁', assetUrl: 'assets/map/composite/faction/blackiron-pavilion.png', rect: { x: 6.1, y: 418.4, w: 338, h: 153 }, filterIds: ['blackiron', 'all'], hotspotIds: ['blackiron_pavilion'] },
                { id: 'fallen_bar_visual', label: '堕落城酒吧', assetUrl: 'assets/map/composite/faction/fallen-bar.png', rect: { x: 360.65, y: 389.15, w: 252, h: 138 }, filterIds: ['fallen', 'all'], hotspotIds: ['fallen_bar'] },
                { id: 'fallen_street_visual', label: '堕落城商业街', assetUrl: 'assets/map/composite/faction/fallen-street.png', rect: { x: 597.9, y: 392.15, w: 212, h: 139 }, filterIds: ['fallen', 'all'], hotspotIds: ['fallen_street'] }
            ],
            staticAvatars: _pageStaticAvatars.faction,
            filters: [
                { id: 'warlord', label: '军阀', hotspotIds: ['warlord_base', 'warlord_tent', 'firing_range'], buttonRect: { x: 895, y: 108, w: 132, h: 42 } },
                { id: 'rock', label: '摇滚', hotspotIds: ['rock_park', 'rock_rehearsal'], buttonRect: { x: 895, y: 168, w: 132, h: 42 } },
                { id: 'blackiron', label: '黑铁会', hotspotIds: ['blackiron_training', 'blackiron_pavilion'], buttonRect: { x: 895, y: 228, w: 132, h: 42 } },
                { id: 'fallen', label: '堕落城', hotspotIds: ['fallen_bar', 'fallen_street'], buttonRect: { x: 895, y: 288, w: 132, h: 42 } },
                { id: 'all', label: '初始化', hotspotIds: ['warlord_base', 'warlord_tent', 'firing_range', 'rock_park', 'rock_rehearsal', 'blackiron_training', 'blackiron_pavilion', 'fallen_bar', 'fallen_street'], buttonRect: { x: 895, y: 348, w: 132, h: 42 } }
            ],
            defaultFilterId: 'all',
            hotspots: [
                { id: 'warlord_base', label: '军阀基地', sceneName: '地图-军阀基地', rect: { x: 42, y: 82, w: 236, h: 220 } },
                { id: 'warlord_tent', label: '军阀帐篷', sceneName: '地图-军阀帐篷', rect: { x: 56, y: 36, w: 218, h: 116 } },
                { id: 'firing_range', label: '靶场', sceneName: '地图-靶场', rect: { x: 48, y: 150, w: 228, h: 148 } },
                { id: 'rock_park', label: '摇滚公园', sceneName: '地图-摇滚公园', rect: { x: 380, y: 46, w: 238, h: 138 } },
                { id: 'rock_rehearsal', label: '摇滚排练室', sceneName: '地图-摇滚排练室', rect: { x: 384, y: 186, w: 224, h: 110 } },
                { id: 'blackiron_training', label: '黑铁会修炼场', sceneName: '地图-黑铁会修炼场', rect: { x: 36, y: 348, w: 248, h: 154 } },
                { id: 'blackiron_pavilion', label: '黑铁阁', sceneName: '地图-黑铁阁', rect: { x: 346, y: 413, w: 168, h: 74 } },
                { id: 'fallen_bar', label: '堕落城酒吧', sceneName: '地图-堕落城酒吧', rect: { x: 610, y: 396, w: 112, h: 92 } },
                { id: 'fallen_street', label: '堕落城商业街', sceneName: '地图-堕落城商业街', rect: { x: 724, y: 394, w: 132, h: 94 } }
            ]
        },
        defense: {
            id: 'defense',
            title: '废城/禁区',
            tabLabel: '废城/禁区',
            renderMode: 'assembled',
            backdropTheme: 'defense',
            backgroundUrl: 'assets/map/page-defense.png',
            width: 1031,
            height: 608,
            sceneVisuals: [
                { id: 'first_defense_visual', label: '第一防线', assetUrl: 'assets/map/composite/defense/first-defense.png', rect: { x: 60, y: 94.7, w: 285, h: 116 }, filterIds: ['first_line', 'all'], hotspotIds: ['first_defense'] },
                { id: 'alliance_dock_visual', label: '同盟卸货站', assetUrl: 'assets/map/composite/defense/alliance-dock.png', rect: { x: 38.75, y: 260.4, w: 270, h: 128 }, filterIds: ['restricted', 'all'], hotspotIds: ['alliance_dock'] },
                { id: 'alliance_corridor_visual', label: '同盟通路', assetUrl: 'assets/map/composite/defense/alliance-corridor.png', rect: { x: 46.4, y: 299.1, w: 277, h: 202 }, filterIds: ['restricted', 'all'], hotspotIds: ['alliance_corridor'] }
            ],
            staticAvatars: _pageStaticAvatars.defense,
            filters: [
                { id: 'first_line', label: '第一防线', hotspotIds: ['first_defense'], buttonRect: { x: 895, y: 201, w: 132, h: 42 } },
                { id: 'restricted', label: '禁区', hotspotIds: ['alliance_dock', 'alliance_corridor'], buttonRect: { x: 895, y: 261, w: 132, h: 42 } },
                { id: 'all', label: '初始化', hotspotIds: ['first_defense', 'alliance_dock', 'alliance_corridor'], buttonRect: { x: 895, y: 321, w: 132, h: 42 } }
            ],
            defaultFilterId: 'all',
            hotspots: [
                { id: 'first_defense', label: '第一防线', sceneName: '地图-第一防线防区', rect: { x: 46, y: 92, w: 252, h: 80 } },
                { id: 'alliance_dock', label: '同盟卸货站', sceneName: '地图-同盟卸货站', rect: { x: 37, y: 258, w: 284, h: 196 } },
                { id: 'alliance_corridor', label: '同盟通路', sceneName: '地图-同盟通路', rect: { x: 90, y: 314, w: 168, h: 72 } }
            ]
        },
        school: {
            id: 'school',
            title: '学校',
            tabLabel: '学校',
            renderMode: 'assembled',
            backdropTheme: 'school',
            backgroundUrl: 'assets/map/page-school.png',
            width: 1031,
            height: 608,
            sceneVisuals: [
                { id: 'workshop_visual', label: '大学地下工坊', assetUrl: 'assets/map/composite/school/workshop.png', rect: { x: 423.05, y: 259.2, w: 147, h: 73 }, filterIds: ['inside', 'all'], hotspotIds: ['workshop'] },
                { id: 'union_university_visual', label: '联合大学', assetUrl: 'assets/map/composite/school/union-university.png', rect: { x: 375.2, y: 443.2, w: 246.12, h: 106.9 }, filterIds: ['outside', 'all'], hotspotIds: ['union_university'] },
                { id: 'university_interior_visual', label: '大学内部', assetUrl: 'assets/map/composite/school/university-interior.png', rect: { x: 364.15, y: 350.6, w: 189, h: 117 }, filterIds: ['inside', 'all'], hotspotIds: ['university_interior'] },
                { id: 'university_playground_visual', label: '大学操场', assetUrl: 'assets/map/composite/school/university-playground.png', rect: { x: 591.85, y: 378.3, w: 193, h: 65 }, filterIds: ['inside', 'all'], hotspotIds: ['university_playground'] },
                { id: 'dorm_downstairs_visual', label: '大学宿舍楼下', assetUrl: 'assets/map/composite/school/dorm-downstairs.png', rect: { x: 195.75, y: 340.25, w: 185, h: 105 }, filterIds: ['inside', 'all'], hotspotIds: ['dorm_downstairs'] },
                { id: 'school_dormitory_visual', label: '大学宿舍', assetUrl: 'assets/map/composite/school/school-dormitory.png', rect: { x: 57.3, y: 276.35, w: 148, h: 85 }, filterIds: ['inside', 'all'], hotspotIds: ['school_dormitory'] },
                { id: 'office_visual', label: '教学楼办公室', assetUrl: 'assets/map/composite/school/office.png', rect: { x: 412.15, y: 47.6, w: 132, h: 66 }, filterIds: ['inside', 'all'], hotspotIds: ['office'] },
                { id: 'kendo_club_visual', label: '剑道社', assetUrl: 'assets/map/composite/school/kendo-club.png', rect: { x: 534.95, y: 160.5, w: 134, h: 68 }, filterIds: ['inside', 'all'], hotspotIds: ['kendo_club'] },
                { id: 'science_class_visual', label: '理科教室', assetUrl: 'assets/map/composite/school/science-class.png', rect: { x: 681.75, y: 164.45, w: 67, h: 45 }, filterIds: ['inside', 'all'], hotspotIds: ['science_class'] },
                { id: 'arts_class_visual', label: '文科教室', assetUrl: 'assets/map/composite/school/arts-class.png', rect: { x: 748.85, y: 164.45, w: 67, h: 45 }, filterIds: ['inside', 'all'], hotspotIds: ['arts_class'] },
                { id: 'teaching_interior_visual', label: '教学楼内部', assetUrl: 'assets/map/composite/school/teaching-interior.png', rect: { x: 423.05, y: 201.75, w: 230.4, h: 76.4 }, filterIds: ['inside', 'all'], hotspotIds: ['teaching_interior'] },
                { id: 'teaching_right_visual', label: '教学楼内部右侧', assetUrl: 'assets/map/composite/school/teaching-right.png', rect: { x: 652.95, y: 200.1, w: 162.49, h: 81.25 }, filterIds: ['inside', 'all'], hotspotIds: ['teaching_right'] }
            ],
            staticAvatars: _pageStaticAvatars.school,
            filters: [
                { id: 'inside', label: '学校内部', hotspotIds: ['workshop', 'university_interior', 'university_playground', 'dorm_downstairs', 'school_dormitory', 'office', 'kendo_club', 'science_class', 'arts_class', 'teaching_interior', 'teaching_right'], buttonRect: { x: 895, y: 201, w: 132, h: 42 } },
                { id: 'outside', label: '学校外部', hotspotIds: ['union_university'], buttonRect: { x: 895, y: 261, w: 132, h: 42 } },
                { id: 'all', label: '初始化', hotspotIds: ['workshop', 'union_university', 'university_interior', 'university_playground', 'dorm_downstairs', 'school_dormitory', 'office', 'kendo_club', 'science_class', 'arts_class', 'teaching_interior', 'teaching_right'], buttonRect: { x: 895, y: 321, w: 132, h: 42 } }
            ],
            defaultFilterId: 'all',
            dynamicAvatars: [
                { id: 'roommate', label: '室友', kind: 'roommateGender', hotspotId: 'school_dormitory', x: 78, y: 294, w: 48, h: 48 }
            ],
            hotspots: [
                { id: 'workshop', label: '大学地下工坊', sceneName: '地图-大学地下工坊', rect: { x: 423, y: 48, w: 134, h: 64 } },
                { id: 'union_university', label: '联合大学', sceneName: '地图-联合大学', rect: { x: 196, y: 340, w: 190, h: 102 } },
                { id: 'university_interior', label: '大学内部', sceneName: '地图-大学内部', rect: { x: 364, y: 350, w: 120, h: 90 } },
                { id: 'university_playground', label: '大学操场', sceneName: '地图-大学操场', rect: { x: 591, y: 378, w: 198, h: 64 } },
                { id: 'dorm_downstairs', label: '大学宿舍楼下', sceneName: '地图-大学宿舍楼下', rect: { x: 196, y: 340, w: 192, h: 102 } },
                { id: 'school_dormitory', label: '大学宿舍', sceneName: '地图-大学宿舍', rect: { x: 57, y: 274, w: 152, h: 72 } },
                { id: 'office', label: '教学楼办公室', sceneName: '地图-教学楼办公室', rect: { x: 412, y: 46, w: 146, h: 66 } },
                { id: 'kendo_club', label: '剑道社', sceneName: '地图-剑道社', rect: { x: 534, y: 160, w: 118, h: 70 } },
                { id: 'science_class', label: '理科教室', sceneName: '地图-理科教室', rect: { x: 681, y: 164, w: 90, h: 66 } },
                { id: 'arts_class', label: '文科教室', sceneName: '地图-文科教室', rect: { x: 748, y: 164, w: 92, h: 66 } },
                { id: 'teaching_interior', label: '教学楼内部', sceneName: '地图-教学楼内部', rect: { x: 423, y: 201, w: 182, h: 74 } },
                { id: 'teaching_right', label: '教学楼内部右侧', sceneName: '地图-教学楼内部右侧', rect: { x: 652, y: 200, w: 152, h: 76 } }
            ]
        }
    };

    var _xflLayoutOverrides = {
        faction: {
            rock_park: { x: 377.05, y: 55, w: 253.8, h: 115.1 },
            rock_rehearsal: { x: 390.3, y: 193.7, w: 219.9, h: 97.3 },
            blackiron_training: { x: 8.1, y: 352.95, w: 299.1, h: 100.1 },
            blackiron_pavilion: { x: 6.1, y: 418.4, w: 308.5, h: 123.6 },
            fallen_bar: { x: 360.65, y: 389.15, w: 222.6, h: 108.7 },
            fallen_street: { x: 597.9, y: 392.15, w: 182.7, h: 108.9 }
        },
        defense: {
            first_defense: { x: 60, y: 94.7, w: 255.1, h: 86.7 }
        },
        school: {
            workshop: { x: 423.05, y: 259.2, w: 147.3, h: 73.6 },
            union_university: { x: 375.2, y: 443.2, w: 198.4, h: 86.5 },
            university_interior: { x: 364.15, y: 350.6, w: 238.2, h: 86.8 },
            university_playground: { x: 591.85, y: 378.3, w: 191.2, h: 58.8 },
            dorm_downstairs: { x: 195.75, y: 340.25, w: 185.9, h: 105.5 },
            school_dormitory: { x: 57.3, y: 276.35, w: 148.8, h: 85.9 },
            office: { x: 412.15, y: 47.6, w: 132.3, h: 66.8 },
            kendo_club: { x: 534.95, y: 160.5, w: 134.3, h: 68.4 },
            science_class: { x: 681.75, y: 164.45, w: 67.1, h: 45.4 },
            arts_class: { x: 748.85, y: 164.45, w: 67.1, h: 45.4 },
            teaching_interior: { x: 423.05, y: 201.75, w: 190, h: 63.2 },
            teaching_right: { x: 652.95, y: 200.1, w: 134.8, h: 67 }
        }
    };

    applyXflLayoutOverrides();

    function applyXflLayoutOverrides() {
        var pageId;

        for (pageId in _xflLayoutOverrides) {
            if (!_xflLayoutOverrides.hasOwnProperty(pageId) || !_pages[pageId]) continue;
            applyPageLayoutOverrides(_pages[pageId], _xflLayoutOverrides[pageId]);
        }

        for (pageId in _pages) {
            if (!_pages.hasOwnProperty(pageId)) continue;
            syncCompositeHotspotRects(pageId);
        }
    }

    function applyPageLayoutOverrides(page, overrides) {
        var hotspots = page && page.hotspots ? page.hotspots : [];
        var i;

        // Keep large composite scene rects hand-tuned; only compact hotspots map 1:1 to XFL bounds.
        for (i = 0; i < hotspots.length; i++) {
            if (overrides[hotspots[i].id]) {
                hotspots[i].rect = overrides[hotspots[i].id];
            }
        }
    }

    function syncCompositeHotspotRects(pageId) {
        var page = _pages[pageId];
        var hotspots = page && page.hotspots ? page.hotspots : [];
        var sceneVisuals = page && page.sceneVisuals ? page.sceneVisuals : [];
        var i;

        if (!page || !sceneVisuals.length) return;

        for (i = 0; i < hotspots.length; i++) {
            hotspots[i].rect = buildSceneVisualUnionRect(sceneVisuals, hotspots[i].id) || hotspots[i].rect;
        }
    }

    function buildSceneVisualUnionRect(sceneVisuals, hotspotId) {
        var rect = null;
        var i;

        for (i = 0; i < sceneVisuals.length; i++) {
            var visual = sceneVisuals[i];
            if (!visual || !visual.rect || !visual.hotspotIds || visual.hotspotIds.indexOf(hotspotId) < 0) continue;

            if (!rect) {
                rect = {
                    x: visual.rect.x,
                    y: visual.rect.y,
                    w: visual.rect.w,
                    h: visual.rect.h
                };
                continue;
            }

            var minX = Math.min(rect.x, visual.rect.x);
            var minY = Math.min(rect.y, visual.rect.y);
            var maxX = Math.max(rect.x + rect.w, visual.rect.x + visual.rect.w);
            var maxY = Math.max(rect.y + rect.h, visual.rect.y + visual.rect.h);

            rect.x = +minX.toFixed(2);
            rect.y = +minY.toFixed(2);
            rect.w = +(maxX - minX).toFixed(2);
            rect.h = +(maxY - minY).toFixed(2);
        }

        return rect;
    }

    function getUnlockGroupMeta(groupId) {
        return groupId ? (_unlockGroups[groupId] || null) : null;
    }

    function getPageUnlockMapping(pageId) {
        return _pageUnlockGroups[resolvePageId(pageId)] || {};
    }

    function getSourceRect(pageId, hotspotId) {
        var pageRects = _xflSourceRects[resolvePageId(pageId)] || {};
        return hotspotId ? (pageRects[hotspotId] || null) : null;
    }

    function isHandTunedLayout(hotspotId) {
        return !!_handTunedLayoutIds[hotspotId];
    }

    function getLayoutAuditMeta(pageId, hotspotId) {
        var sourceRect = getSourceRect(pageId, hotspotId);
        var hotspot = findHotspot(pageId, hotspotId);
        var dx = null;
        var dy = null;
        var status = 'missing';
        var note = 'missing_xfl_ref';

        if (sourceRect && hotspot) {
            dx = +(hotspot.rect.x - sourceRect.x).toFixed(2);
            dy = +(hotspot.rect.y - sourceRect.y).toFixed(2);

            if (isHandTunedLayout(hotspotId)) {
                status = 'hand_tuned';
                note = 'hand_tuned_composite_rect';
            } else if (Math.abs(dx) <= 0.5 && Math.abs(dy) <= 0.5) {
                status = 'exact';
                note = 'xfl_aligned';
            } else if (Math.abs(dx) <= 8 && Math.abs(dy) <= 8) {
                status = 'near';
                note = 'minor_delta';
            } else {
                status = 'review';
                note = 'large_delta';
            }
        }

        return {
            status: status,
            note: note,
            dx: dx,
            dy: dy,
            sourceRect: sourceRect
        };
    }

    function getHotspotUnlockGroup(pageId, hotspotId) {
        var mapping = getPageUnlockMapping(pageId);
        return hotspotId ? ((mapping.hotspots || {})[hotspotId] || '') : '';
    }

    function getFilterUnlockGroup(pageId, filterId) {
        var mapping = getPageUnlockMapping(pageId);
        return filterId ? ((mapping.filters || {})[filterId] || '') : '';
    }

    function normalizeUnlockFlags(unlocks) {
        var normalized = {};
        var groupId;
        unlocks = unlocks || {};

        for (groupId in _unlockGroups) {
            normalized[groupId] = unlocks[groupId] !== undefined ? !!unlocks[groupId] : true;
        }

        return normalized;
    }

    function evaluateCondition(unlocks, conditionId) {
        var groupId;
        var normalized = normalizeUnlockFlags(unlocks);

        if (!conditionId) return true;

        for (groupId in _unlockGroups) {
            if (_unlockGroups[groupId].conditionId === conditionId) {
                return !!normalized[groupId];
            }
        }

        return true;
    }

    function buildPageDisplayConditions(pageId) {
        var mapping = getPageUnlockMapping(pageId);
        var used = {};
        var groupId;
        var items = [];

        function collect(source) {
            var key;
            for (key in (source || {})) {
                groupId = source[key];
                if (groupId && !used[groupId] && _unlockGroups[groupId]) {
                    used[groupId] = true;
                    items.push({
                        id: _unlockGroups[groupId].conditionId,
                        kind: 'snapshotFlag',
                        path: 'unlocks.' + groupId,
                        label: _unlockGroups[groupId].label
                    });
                }
            }
        }

        collect(mapping.filters);
        collect(mapping.hotspots);
        return items;
    }

    function buildPageFlashHints(page) {
        var filters = page.filters || [];
        var hints = [];
        var i;

        for (i = 0; i < filters.length; i++) {
            var unlockGroup = getFilterUnlockGroup(page.id, filters[i].id);
            var meta = getUnlockGroupMeta(unlockGroup);
            if (!meta || !filters[i].buttonRect) continue;

            hints.push({
                id: 'hint.' + page.id + '.' + filters[i].id,
                kind: 'lockedFilter',
                filterId: filters[i].id,
                pageId: page.id,
                conditionId: meta.conditionId,
                whenValue: false,
                label: meta.lockedReason
            });
        }

        return hints;
    }

    function getPageFlashHints(pageId) {
        return buildPageFlashHints(getPage(pageId));
    }

    function getPageDisplayConditions(pageId) {
        return buildPageDisplayConditions(resolvePageId(pageId));
    }

    function buildHotspotStates(unlocks) {
        var normalized = normalizeUnlockFlags(unlocks);
        var states = {};
        var ids = getAllHotspotIds();
        var i;

        for (i = 0; i < ids.length; i++) {
            var hotspotId = ids[i];
            var pageId = findHotspotPageId(hotspotId);
            var unlockGroup = getHotspotUnlockGroup(pageId, hotspotId);
            var meta = getUnlockGroupMeta(unlockGroup);
            var enabled = meta ? !!normalized[unlockGroup] : true;

            states[hotspotId] = {
                enabled: enabled,
                unlockGroup: unlockGroup || '',
                lockedReason: enabled || !meta ? '' : meta.lockedReason
            };
        }

        return states;
    }

    function buildEnabledHotspotIds(unlocks) {
        var states = buildHotspotStates(unlocks);
        var ids = [];
        var hotspotId;

        for (hotspotId in states) {
            if (states[hotspotId].enabled) {
                ids.push(hotspotId);
            }
        }

        return ids;
    }

    function getPage(id) {
        return _pages[_pageAliases[id] || id] || _pages.base;
    }

    function getPageOrder() {
        return _pageOrder.slice();
    }

    function isLayerRelationFilter(pageId, filterId) {
        return resolvePageId(pageId) === 'base' && filterId === 'hierarchy';
    }

    function getManifest() {
        return {
            version: 2,
            id: 'cf7.map',
            schema: 'cf7.map/manifest-v2',
            sourceRefs: _sourceRefs,
            unlockGroups: _unlockGroups,
            pageOrder: _pageOrder.slice(),
            pageAliases: _pageAliases,
            pages: _pages
        };
    }

    function resolvePageId(id) {
        return _pageAliases[id] || id || _pageOrder[0];
    }

    function getAllHotspotIds() {
        var ids = [];
        var seen = {};
        for (var i = 0; i < _pageOrder.length; i++) {
            var page = getPage(_pageOrder[i]);
            var hotspots = page.hotspots || [];
            for (var j = 0; j < hotspots.length; j++) {
                if (!seen[hotspots[j].id]) {
                    seen[hotspots[j].id] = true;
                    ids.push(hotspots[j].id);
                }
            }
        }
        return ids;
    }

    function findHotspot(pageId, hotspotId) {
        var page = getPage(pageId);
        var hotspots = page.hotspots || [];
        for (var i = 0; i < hotspots.length; i++) {
            if (hotspots[i].id === hotspotId) {
                return hotspots[i];
            }
        }
        return null;
    }

    function findHotspotPageId(hotspotId) {
        for (var i = 0; i < _pageOrder.length; i++) {
            var page = getPage(_pageOrder[i]);
            var hotspots = page.hotspots || [];
            for (var j = 0; j < hotspots.length; j++) {
                if (hotspots[j].id === hotspotId) {
                    return page.id;
                }
            }
        }
        return '';
    }

    function findFilter(pageId, filterId) {
        var page = getPage(pageId);
        var filters = page.filters || [];
        for (var i = 0; i < filters.length; i++) {
            if (filters[i].id === filterId) {
                return filters[i];
            }
        }
        return null;
    }

    function getVisibleHotspots(pageId, filterId) {
        var page = getPage(pageId);
        var hotspots = (page.hotspots || []).slice();
        var filter = findFilter(page.id, filterId);
        var lookup = {};
        var visible = [];
        var i;

        if (!filter || !(filter.hotspotIds || []).length) {
            return hotspots;
        }

        for (i = 0; i < filter.hotspotIds.length; i++) {
            lookup[filter.hotspotIds[i]] = true;
        }

        for (i = 0; i < hotspots.length; i++) {
            if (lookup[hotspots[i].id]) {
                visible.push(hotspots[i]);
            }
        }

        return visible;
    }

    function getVisibleSceneVisuals(pageId, filterId) {
        var page = getPage(pageId);
        var visuals = (page.sceneVisuals || []).slice();
        var visible = [];
        var i;

        if (!filterId || filterId === 'all') {
            return visuals;
        }

        for (i = 0; i < visuals.length; i++) {
            var filterIds = visuals[i].filterIds || [];
            if (!filterIds.length || filterIds.indexOf(filterId) >= 0) {
                visible.push(visuals[i]);
            }
        }

        return visible;
    }

    function buildFilterIdsForHotspot(page, hotspotId) {
        var filterIds = [];
        var filters = page.filters || [];
        for (var i = 0; i < filters.length; i++) {
            if ((filters[i].hotspotIds || []).indexOf(hotspotId) >= 0) {
                filterIds.push(filters[i].id);
            }
        }
        return filterIds;
    }

    function exportPage(pageId) {
        var page = getPage(pageId);
        var filters = page.filters || [];
        var hotspots = page.hotspots || [];
        var staticAvatars = page.staticAvatars || [];
        var slots = page.dynamicAvatars || [];
        var sceneNodes = [];
        var exportedHotspots = [];
        var markers = [];

        for (var i = 0; i < filters.length; i++) {
            var filterUnlockGroup = getFilterUnlockGroup(page.id, filters[i].id);
            var filterMeta = getUnlockGroupMeta(filterUnlockGroup);
            sceneNodes.push({
                id: filters[i].id,
                label: filters[i].label,
                kind: 'filter',
                hotspotIds: (filters[i].hotspotIds || []).slice(),
                buttonRect: filters[i].buttonRect || null,
                displayConditions: filterMeta ? [filterMeta.conditionId] : [],
                interactionState: {
                    enabledBy: filterMeta ? ('unlock.' + filterUnlockGroup) : 'always',
                    lockedReason: filterMeta ? filterMeta.lockedReason : ''
                }
            });
        }

        for (var v = 0; v < (page.sceneVisuals || []).length; v++) {
            sceneNodes.push({
                id: page.sceneVisuals[v].id,
                label: page.sceneVisuals[v].label,
                kind: 'sceneVisual',
                asset: page.sceneVisuals[v].assetUrl,
                rect: page.sceneVisuals[v].rect,
                filterIds: (page.sceneVisuals[v].filterIds || []).slice(),
                hotspotIds: (page.sceneVisuals[v].hotspotIds || []).slice()
            });
        }

        for (var j = 0; j < hotspots.length; j++) {
            var hotspotUnlockGroup = getHotspotUnlockGroup(page.id, hotspots[j].id);
            var hotspotMeta = getUnlockGroupMeta(hotspotUnlockGroup);
            exportedHotspots.push({
                id: hotspots[j].id,
                label: hotspots[j].label,
                rect: hotspots[j].rect,
                sourceRect: getSourceRect(page.id, hotspots[j].id),
                target: {
                    type: 'scene',
                    sceneName: hotspots[j].sceneName
                },
                display: {
                    filterIds: buildFilterIdsForHotspot(page, hotspots[j].id),
                    when: hotspotMeta ? [hotspotMeta.conditionId] : []
                },
                interactionState: {
                    enabledBy: hotspotMeta ? ('unlock.' + hotspotUnlockGroup) : 'always',
                    lockedReason: hotspotMeta ? hotspotMeta.lockedReason : ''
                },
                layoutAudit: getLayoutAuditMeta(page.id, hotspots[j].id)
            });
        }

        for (var k = 0; k < staticAvatars.length; k++) {
            markers.push({
                id: staticAvatars[k].id,
                kind: 'staticAvatar',
                label: staticAvatars[k].label || '',
                hotspotId: staticAvatars[k].hotspotId || null,
                asset: staticAvatars[k].assetUrl,
                rect: {
                    x: staticAvatars[k].x,
                    y: staticAvatars[k].y,
                    w: staticAvatars[k].w,
                    h: staticAvatars[k].h
                }
            });
        }

        for (k = 0; k < slots.length; k++) {
            markers.push({
                id: slots[k].id,
                kind: 'dynamicAvatar',
                stateKey: slots[k].kind,
                hotspotId: slots[k].hotspotId || null,
                rect: {
                    x: slots[k].x,
                    y: slots[k].y,
                    w: slots[k].w,
                    h: slots[k].h
                }
            });
        }

        return {
            id: page.id,
            title: page.title,
            tabLabel: page.tabLabel,
            size: {
                width: page.width,
                height: page.height
            },
            layers: [
                {
                    id: 'background',
                    kind: 'background',
                    asset: page.backgroundUrl,
                    width: page.width,
                    height: page.height
                }
            ],
            sceneNodes: sceneNodes,
            hotspots: exportedHotspots,
            markers: markers,
            flashHints: buildPageFlashHints(page),
            displayConditions: buildPageDisplayConditions(page.id),
            interactionState: {
                defaultFilterId: page.defaultFilterId || '',
                snapshotVersion: 2,
                renderMode: page.renderMode || 'background',
                backdropTheme: page.backdropTheme || 'default'
            }
        };
    }

    function exportManifest() {
        var pages = {};
        for (var i = 0; i < _pageOrder.length; i++) {
            pages[_pageOrder[i]] = exportPage(_pageOrder[i]);
        }
        return {
            version: 2,
            id: 'cf7.map',
            schema: 'cf7.map/manifest-v2',
            sourceRefs: _sourceRefs,
            unlockGroups: _unlockGroups,
            pageOrder: _pageOrder.slice(),
            pageAliases: _pageAliases,
            pages: pages
        };
    }

    return {
        getManifest: getManifest,
        getPage: getPage,
        getPageOrder: getPageOrder,
        getUnlockGroupMeta: getUnlockGroupMeta,
        getHotspotUnlockGroup: getHotspotUnlockGroup,
        getFilterUnlockGroup: getFilterUnlockGroup,
        getPageFlashHints: getPageFlashHints,
        getPageDisplayConditions: getPageDisplayConditions,
        getSourceRect: getSourceRect,
        isHandTunedLayout: isHandTunedLayout,
        getLayoutAuditMeta: getLayoutAuditMeta,
        normalizeUnlockFlags: normalizeUnlockFlags,
        evaluateCondition: evaluateCondition,
        buildHotspotStates: buildHotspotStates,
        buildEnabledHotspotIds: buildEnabledHotspotIds,
        resolvePageId: resolvePageId,
        isLayerRelationFilter: isLayerRelationFilter,
        getAllHotspotIds: getAllHotspotIds,
        findHotspot: findHotspot,
        findHotspotPageId: findHotspotPageId,
        findFilter: findFilter,
        getVisibleHotspots: getVisibleHotspots,
        getVisibleSceneVisuals: getVisibleSceneVisuals,
        exportPage: exportPage,
        exportManifest: exportManifest
    };
})();

var MapManifest = MapPanelData.exportManifest();
