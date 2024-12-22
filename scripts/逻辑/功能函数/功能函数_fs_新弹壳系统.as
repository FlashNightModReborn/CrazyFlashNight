import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.neur.Event.*;

ShellSystem.initialize(); //初始化信息加载

EventBus.getInstance().subscribe("地图已切换", function() {
	ShellSystem.initializeBulletPools();
}, null); // 地图变动时，重新初始化子弹池
