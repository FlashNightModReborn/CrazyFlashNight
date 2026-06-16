// 任务系统_WebView.as — WebView 任务面板 AS2 端桥接安装
// 详细实现见 org.flashNight.arki.task.TaskPanelService。
TaskPanelService.install();
// 成就服务（任务面板第三 tab）：详细实现见 org.flashNight.arki.achievement.AchievementService。
// install 仅注册命令/订阅/发起非阻塞加载，不碰存档数据（此刻存档未读）。
AchievementService.install();
