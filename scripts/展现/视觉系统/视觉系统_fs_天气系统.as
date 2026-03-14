/**
 * 视觉系统_fs_天气系统.as — 兼容垫片
 *
 * 核心逻辑已迁移至 org.flashNight.arki.weather.WeatherSystem（class 化单例）。
 * 本帧脚本负责：
 * 1. 创建单例并触发异步初始化
 * 2. 挂载 _root.天气系统 最低兼容引用
 * 3. 保留 _root.配置环境信息() 工具函数（依赖 _root 工具函数，暂不迁移）
 */
import org.flashNight.arki.weather.*;

// ==================== 创建单例 + 初始化 ====================

var ws:WeatherSystem = WeatherSystem.getInstance();
ws.setupLegacyBridge();
ws.initialize();
_root.天气系统 = ws;

// ==================== _root.配置环境信息 兼容桥接 ====================
// 核心逻辑已迁移至 EnvironmentConfig.parseEnvironmentInfo
_root.配置环境信息 = EnvironmentConfig.parseEnvironmentInfo;
